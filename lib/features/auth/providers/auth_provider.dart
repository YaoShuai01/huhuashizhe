import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

/// 当前登录用户状态（null = 未登录）
final authProvider = StateNotifierProvider<AuthNotifier, UserModel?>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<UserModel?> {
  AuthNotifier() : super(AuthService.instance.currentUser);

  void refresh() {
    state = AuthService.instance.currentUser;
  }

  void logout() {
    AuthService.instance.logout();
    state = null;
  }
}
