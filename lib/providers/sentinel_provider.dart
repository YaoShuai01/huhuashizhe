import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/sentinel/services/sentinel_service.dart';

/// 田哨服务全局实例（云端田哨 · 哨兵值守）
final sentinelServiceProvider =
    ChangeNotifierProvider<SentinelService>((ref) => SentinelService());
