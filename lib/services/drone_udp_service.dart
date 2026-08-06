import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 无人机UDP通信服务
/// 通过WiFi连接ESP32-S3，使用UDP协议发送遥控指令
/// 协议格式: KEY:VALUE;KEY:VALUE;...\n
class DroneUdpService {
  static const String _droneIp = '192.168.4.1'; // ESP32 AP默认IP
  static const int _dronePort = 8888;
  static const int _sendIntervalMs = 20; // 50Hz发送频率
  static const int _keepAliveMs = 200; // 无变化时200ms发送一次保活

  RawDatagramSocket? _socket;
  Timer? _sendTimer;
  int _lastSendTime = 0;

  // 当前控制值
  int _throttle = 0; // -100 ~ 100
  int _roll = 0;     // -100 ~ 100
  int _pitch = 0;    // -100 ~ 100
  int _yaw = 0;      // -100 ~ 100
  bool _spray = false;
  bool _armed = false;

  bool _dirty = false; // 是否有未发送的变更

  // 状态回调
  final ValueNotifier<DroneStatus> statusNotifier = ValueNotifier(DroneStatus.disconnected);
  final ValueNotifier<String> debugNotifier = ValueNotifier('未连接');

  // 获取当前控制值（用于UI显示）
  int get throttle => _throttle;
  int get roll => _roll;
  int get pitch => _pitch;
  int get yaw => _yaw;
  bool get spray => _spray;
  bool get armed => _armed;

  /// 初始化UDP socket
  Future<void> init() async {
    try {
      _socket?.close();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      debugNotifier.value = 'UDP已就绪，目标: $_droneIp:$_dronePort';
      statusNotifier.value = DroneStatus.ready;
    } catch (e) {
      debugNotifier.value = 'UDP初始化失败: $e';
      statusNotifier.value = DroneStatus.error;
      rethrow;
    }
  }

  /// 启动定时发送
  void startSending() {
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(const Duration(milliseconds: _sendIntervalMs), (_) {
      _sendLoop();
    });
    statusNotifier.value = DroneStatus.connected;
    debugNotifier.value = '已连接，发送中...';
  }

  /// 停止发送
  void stopSending() {
    _sendTimer?.cancel();
    _sendTimer = null;
    statusNotifier.value = DroneStatus.ready;
    debugNotifier.value = '已停止发送';
  }

  /// 发送循环：50Hz高频发送，无变化时降频保活
  void _sendLoop() {
    if (_socket == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastSendTime;

    if (_dirty || elapsed >= _keepAliveMs) {
      _sendCommand();
      _lastSendTime = now;
      _dirty = false;
    }
  }

  /// 构建并发送UDP指令
  void _sendCommand() {
    if (_socket == null) return;

    final cmd = 'ARM:${_armed ? 1 : 0};'
        'THR:$_throttle;'
        'ROL:$_roll;'
        'PIT:$_pitch;'
        'YAW:$_yaw;'
        'SPR:${_spray ? 1 : 0}\n';

    final data = utf8.encode(cmd);
    try {
      _socket!.send(data, InternetAddress(_droneIp), _dronePort);
    } catch (e) {
      debugNotifier.value = '发送失败: $e';
    }
  }

  /// 设置摇杆值（-100~100）
  void setThrottle(int value) {
    _throttle = value.clamp(-100, 100);
    _dirty = true;
  }

  void setRoll(int value) {
    _roll = value.clamp(-100, 100);
    _dirty = true;
  }

  void setPitch(int value) {
    _pitch = value.clamp(-100, 100);
    _dirty = true;
  }

  void setYaw(int value) {
    _yaw = value.clamp(-100, 100);
    _dirty = true;
  }

  /// 设置喷洒
  void setSpray(bool value) {
    _spray = value;
    _dirty = true;
  }

  void toggleSpray() {
    _spray = !_spray;
    _dirty = true;
  }

  /// 解锁/上锁
  void setArmed(bool value) {
    _armed = value;
    _dirty = true;
    if (!_armed) {
      // 上锁时重置所有值
      _throttle = 0;
      _roll = 0;
      _pitch = 0;
      _yaw = 0;
      _spray = false;
    }
  }

  void toggleArmed() {
    setArmed(!_armed);
  }

  /// 释放资源
  void dispose() {
    _sendTimer?.cancel();
    _socket?.close();
    _socket = null;
    statusNotifier.dispose();
    debugNotifier.dispose();
  }
}

enum DroneStatus {
  disconnected,
  ready,
  connected,
  error,
}