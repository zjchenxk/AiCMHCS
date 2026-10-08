class LoginUser {
  final String userId; // 用户ID
  final String userCode; // 用户名
  final String userName; // 姓名
  final String password; // 密码
  final String organId; // 医院ID
  final String organName; // 医院名称
  final String? branchId; // 分院ID
  final String? branchName; // 分院名称
  final String deptId; // 科室ID
  final String deptName; // 科室名称

  const LoginUser({
    required this.userId,
    required this.userCode,
    required this.userName,
    required this.password,
    required this.organId,
    required this.organName,
    required this.branchId,
    required this.branchName,
    required this.deptId,
    required this.deptName,
  });

  LoginUser copyWith({String? deptId, String? deptName}) => LoginUser(
    userId: userId,
    userCode: userCode,
    userName: userName,
    password: password,
    organId: organId,
    organName: organName,
    branchId: branchId,
    branchName: branchName,
    deptId: deptId ?? this.deptId,
    deptName: deptName ?? this.deptName,
  );
}
