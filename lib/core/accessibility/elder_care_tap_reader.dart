import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../services/voice_service.dart';

/// 轻触文字朗读：点击屏幕上任意文字段落时朗读该段内容
///
/// 通过命中测试找到被点击的 [RenderParagraph]，取出纯文本交给系统 TTS。
/// 只读取文字，不拦截点击，原有交互不受影响。
class ElderCareTapReader extends StatelessWidget {
  const ElderCareTapReader({
    super.key,
    required this.child,
    this.onRead,
  });

  final Widget child;

  /// 朗读回调，为空时使用全局 [VoiceService]；测试可注入
  final ValueChanged<String>? onRead;

  void _handlePointerUp(PointerUpEvent event) {
    final text = _textAt(event.position, event.viewId);
    if (text == null || text.isEmpty) return;
    final onRead = this.onRead;
    if (onRead != null) {
      onRead(text);
      return;
    }
    VoiceService.instance.speakReading(
      VoiceService.condenseForSpeech(text, maxChars: 200),
    );
  }

  String? _textAt(Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderParagraph) {
        final text = target.text
            .toPlainText(includeSemanticsLabels: false, includePlaceholders: false)
            .trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: _handlePointerUp,
      child: child,
    );
  }
}
