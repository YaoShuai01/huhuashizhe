import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BtConnectionState { disconnected, scanning, connecting, connected }

/// 发现的蓝牙设备
class DiscoveredDevice {
  final String name;
  final String address;
  final int rssi;
  final String type; // "BLE" or "CLASSIC"
  final bool isBonded;

  const DiscoveredDevice({
    required this.name,
    required this.address,
    required this.rssi,
    this.type = 'CLASSIC',
    this.isBonded = false,
  });

  factory DiscoveredDevice.fromMap(Map<String, dynamic> map) {
    return DiscoveredDevice(
      name: map['name'] as String? ?? '未知设备',
      address: map['address'] as String? ?? '',
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
      type: map['type'] as String? ?? 'CLASSIC',
      isBonded: map['isBonded'] as bool? ?? false,
    );
  }

  String get signalStrengthDisplay => '$rssi dBm';

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'rssi': rssi,
        'type': type,
        'isBonded': isBonded,
      };
}

class DeviceStatus {
  final String? deviceName;
  final BtConnectionState connectionState;
  final int batteryLevel;
  final int signalStrength;
  final DateTime? connectedAt;

  const DeviceStatus({
    this.deviceName,
    this.connectionState = BtConnectionState.disconnected,
    this.batteryLevel = 0,
    this.signalStrength = 0,
    this.connectedAt,
  });

  bool get isConnected => connectionState == BtConnectionState.connected;
}

class CommandFrame {
  static const frameHeader = 0xAA55;
  static const frameFooter = 0x55AA;
  static const protocolVersion = 0x01;

  final int command;
  final List<int> data;

  CommandFrame({required this.command, required this.data});

  List<int> toBytes() {
    final len = data.length;
    final buffer = List<int>.filled(8 + len, 0);
    buffer[0] = frameHeader & 0xFF;
    buffer[1] = (frameHeader >> 8) & 0xFF;
    buffer[2] = protocolVersion;
    buffer[3] = command;
    buffer[4] = len & 0xFF;
    buffer[5] = (len >> 8) & 0xFF;
    buffer.setRange(6, 6 + len, data);
    final crc = _crc16(data);
    buffer[6 + len] = crc & 0xFF;
    buffer[7 + len] = (crc >> 8) & 0xFF;
    buffer[8 + len] = frameFooter & 0xFF;
    buffer[9 + len] = (frameFooter >> 8) & 0xFF;
    return buffer;
  }

  static int _crc16(List<int> data) {
    int crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte << 8;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}

class BluetoothService {
  static const _channel = MethodChannel('com.huhuashizhe/bluetooth');
  static const _eventChannel = EventChannel('com.huhuashizhe/bluetooth_events');

  BtConnectionState _state = BtConnectionState.disconnected;
  DeviceStatus _deviceStatus = const DeviceStatus();
  final _stateController = StreamController<DeviceStatus>.broadcast();
  final _deviceStreamController = StreamController<DiscoveredDevice>.broadcast();
  final _scanCompleteController = StreamController<void>.broadcast();

  StreamSubscription? _eventSubscription;
  bool _isScanning = false;

  BtConnectionState get state => _state;
  DeviceStatus get deviceStatus => _deviceStatus;
  bool get isScanning => _isScanning;
  Stream<DeviceStatus> get statusStream => _stateController.stream;
  Stream<DiscoveredDevice> get deviceStream => _deviceStreamController.stream;
  Stream<void> get scanCompleteStream => _scanCompleteController.stream;

  void init() {
    debugPrint('BluetoothService initialized');
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (error) => debugPrint('Bluetooth event error: $error'),
    );
  }

  void _onNativeEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      if (type == 'scanComplete') {
        _isScanning = false;
        _scanCompleteController.add(null);
        return;
      }
      if (type == 'scanError') {
        debugPrint('Bluetooth scan error: ${event['error']}');
        return;
      }
      // 设备发现事件
      try {
        final device = DiscoveredDevice.fromMap(Map<String, dynamic>.from(event));
        _deviceStreamController.add(device);
      } catch (e) {
        debugPrint('Failed to parse device: $e');
      }
    }
  }

  /// 检查蓝牙是否开启
  Future<bool> isBluetoothEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBluetoothEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('isBluetoothEnabled error: $e');
      return false;
    }
  }

  /// 获取已配对设备列表
  Future<List<DiscoveredDevice>> getBondedDevices() async {
    try {
      final result = await _channel.invokeMethod('getBondedDevices');
      if (result is List) {
        return result
            .map((e) => DiscoveredDevice.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('getBondedDevices error: $e');
      return [];
    }
  }

  /// 开始扫描蓝牙设备
  Future<bool> startScan() async {
    if (_isScanning) return true;
    try {
      final result = await _channel.invokeMethod<bool>('startScan');
      if (result == true) {
        _isScanning = true;
        updateConnectionState(BtConnectionState.scanning);
      }
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('startScan error: ${e.code} - ${e.message}');
      if (e.code == 'BT_DISABLED') {
        rethrow;
      }
      return false;
    } catch (e) {
      debugPrint('startScan error: $e');
      return false;
    }
  }

  /// 停止扫描
  Future<void> stopScan() async {
    if (!_isScanning) return;
    try {
      await _channel.invokeMethod('stopScan');
      _isScanning = false;
      updateConnectionState(BtConnectionState.disconnected);
    } catch (e) {
      debugPrint('stopScan error: $e');
    }
  }

  void updateConnectionState(BtConnectionState newState) {
    _state = newState;
    _deviceStatus = DeviceStatus(
      deviceName: _deviceStatus.deviceName,
      connectionState: newState,
      batteryLevel: _deviceStatus.batteryLevel,
      signalStrength: _deviceStatus.signalStrength,
      connectedAt:
          newState == BtConnectionState.connected ? DateTime.now() : null,
    );
    _stateController.add(_deviceStatus);
  }

  void dispose() {
    _eventSubscription?.cancel();
    _stateController.close();
    _deviceStreamController.close();
    _scanCompleteController.close();
  }
}