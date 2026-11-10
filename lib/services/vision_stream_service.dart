import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// 视觉板UDP图传客户端
///
/// 协议对应 esp32_vision/main/vision_udp.h：
/// 命令（文本）：VSTART/VSTOP/VSNAP/VINFO/VSET/VFLIP/VMIR → 192.168.4.2:8889
/// 帧数据（二进制，22字节头）：
///   [0-1]='H''V' [2]=type(1流/2照片) [3]=flags
///   [4-7]=photo_id [8-11]=frame_seq [12-13]=seg_idx [14-15]=seg_cnt
///   [16-19]=total_len [20-21]=seg_len [22+]=payload
/// UDP分段按 frame_seq 重组，收齐 seg_cnt 段拼出完整JPEG。
class VisionStreamService {
  VisionStreamService({this.visionIp = '192.168.4.2', this.visionPort = 8889});

  final String visionIp;
  final int visionPort;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _keepAlive;

  // 分帧重组缓冲：key = frame_seq
  final Map<int, _PendingFrame> _pending = {};

  final ValueNotifier<String> statusNotifier = ValueNotifier('未启动');
  final ValueNotifier<int> fpsNotifier = ValueNotifier(0);
  final ValueNotifier<Uint8List?> frameNotifier = ValueNotifier(null);
  final ValueNotifier<Uint8List?> photoNotifier = ValueNotifier(null);
  final ValueNotifier<bool> streamingNotifier = ValueNotifier(false);

  int _fpsCount = 0;
  DateTime _fpsT0 = DateTime.now();

  bool get streaming => streamingNotifier.value;

  /// 初始化socket并开始图传
  Future<void> start() async {
    _socket?.close();
    _sub?.cancel();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _sub = _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket!.receive();
        if (dg != null) _onData(dg);
      }
    });
    sendCommand('VSTART');
    streamingNotifier.value = true;
    statusNotifier.value = '指令已发送，等待画面...';
    _keepAlive?.cancel();
    // 周期重发VSTART：既是保活，也刷新板子"最近命令来源"地址
    _keepAlive = Timer.periodic(const Duration(seconds: 3), (_) {
      if (streamingNotifier.value) sendCommand('VSTART');
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

  /// 发送任意文本命令
  void sendCommand(String cmd) {
    final sock = _socket;
    if (sock == null) {
      statusNotifier.value = '未初始化';
      return;
    }
    final dg = sock.send(cmd.codeUnits, InternetAddress(visionIp), visionPort);
    if (dg == null) {
      statusNotifier.value = '发送失败：请确认已连接 HuHuaShiZhe-Drone 热点';
    }
  }

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
    frameNotifier.dispose();
    photoNotifier.dispose();
    streamingNotifier.dispose();
  }

  // ==================== 数据解析 ====================

  void _onData(Datagram dg) {
    final data = dg.data;
    if (data.length < 22) return;
    if (data[0] != 0x48 || data[1] != 0x56) return; // 'HV'

    final bd = ByteData.sublistView(data);
    final type = data[2];
    // final flags = data[3];
    // final photoId = bd.getUint32(4, Endian.little);
    final frameSeq = bd.getUint32(8, Endian.little);
    final segIdx = bd.getUint16(12, Endian.little);
    final segCnt = bd.getUint16(14, Endian.little);
    // final totalLen = bd.getUint32(16, Endian.little);
    final segLen = bd.getUint16(20, Endian.little);
    if (segCnt == 0 || segCnt > 64) return;
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
      frameNotifier.value = jpeg;
      _fpsCount++;
      final now = DateTime.now();
      if (now.difference(_fpsT0).inMilliseconds >= 1000) {
        fpsNotifier.value = (_fpsCount * 1000 / now.difference(_fpsT0).inMilliseconds).round();
        _fpsCount = 0;
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
