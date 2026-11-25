import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 飞控 UDP 图传 → 本机 HTTP 中转。
///
/// 飞控把 H.264 按 1400 字节分段单播到手机 8889，分片头 18 字节：
/// 'H''V' 0x03 | seq(4) | idx(2) | cnt(2) | nal_len(4) | seg_len(2) | 0
///
/// 本类重组出完整 NAL，再通过 127.0.0.1 的 HTTP 流交给 FVP 解码。
/// 走 UDP 而不是直连飞控 HTTP：ESP32 的 TCP 发送窗口只有 5744 字节，
/// 手机省电模式下 RTT 约 50ms，TCP 吞吐只有约 1Mbps，扛不住 3Mbps 视频。
class H264UdpRelay {
  static const int udpPort = 8889;
  static const String _droneHost = '192.168.4.1';
  static const int _hdrLen = 18;
  static const int _segMax = 1400;
  static const int _maxQueue = 40; // 约 1.5 秒缓冲，超出丢最旧的整帧

  RawDatagramSocket? _udp;
  HttpServer? _http;
  Timer? _hello;
  HttpResponse? _client;

  final List<Uint8List> _queue = [];

  // 分片重组状态
  int _seq = -1;
  int _nalLen = 0;
  int _segCnt = 0;
  int _nextSeg = 0;
  int _got = 0;
  Uint8List? _buf;
  bool _drop = false;

  int droppedNals = 0;
  int receivedBytes = 0;

  String get localUrl => 'http://127.0.0.1:${_http!.port}/live.h264';

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http!.listen(_handle, onError: (Object _) {});
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
    _udp!.listen(_onSocket);
    _hello = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => _sendHello(),
    );
    _sendHello();
  }

  Future<void> dispose() async {
    _hello?.cancel();
    _hello = null;
    _client = null;
    _udp?.close();
    _udp = null;
    try {
      await _http?.close(force: true);
    } catch (_) {}
    _http = null;
    _queue.clear();
  }

  /// 订阅包：飞控收到后才知道要发给谁（单播，不用广播占空口）
  void _sendHello() {
    final s = _udp;
    if (s == null) return;
    try {
      s.send(
        Uint8List.fromList('HVS1'.codeUnits),
        InternetAddress(_droneHost),
        udpPort,
      );
    } catch (_) {
      // 还没连上飞控 AP，下一轮重试
    }
  }

  void _onSocket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final s = _udp;
    if (s == null) return;
    Datagram? dg;
    while ((dg = s.receive()) != null) {
      _onPacket(dg!.data);
    }
  }

  void _onPacket(Uint8List d) {
    if (d.length < _hdrLen + 1) return;
    if (d[0] != 0x48 || d[1] != 0x56 || d[2] != 0x03) return;

    final bd = ByteData.sublistView(d);
    final seq = bd.getUint32(3, Endian.little);
    final idx = bd.getUint16(7, Endian.little);
    final cnt = bd.getUint16(9, Endian.little);
    final nalLen = bd.getUint32(11, Endian.little);
    final segLen = bd.getUint16(15, Endian.little);
    if (nalLen == 0 || nalLen > 400000 || cnt == 0 || segLen == 0) return;
    if (d.length < _hdrLen + segLen) return;

    if (seq != _seq) {
      _seq = seq;
      _nalLen = nalLen;
      _segCnt = cnt;
      _nextSeg = 0;
      _got = 0;
      _drop = false;
      _buf = Uint8List(nalLen);
    }
    if (_drop) return;

    if (idx != _nextSeg) {
      // 中间丢片：整帧丢弃。半帧数据交给解码器会画出彩色竖线
      _drop = true;
      droppedNals++;
      return;
    }
    final off = idx * _segMax;
    if (off + segLen > _nalLen) {
      _drop = true;
      droppedNals++;
      return;
    }
    _buf!.setRange(off, off + segLen, d, _hdrLen);
    _got += segLen;
    _nextSeg++;

    if (idx == _segCnt - 1 || _got >= _nalLen) {
      if (!_drop && _got == _nalLen) {
        _push(_buf!);
      } else {
        droppedNals++;
      }
      _seq = -1;
    }
  }

  void _push(Uint8List nal) {
    receivedBytes += nal.length;
    _queue.add(nal);
    while (_queue.length > _maxQueue) {
      _queue.removeAt(0);
      droppedNals++;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    if (req.uri.path != '/live.h264') {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    // 播放器重连时新连接顶掉旧连接
    final old = _client;
    _client = res;
    if (old != null) {
      try {
        await old.close();
      } catch (_) {}
    }

    res.statusCode = 200;
    res.headers.contentType = ContentType('video', 'h264');
    res.headers.set('Cache-Control', 'no-cache');
    res.bufferOutput = false;
    try {
      while (identical(_client, res)) {
        if (_queue.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        res.add(_queue.removeAt(0));
        await res.flush();
      }
    } catch (_) {
      // 播放器断开
    } finally {
      if (identical(_client, res)) _client = null;
      try {
        await res.close();
      } catch (_) {}
    }
  }
}
