import 'dart:async';
import 'package:flutter/foundation.dart';

enum BtConnectionState { disconnected, scanning, connecting, connected }

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
  BtConnectionState _state = BtConnectionState.disconnected;
  DeviceStatus _deviceStatus = const DeviceStatus();
  final _stateController = StreamController<DeviceStatus>.broadcast();

  BtConnectionState get state => _state;
  DeviceStatus get deviceStatus => _deviceStatus;
  Stream<DeviceStatus> get statusStream => _stateController.stream;

  void init() => debugPrint('BluetoothService initialized');

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

  void dispose() => _stateController.close();
}