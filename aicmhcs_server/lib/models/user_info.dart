/// 登录用户信息（SYS_USER 表的业务视图）。
final class UserInfo {
  const UserInfo({
    required this.id,
    required this.username,
    required this.realName,
    required this.roleCode,
    this.phone,
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String realName;
  final String roleCode;
  final String? phone;
  final String? lastLoginAt;

  static const _roleNames = {
    'ADMIN': '系统管理员',
    'DOCTOR': '儿童心理医生',
    'TEACHER': '教师',
    'PARENT': '家长',
  };

  String get roleName => _roleNames[roleCode] ?? roleCode;

  factory UserInfo.fromRow(Map<String, String?> row) => UserInfo(
        id: int.parse(row['ID'] ?? '0'),
        username: row['USERNAME'] ?? '',
        realName: row['REAL_NAME'] ?? '',
        roleCode: row['ROLE_CODE'] ?? '',
        phone: row['PHONE'],
        lastLoginAt: row['LAST_LOGIN_AT'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'realName': realName,
        'roleCode': roleCode,
        'roleName': roleName,
        'phone': phone,
        'lastLoginAt': lastLoginAt,
      };
}
