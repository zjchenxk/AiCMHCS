/// 登录用户信息（前后端共享，SYS_USER 表的业务视图）。
///
/// 字段分两组：协议字段由后端 `/api/auth/login`、`/api/auth/me` 下发；
/// 工作区字段（医院/院区/科室）后端暂不下发，由客户端登录后自行补充。
final class LoginUser {
  /// 构造函数
  const LoginUser({
    required this.id,
    required this.userCode,
    required this.userName,
    required this.roleCode,
    this.phone,
    this.lastLoginAt,
    this.organId,
    this.organName,
    this.branchId,
    this.branchName,
    this.deptId,
    this.deptName,
  });

  /// 从 JSON 对象创建 LoginUser 实例（后端响应的 user 字段）
  factory LoginUser.fromJson(Map<String, dynamic> json) => LoginUser(
    id: json['id'] as int,
    userCode: json['userCode'] as String,
    userName: json['userName'] as String,
    roleCode: json['roleCode'] as String,
    phone: json['phone'] as String?,
    lastLoginAt: json['lastLoginAt'] as String?,
    organId: json['organId'] as String?,
    organName: json['organName'] as String?,
    branchId: json['branchId'] as String?,
    branchName: json['branchName'] as String?,
    deptId: json['deptId'] as String?,
    deptName: json['deptName'] as String?,
  );

  /// 用户 ID
  final int id;

  /// 用户名（登录账号）
  final String userCode;

  /// 用户姓名
  final String userName;

  /// 用户角色代码
  final String roleCode;

  /// 用户手机号（协议字段）
  final String? phone;

  /// 最后登录时间（协议字段）
  final String? lastLoginAt;

  /// 医院 ID（工作区字段，后端暂不下发）
  final String? organId;

  /// 医院名称（工作区字段，后端暂不下发）
  final String? organName;

  /// 分院 ID（工作区字段，后端暂不下发）
  final String? branchId;

  /// 分院名称（工作区字段，后端暂不下发）
  final String? branchName;

  /// 科室 ID（工作区字段，后端暂不下发）
  final String? deptId;

  /// 科室名称（工作区字段，后端暂不下发）
  final String? deptName;

  static const _roleNames = {
    'ADMIN': '系统管理员',
    'DOCTOR': '儿童心理医生',
    'TEACHER': '教师',
    'PARENT': '家长',
  };

  /// 用户角色名称
  String get roleName => _roleNames[roleCode] ?? roleCode;

  /// 复制并替换指定字段（参数传 null 表示保留原值）
  LoginUser copyWith({
    int? id,
    String? userCode,
    String? userName,
    String? roleCode,
    String? phone,
    String? lastLoginAt,
    String? organId,
    String? organName,
    String? branchId,
    String? branchName,
    String? deptId,
    String? deptName,
  }) => LoginUser(
    id: id ?? this.id,
    userCode: userCode ?? this.userCode,
    userName: userName ?? this.userName,
    roleCode: roleCode ?? this.roleCode,
    phone: phone ?? this.phone,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    organId: organId ?? this.organId,
    organName: organName ?? this.organName,
    branchId: branchId ?? this.branchId,
    branchName: branchName ?? this.branchName,
    deptId: deptId ?? this.deptId,
    deptName: deptName ?? this.deptName,
  );

  /// 将 LoginUser 转换为 JSON 对象（后端 login/me 响应的 user 字段同此结构）
  Map<String, dynamic> toJson() => {
    'id': id,
    'userCode': userCode,
    'userName': userName,
    'roleCode': roleCode,
    'roleName': roleName,
    'phone': phone,
    'lastLoginAt': lastLoginAt,
    'organId': organId,
    'organName': organName,
    'branchId': branchId,
    'branchName': branchName,
    'deptId': deptId,
    'deptName': deptName,
  };
}
