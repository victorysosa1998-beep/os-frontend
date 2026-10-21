import 'package:flutter/material.dart';

/// Colour of the verified tick for regular verified members.
const Color kVerifiedBlue = Color(0xFF1DA1F2);

/// Colour of the tick for OS administrators (distinct from members).
const Color kAdminGold = Color(0xFFF5B400);

bool _truthy(dynamic v) =>
    v == true || v == 1 || '$v'.toLowerCase() == 'true' || '$v' == '1';

/// True for administrator accounts. Accepts the common ways a backend flags
/// an admin so one missing field cannot demote an admin to "regular user".
bool isAdminUser(Map? u) {
  if (u == null) return false;
  if (_truthy(u['is_admin']) || _truthy(u['is_superuser'])) return true;
  final role = '${u['role'] ?? u['user_type'] ?? ''}'.toLowerCase().trim();
  return role == 'admin' || role == 'administrator' || role == 'superadmin';
}

/// Admins always count as verified; members need verification_status == verified.
bool isVerifiedUser(Map? u) =>
    u != null && (isAdminUser(u) || u['verification_status'] == 'verified');

Color badgeColorFor(Map? u) => isAdminUser(u) ? kAdminGold : kVerifiedBlue;

/// Text for the "Account status" line.
String accountStatusLabel(Map? u) {
  if (isAdminUser(u)) return 'OS Admin';
  if (isVerifiedUser(u)) return 'Verified OS member';
  final s = '${u?['verification_status'] ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? 'Unverified' : s[0].toUpperCase() + s.substring(1);
}

/// Verified tick: blue for verified members, gold for admins, nothing otherwise.
class UserBadge extends StatelessWidget {
  final Map? user;
  final double size;
  const UserBadge({super.key, required this.user, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (!isVerifiedUser(user)) return const SizedBox.shrink();
    return Tooltip(
      message: isAdminUser(user) ? 'OS Admin' : 'Verified',
      child: Icon(Icons.verified, size: size, color: badgeColorFor(user)),
    );
  }
}