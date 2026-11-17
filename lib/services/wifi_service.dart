import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 扫描到的 WiFi 网络
class WifiNetwork {
  final String ssid;
  final String bssid;
  final int rssi;
  final bool secured;
  final bool isCurrent;

  const WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    this.secured = false,
    this.isCurrent = false,
  });

  /// 是否为无人机热点（ESP32 AP 固定 SSID）
  bool get isDrone => ssid == WifiService.droneSsid;

  String get signalDisplay => '$rssi dBm';

  String get securityDisplay => secured ? '加密' : '开放';

  factory WifiNetwork.fromMap(Map<dynamic, dynamic> map) {
    return WifiNetwork(
      ssid: map['ssid'] as String? ?? '',
      bssid: map['bssid'] as String? ?? '',
      rssi: (map['rssi'] as num?)?.toInt() ?? -100,
      secured: map['secured'] as bool? ?? false,
      isCurrent: map['isCurrent'] as bool? ?? false,
    );
  }
}

/// 当前 WiFi 连接状态
class WifiStatus {
  final String? ssid;
  final bool connectedToDrone;
  final int rssi;

  const WifiStatus({this.ssid, this.connectedToDrone = false, this.rssi = 0});

  bool get isConnected => connectedToDrone;

  String get displayName => ssid ?? '未连接';

  String get signalDisplay => rssi == 0 ? '-- dBm' : '$rssi dBm';
}

/// WiFi 扫描与连接状态服务
///
/// Android 10+ 不允许应用直接连接指定 WiFi，因此这里只负责扫描、
/// 跳转系统 WiFi 面板，并检测是否已连上无人机热点。
class WifiService {
  /// ESP32 飞控 AP 的固定 SSID（见 esp32_drone/main/main.c）
  static const String droneSsid = 'HuHuaShiZhe-Drone';

  static const _channel = MethodChannel('com.huhuashizhe/wifi');
  static const _eventChannel = EventChannel('com.huhuashizhe/wifi_events');

  final _networkController = StreamController<WifiNetwork>.broadcast();
  final _scanCompleteController = StreamController<void>.broadcast();
  final _statusController = StreamController<WifiStatus>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  WifiStatus _status = const WifiStatus();
  bool _isScanning = false;

  WifiStatus get status => _status;
  bool get isScanning => _isScanning;

  Stream<WifiStatus> get statusStream => _statusController.stream;
  Stream<WifiNetwork> get networkStream => _networkController.stream;
  Stream<void> get scanCompleteStream => _scanCompleteController.stream;

  void init() {
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error) => debugPrint('WiFi event error: $error'),
    );
    // 首页/监控页依赖状态流，初始化时先同步一次当前连接
    refreshStatus();
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<dynamic, dynamic>.from(event);
    final type = map['type'] as String?;

    if (type == 'scanComplete') {
      _isScanning = false;
      _scanCompleteController.add(null);
      return;
    }
    if (type == 'scanError') {
      debugPrint('WiFi 扫描错误: ${map['error']}');
      return;
    }
    if (type == 'network') {
      final network = WifiNetwork.fromMap(map);
      if (network.ssid.isEmpty) return;
      _networkController.add(network);
      if (network.isCurrent) {
        _emitStatus(WifiStatus(
          ssid: network.ssid,
          connectedToDrone: network.isDrone,
          rssi: network.rssi,
        ));
      }
    }
  }

  void _emitStatus(WifiStatus next) {
    final unchanged = _status.ssid == next.ssid &&
        _status.connectedToDrone == next.connectedToDrone &&
        _status.rssi == next.rssi;
    if (unchanged) return;
    _status = next;
    _statusController.add(next);
  }

  /// 读取当前连接的 WiFi SSID（未连接返回 null）
  Future<void> refreshStatus() async {
    try {
      final ssid = await _channel.invokeMethod<String>('getCurrentSsid');
      final name = (ssid == null || ssid.isEmpty) ? null : ssid;
      final connected = name == droneSsid;
      _emitStatus(WifiStatus(
        ssid: name,
        connectedToDrone: connected,
        rssi: connected ? _status.rssi : 0,
      ));
    } catch (e) {
      debugPrint('获取当前 WiFi 失败: $e');
      _emitStatus(const WifiStatus());
    }
  }

  Future<bool> isWifiEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isWifiEnabled') ?? false;
    } catch (e) {
      debugPrint('isWifiEnabled error: $e');
      return false;
    }
  }

  /// 开始扫描周边 WiFi，结果通过 networkStream 推送
  Future<bool> startScan() async {
    try {
      final success = await _channel.invokeMethod<bool>('startScan') ?? false;
      if (success) _isScanning = true;
      return success;
    } on PlatformException catch (e) {
      debugPrint('WiFi 扫描启动失败: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<void> stopScan() async {
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      debugPrint('stopScan error: $e');
    }
    _isScanning = false;
  }

  /// 打开系统 WiFi 设置面板（Android 10+ 只能由用户确认连接）
  Future<void> openWifiSettings() async {
    try {
      await _channel.invokeMethod('openWifiSettings');
    } catch (e) {
      debugPrint('openWifiSettings error: $e');
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _networkController.close();
    _scanCompleteController.close();
    _statusController.close();
  }
}
