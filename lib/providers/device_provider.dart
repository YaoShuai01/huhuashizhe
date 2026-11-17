import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/wifi_service.dart';

final wifiServiceProvider = Provider<WifiService>((ref) {
  final service = WifiService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 设备连接状态：以无人机 WiFi 热点是否已连接为准
final deviceStatusProvider = StreamProvider<WifiStatus>((ref) {
  final service = ref.watch(wifiServiceProvider);
  return service.statusStream;
});
