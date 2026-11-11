import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 视觉板UDP图传客户端
///
/// 协议对应 esp32_vision/main/vision_udp.h：
/// 命令（文本）：VSTART/VSTOP/VSNAP/VINFO/VSET/VFLIP/VMIR → 端口8889
/// 帧数据（二进制，22字节头）：
///   [0-1]='H''V' [2]=type(1流/2照片) [3]=flags
///   [4-7]=photo_id [8-11]=frame_seq [12-13]=seg_idx [14-15]=seg_cnt
///   [16-19]=total_len [20-21]=seg_len [22+]=payload
/// UDP分段按 frame_seq 重组，收齐 seg_cnt 段拼出完整JPEG。
///
/// 地址发现：ESP32 softAP 不保证把手机的广播帧转发给其他客户端，
/// 因此发现阶段对飞控子网 192.168.4.2~.9 逐一单播探测（客户端间单播必达），
/// 收到板子应答后锁定其IP，之后所有命令单播直达；断流超时自动重新搜索。
class VisionStreamService {
  VisionStreamService({this.visionPort = 8889});

  final int visionPort;

  /// 飞控子网候选地址（手机通常占.2，视觉板在其后）
  static const List<String> _sweepTargets = [
    '192.168.4.3', '192.168.4.2', '192.168.4.4', '192.168.4.5',
    '192.168.4.6', '192.168.4.7', '192.168.4.8', '192.168.4.9',
  ];

  /// 推流画质档位（对应固件 VSTART res fps q）
  /// res: k_cam_res 索引（2=XGA 1024x768, 3=HD 1280x720, 5=UXGA 1600x1200）
  /// q: JPEG质量，数字越小越清晰（码率随之升高）
  /// 三档码率都控制在WiFi UDP可承载范围（约1MB/s），取舍在清晰度与帧率
  static const List<(String, int, int, int)> profiles = [
    ('流畅', 2, 25, 15),   // XGA 25fps：帧率优先，操控跟手
    ('均衡', 3, 15, 10),   // HD 720p 15fps：画质与流畅兼顾
    ('高清', 5, 8, 9),     // UXGA 1600x1200 8fps：细节优先，用于病虫害识别
  ];

  /// 当前档位（默认均衡）
  int _profileIdx = 1;
  int get profileIndex => _profileIdx;
  String get profileLabel => profiles[_profileIdx].$1;

  String get _startCmd {
    final p = profiles[_profileIdx];
    return 'VSTART ${p.$2} ${p.$3} ${p.$4}';
  }

  /// 切换画质档位并立即下发（会重配传感器，约0.5秒黑屏后恢复）
  void setProfile(int index) {
    if (index < 0 || index >= profiles.length) return;
    _profileIdx = index;
    if (!_discovering && _boardIp != null) {
      _lastVstartAt = DateTime.now();
      _sendTo(_boardIp!, _startCmd);
      statusNotifier.value = '切换画质：${profiles[index].$1}';
    }
  }

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _keepAlive;

  // 发现状态
  int _sweepIdx = 0;
  bool _discovering = true;
  bool _everGotFrame = false; // 本次连接后是否收到过画面
  String? _boardIp;           // 已锁定的视觉板地址
  String? _lastSentTarget;    // 最近一次单播探测的目标（用于应答配对）
  DateTime _lastFrameAt = DateTime.now();
  DateTime _lastVstartAt = DateTime.now(); // 最近一次发VSTART（防频发）

  // 分帧重组缓冲：key = frame_seq
  final Map<int, _PendingFrame> _pending = {};

  final ValueNotifier<String> statusNotifier = ValueNotifier('未启动');
  final ValueNotifier<int> fpsNotifier = ValueNotifier(0);
  /// 实时接收码率（KB/s），用于判断链路是否被码头堵塞
  final ValueNotifier<int> kbpsNotifier = ValueNotifier(0);
  final ValueNotifier<Uint8List?> frameNotifier = ValueNotifier(null);
  final ValueNotifier<Uint8List?> photoNotifier = ValueNotifier(null);
  final ValueNotifier<bool> streamingNotifier = ValueNotifier(false);

  int _fpsCount = 0;
  int _byteCount = 0;
  DateTime _fpsT0 = DateTime.now();

