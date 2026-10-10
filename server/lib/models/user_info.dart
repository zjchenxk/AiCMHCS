/// 登录用户信息（SYS_USER 表的业务视图）。
final class UserInfo {
  /// 构造函数
  const UserInfo({
    required this.id,
    required this.userCode,
    required this.userName,
    required this.roleCode,
    this.phone,
    this.lastLoginAt,
  });

  /// 从数据库行创建 UserInfo 实例
  factory UserInfo.fromRow(Map<String, String?> row) => UserInfo(
    id: int.parse(row['ID'] ?? '0'),
    userCode: row['USER_CODE'] ?? '',
    userName: row['USER_NAME'] ?? '',
    roleCode: row['ROLE_CODE'] ?? '',
    phone: row['PHONE'],
    lastLoginAt: row['LAST_LOGIN_AT'],
  );

  /// 用户 ID
  final int id;

  /// 用户名（登录账号）
  final String userCode;

  /// 用户姓名
  final String userName;

  /// 用户角色代码
  final String roleCode;

  /// 用户手机号
  final String? phone;

  /// 最后登录时间
  final String? lastLoginAt;

  static const _roleNames = {
    'ADMIN': '系统管理员',
    'DOCTOR': '儿童心理医生',
    'TEACHER': '教师',
    'PARENT': '家长',
  };

  /// 用户角色名称
  String get roleName => _roleNames[roleCode] ?? roleCode;

  /// 将 UserInfo 转换为 JSON 对象
  Map<String, dynamic> toJson() => {
    'id': id,
    'userCode': userCode,
    'userName': userName,
    'roleCode': roleCode,
    'roleName': roleName,
    'phone': phone,
    'lastLoginAt': lastLoginAt,
  };
}
