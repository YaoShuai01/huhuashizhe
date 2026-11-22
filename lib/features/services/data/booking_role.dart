import '../../../data/local_database.dart';

/// 预约飞防的身份：农户 / 飞手
const String bookingRoleFarmer = 'farmer';
const String bookingRolePilot = 'pilot';

const String _roleKey = 'booking_role';

/// 读取上次选择的身份，未选择过返回 null
String? savedBookingRole() {
  final value = LocalDatabase().get(_roleKey);
  if (value == bookingRoleFarmer || value == bookingRolePilot) {
    return value;
  }
  return null;
}

void saveBookingRole(String role) {
  LocalDatabase().set(_roleKey, role);
}

/// 身份对应的页面路径
String bookingRolePath(String role) =>
    role == bookingRolePilot ? '/services/booking/pilot' : '/services/booking/farmer';