  bool get streaming => streamingNotifier.value;

  /// 初始化socket并开始图传
  Future<void> start() async {
    _socket?.close();
    _sub?.cancel();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _sub = _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        // 一次事件内把接收缓冲里的包全部读空：高码率图传每秒上千个UDP包，
        // 一个事件只读一个包会积压溢出，导致大量分段丢失、整帧被弃
        Datagram? dg;
        while ((dg = _socket!.receive()) != null) {
          _onData(dg!);
        }
      }
    });
    _discovering = true;
    _everGotFrame = false;
    _sweepIdx = 0;
    _lastFrameAt = DateTime.now();
    streamingNotifier.value = true;
    statusNotifier.value = '正在搜索视觉板...';
    _keepAlive?.cancel();
    // 发现阶段500ms一跳用VINFO探测（不触碰摄像头、无副作用）；
    // 锁定地址后发一次VSTART即开始推流，稳态不再发周期命令——
    // VSTART每到达一次板子都会重配传感器PLL（几百ms不出帧），高频补发会导致永远无画面
    _keepAlive = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!streamingNotifier.value) return;
      // 清理长时间未拼齐的残留分段（UDP丢段）
      final cutoff = DateTime.now().subtract(const Duration(seconds: 2));
      _pending.removeWhere((_, f) => f.createdAt.isBefore(cutoff));
      if (_discovering) {
        final target = _sweepTargets[_sweepIdx % _sweepTargets.length];
        _sweepIdx++;
        _lastSentTarget = target;
        final lastOctet = target.split('.').last;
        statusNotifier.value = '正在搜索视觉板(.$lastOctet)...';
        _sendTo(target, 'VINFO');
      } else if (_everGotFrame) {
        // 之前出过画面：断流9秒重新搜索（板子可能掉线重连换了IP）
        if (DateTime.now().difference(_lastFrameAt).inSeconds > 9) {
          _discovering = true;
          _sweepIdx = 0;
          statusNotifier.value = '画面中断，重新搜索视觉板...';
        }
      } else {
        // 从未出过画面：板子应答正常，但帧没到达（大包传输受阻或摄像头无输出）
        // 每15秒单次重试VSTART（VSTART有重配传感器副作用，严禁频发）
        final now = DateTime.now();
        if (now.difference(_lastVstartAt).inSeconds >= 15) {
          _lastVstartAt = now;
          _sendTo(_boardIp!, _startCmd);
        }
        if (now.difference(_lastFrameAt).inSeconds > 6) {
          statusNotifier.value =
              '板子已应答但画面未到达\n用手机浏览器打开 http://$_boardIp/stream 验证';
        }
      }
    });
  }

  /// 停止图传
  void stop() {
    _keepAlive?.cancel();
    sendCommand('VSTOP');
    streamingNotifier.value = false;
    statusNotifier.value = '已停止';
    _pending.clear();
  }

  /// 发送文本命令：已锁定地址则单播直达，否则对全部候选地址发送
  void sendCommand(String cmd) {
    final sock = _socket;
    if (sock == null) {
      statusNotifier.value = '未初始化';
      return;
    }
    if (!_discovering && _boardIp != null) {
      _sendTo(_boardIp!, cmd);
      return;
    }
    var sent = false;
    for (final t in _sweepTargets) {
      if (_sendTo(t, cmd)) sent = true;
    }
    if (!sent) {
      statusNotifier.value = '发送失败：请确认已连接 HuHuaShiZhe-Drone 热点';
    }
  }

  bool _sendTo(String ip, String cmd) {
    final sock = _socket;
    if (sock == null) return false;
    try {
      return sock.send(cmd.codeUnits, InternetAddress(ip), visionPort) > 0;
    } catch (_) {
      return false;
    }
  }

  /// 状态栏显示截断（应答文本可能较长）
  static String _clip(String text, [int max = 46]) =>
      text.length > max ? '${text.substring(0, max)}…' : text;

  /// 请求高清拍照（视觉板会暂停推流→换分辨率→回0x02帧→恢复）
  void requestSnapshot() {
    sendCommand('VSNAP');
    statusNotifier.value = '拍照中...';
  }

  void dispose() {
    if (streamingNotifier.value) {
      try {
        sendCommand('VSTOP');
      } catch (_) {}
    }
    _keepAlive?.cancel();
    _sub?.cancel();
    _socket?.close();
    statusNotifier.dispose();
    fpsNotifier.dispose();
    kbpsNotifier.dispose();
    frameNotifier.dispose();
    photoNotifier.dispose();
    streamingNotifier.dispose();
  }

  // ==================== 数据解析 ====================

  void _onData(Datagram dg) {
    final data = dg.data;
    _byteCount += data.length;
    if (data.length < 22 || data[0] != 0x48 || data[1] != 0x56) {
      // 非帧数据：板子的文本应答（VOK/VERR开头）
      final text = utf8.decode(data, allowMalformed: true).trim();
      if (text.startsWith('VOK') || text.startsWith('VERR')) {
        // VINFO应答带有板子IP，直接精确锁定（比来源配对更可靠）
        final ipMatch =
            RegExp(r'ip=(\d+\.\d+\.\d+\.\d+)').firstMatch(text);
        if (_discovering) {
          final lockedIp = ipMatch?.group(1) ?? _lastSentTarget;
          if (lockedIp != null) {
            _boardIp = lockedIp;
            _discovering = false;
            _lastVstartAt = DateTime.now();
            statusNotifier.value = '已连接视觉板 $_boardIp';
            // 锁定后只发一次VSTART启动推流（带当前画质档位参数）
            _sendTo(_boardIp!, _startCmd);
            return;
          }
        }
        statusNotifier.value = '视觉板: ${_clip(text)}';
      }
      return;
    }

    final bd = ByteData.sublistView(data);
    final type = data[2];
    final frameSeq = bd.getUint32(8, Endian.little);
    final segIdx = bd.getUint16(12, Endian.little);
    final segCnt = bd.getUint16(14, Endian.little);
    final segLen = bd.getUint16(20, Endian.little);
    if (segCnt == 0 || segCnt > 4096) return;
    if (data.length < 22 + segLen) return;

    final key = (type << 32) | frameSeq;
    final pending =
        _pending.putIfAbsent(key, () => _PendingFrame(segCnt, DateTime.now()));
    pending.segments[segIdx] = Uint8List.sublistView(data, 22, 22 + segLen);

    if (pending.segments.length < segCnt) {
      // 清理过期未拼完的帧（UDP丢段）
      if (_pending.length > 4) {
        final cutoff = DateTime.now().subtract(const Duration(seconds: 1));
        _pending.removeWhere(
            (_, f) => f.createdAt.isBefore(cutoff) && f.segments.length < f.segCnt);
      }
      return;
    }

    // 拼完整JPEG
    final parts = pending.segments;
    final total = parts.values.fold<int>(0, (a, b) => a + b.length);
    final jpeg = Uint8List(total);
    var off = 0;
    for (var i = 0; i < segCnt; i++) {
      final seg = parts[i];
      if (seg == null) return; // 缺段，放弃
      jpeg.setRange(off, off + seg.length, seg);
      off += seg.length;
    }
    _pending.remove(key);

    if (type == 1) {
      // 收到画面即视为已连通（应答可能丢包）
      if (_discovering && _lastSentTarget != null) {
        _boardIp = _lastSentTarget;
        _discovering = false;
      }
      _everGotFrame = true;
      _lastFrameAt = DateTime.now();
      frameNotifier.value = jpeg;
      _fpsCount++;
      final now = DateTime.now();
      if (now.difference(_fpsT0).inMilliseconds >= 1000) {
        final ms = now.difference(_fpsT0).inMilliseconds;
        fpsNotifier.value = (_fpsCount * 1000 / ms).round();
        kbpsNotifier.value = (_byteCount * 1000 / ms / 1024).round();
        _fpsCount = 0;
        _byteCount = 0;
        _fpsT0 = now;
      }
      statusNotifier.value = '图传中';
    } else if (type == 2) {
      photoNotifier.value = jpeg;
      statusNotifier.value = '照片已接收';
    }
  }
}

class _PendingFrame {
  final int segCnt;
  final DateTime createdAt;
  final Map<int, Uint8List> segments = {};

  _PendingFrame(this.segCnt, this.createdAt);
}
