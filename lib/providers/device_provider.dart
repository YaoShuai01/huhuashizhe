import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/bluetooth_service.dart';

final bluetoothServiceProvider = Provider<BluetoothService>((ref) {
  final service = BluetoothService();
  ref.onDispose(() => service.dispose());
  return service;
});

final deviceStatusProvider = StreamProvider<DeviceStatus>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  return service.statusStream;
});