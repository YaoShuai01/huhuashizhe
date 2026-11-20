import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../services/voice_service.dart';

/// 朗读板块：包裹需要整块朗读的内容（帖子卡片、消息条目、评论等）
///
/// 老年关怀模式下长按板块内任意文字，会朗读该板块的全部内容，
/// 而不是只有手指下的一行字。
///
/// [readText] 可指定朗读文本，用于跳过时间、点赞等不需要朗读的区域。
class ElderCareBlock extends SingleChildRenderObjectWidget {
  // SingleChildRenderObjectWidget 自带 child 字段，无法用 super 参数转发
  // ignore: use_super_parameters
  const ElderCareBlock({super.key, this.readText, Widget? child})
      : super(child: child);

  /// 自定义朗读文本，为空时朗读板块内全部文字
  final String? readText;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderElderCareBlock(readText: readText);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderElderCareBlock).readText = readText;
  }
}

class _RenderElderCareBlock extends RenderProxyBox {
  _RenderElderCareBlock({this.readText});

  String? readText;
}

/// 长按板块文字朗读
///
/// 通过命中测试找到被长按的位置：
/// - 落在 [ElderCareBlock] 内时，朗读该板块的全部文字；
/// - 否则退化为朗读手指下的一段文字。
///
/// 只读取内容，不拦截点击、滑动与长按，原有交互不受影响。
class ElderCareReader extends StatefulWidget {
  const ElderCareReader({
    super.key,
    required this.child,
    this.onRead,
  });

  final Widget child;

  /// 朗读回调，为空时使用全局 [VoiceService]；测试可注入
  final ValueChanged<String>? onRead;

  @override
  State<ElderCareReader> createState() => _ElderCareReaderState();
}

class _ElderCareReaderState extends State<ElderCareReader> {
  /// 判定为长按的时间
  static const Duration _holdDuration = Duration(milliseconds: 400);

  /// 手指移动超过该距离视为滑动，取消朗读
  static const double _moveTolerance = 32;

  Timer? _holdTimer;
  Offset? _downPosition;
  int? _viewId;
  int? _pointer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downPosition = event.position;
    _viewId = event.viewId;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () {
      final position = _downPosition;
      final viewId = _viewId;
      if (position == null || viewId == null) return;
      _readAt(position, viewId);
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final start = _downPosition;
    if (start != null && (event.position - start).distance > _moveTolerance) {
      _reset();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _reset();
  }

  void _reset() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _downPosition = null;
    _viewId = null;
    _pointer = null;
  }

  void _readAt(Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);

    RenderObject? block;
    RenderParagraph? paragraph;
    for (final entry in result.path) {
      final target = entry.target;
      if (block == null && target is _RenderElderCareBlock) {
        block = target;
      }
      if (paragraph == null &&
          target is RenderParagraph &&
          _paragraphText(target).isNotEmpty) {
        paragraph = target;
      }
    }

    // 优先朗读显式标记的板块；未标记时自动向上找最近的文字板块
    final target = block ?? (paragraph == null ? null : _autoBlock(paragraph));
    final text = target == null
        ? (paragraph == null ? null : _paragraphText(paragraph))
        : _blockText(target);
    if (text == null || text.isEmpty) return;
    _read(text);
  }

  /// 未标记板块时，向上寻找最近的、包含多段文字的板块
  RenderObject? _autoBlock(RenderParagraph paragraph) {
    RenderObject node = paragraph;
    for (var depth = 0; depth < 8; depth++) {
      final parent = node.parent;
      if (parent == null) return null;
      node = parent;
      if (_paragraphCount(node) >= 2) return node;
    }
    return null;
  }

  /// 统计板块内有效文字段落数，达到 2 段即停止
  int _paragraphCount(RenderObject node) {
    var count = 0;

    void visit(RenderObject child) {
      if (count >= 2) return;
      if (child is RenderParagraph) {
        if (_paragraphText(child).isNotEmpty) count++;
        return;
      }
      child.visitChildren(visit);
    }

    visit(node);
    return count;
  }

  /// 板块内全部文字，按渲染顺序逐行拼接
  String _blockText(RenderObject block) {
    if (block is _RenderElderCareBlock) {
      final readText = block.readText?.trim();
      if (readText != null && readText.isNotEmpty) return readText;
    }

    final parts = <String>[];

    void collect(RenderObject node) {
      if (node is RenderParagraph) {
        final text = _paragraphText(node);
        if (text.isNotEmpty && (parts.isEmpty || parts.last != text)) {
          parts.add(text);
        }
        return;
      }
      node.visitChildren(collect);
    }

    collect(block);
    return parts.join('\n');
  }

  String _paragraphText(RenderParagraph paragraph) {
    return paragraph.text
        .toPlainText(
          includeSemanticsLabels: false,
          includePlaceholders: false,
        )
        .trim();
  }

  void _read(String text) {
    final onRead = widget.onRead;
    if (onRead != null) {
      onRead(text);
      return;
    }
    VoiceService.instance.speakReading(
      VoiceService.condenseForSpeech(text, maxChars: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: widget.child,
    );
  }
}
