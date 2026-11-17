/// 登录用户信息（前后端共享，SYS_USER 表的业务视图）。
///
/// 字段分两组：协议字段由后端 `/api/auth/login`、`/api/auth/me` 下发；
/// 工作区字段（医院/院区/科室/角色名称）按登录时所选「角色-科室」授权
/// 组合由后端关联下发（见 AuthService.withRoleContext），未设置的字段
/// 为 null，界面按需隐藏。
final class LoginUser {
  /// 构造函数
  const LoginUser({
    required this.id,
    required this.userCode,
    required this.userName,
    required this.roleId,
    this.roleName,
    this.userType,
    this.permissionLevel,
    this.phone,
    this.idCardNo,
    this.hisUserCode,
    this.mchisUserCode,
    this.certId,
    this.signatureImage,
    this.avatarImage,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.hospId,
    this.hospName,
  });

  /// 从 JSON 对象创建 LoginUser 实例（后端响应的 user 字段）
  factory LoginUser.fromJson(Map<String, dynamic> json) => LoginUser(
    id: json['id'] as String,
    userCode: json['userCode'] as String,
    userName: json['userName'] as String,
    roleId: json['roleId'] as String,
    roleName: json['roleName'] as String?,
    userType: json['userType'] as String?,
    permissionLevel: json['permissionLevel'] as String?,
    phone: json['phone'] as String?,
    idCardNo: json['idCardNo'] as String?,
    hisUserCode: json['hisUserCode'] as String?,
    mchisUserCode: json['mchisUserCode'] as String?,
    certId: json['certId'] as String?,
    signatureImage: json['signatureImage'] as String?,
    avatarImage: json['avatarImage'] as String?,
    deptId: json['deptId'] as String?,
    deptName: json['deptName'] as String?,
    campusId: json['campusId'] as String?,
    campusName: json['campusName'] as String?,
    hospId: json['hospId'] as String?,
    hospName: json['hospName'] as String?,
  );

  /// 用户 ID
  final String id;

  /// 用户名（登录账号）
  final String userCode;

  /// 用户姓名
  final String userName;

  /// 登录角色ID（登录时所选「角色-科室」授权组合中的角色）
  final String roleId;

  /// 登录角色名称（登录时所选授权组合的角色，后端关联下发）
  final String? roleName;

  /// 用户类别（ADMIN/DOCTOR/NURSE/TECHNICIAN）
  final String? userType;

  /// 用户权限级别：
  /// 0-个人级（只能修改和删除本人录入的数据）
  /// 1-机构级（可以修改和删除本机构所有人录入的数据）
  /// 2-跨机构级（可以修改和删除本系统所有人录入的数据）
  final String? permissionLevel;

  /// 用户手机号
  final String? phone;

  /// 用户身份证号
  final String? idCardNo;

  ///HIS系统用户编码
  final String? hisUserCode;

  ///区域妇幼健康信息系统用户编码
  final String? mchisUserCode;

  /// CA证书唯一标识
  final String? certId;

  ///手写签名图片BASE64
  final String? signatureImage;

  ///用户头像图片BASE64
  final String? avatarImage;

  /// 科室 ID（登录时所选授权组合的适用科室）
  final String? deptId;

  /// 科室名称（登录时所选授权组合的适用科室名称）
  final String? deptName;

  /// 院区 ID（上述科室所属院区）
  final String? campusId;

  /// 院区名称（上述科室所属院区名称）
  final String? campusName;

  /// 医院 ID（上述科室所属医院）
  final String? hospId;

  /// 医院名称（上述科室所属医院名称）
  final String? hospName;

  /// 复制并替换指定字段
  LoginUser copyWith({
    String? id,
    String? userCode,
    String? userName,
    String? roleId,
    String? roleName,
    String? userType,
    String? permissionLevel,
    String? phone,
    String? idCardNo,
    String? hisUserCode,
    String? mchisUserCode,
    String? certId,
    String? signatureImage,
    String? avatarImage,
    String? deptId,
    String? deptName,
    String? campusId,
    String? campusName,
    String? hospId,
    String? hospName,
  }) => LoginUser(
    id: id ?? this.id,
    userCode: userCode ?? this.userCode,
    userName: userName ?? this.userName,
    roleId: roleId ?? this.roleId,
    roleName: roleName ?? this.roleName,
    userType: userType ?? this.userType,
    permissionLevel: permissionLevel ?? this.permissionLevel,
    phone: phone ?? this.phone,
    idCardNo: idCardNo ?? this.idCardNo,
    hisUserCode: hisUserCode ?? this.hisUserCode,
    mchisUserCode: mchisUserCode ?? this.mchisUserCode,
    certId: certId ?? this.certId,
    signatureImage: signatureImage ?? this.signatureImage,
    avatarImage: avatarImage ?? this.avatarImage,
    deptId: deptId ?? this.deptId,
    deptName: deptName ?? this.deptName,
    campusId: campusId ?? this.campusId,
    campusName: campusName ?? this.campusName,
    hospId: hospId ?? this.hospId,
    hospName: hospName ?? this.hospName,
  );

  /// 以登录时所选「角色-科室」授权组合替换身份上下文：角色 ID/名称与
  /// 医院/院区/科室字段**整体覆盖**（含置 null——所选科室无院区时须清掉
  /// 之前的值，故不能用 copyWith 的「null 表示保留」语义）。
  LoginUser withRoleContext({
    required String roleId,
    String? roleName,
    String? deptId,
    String? deptName,
    String? campusId,
    String? campusName,
    String? hospId,
    String? hospName,
  }) => LoginUser(
    id: id,
    userCode: userCode,
    userName: userName,
    roleId: roleId,
    roleName: roleName,
    userType: userType,
    permissionLevel: permissionLevel,
    phone: phone,
    idCardNo: idCardNo,
    hisUserCode: hisUserCode,
    mchisUserCode: mchisUserCode,
    certId: certId,
    signatureImage: signatureImage,
    avatarImage: avatarImage,
    deptId: deptId,
    deptName: deptName,
    campusId: campusId,
    campusName: campusName,
    hospId: hospId,
    hospName: hospName,
  );

  /// 将 LoginUser 转换为 JSON 对象（后端 login/me 响应的 user 字段同此结构）
  Map<String, dynamic> toJson() => {
    'id': id,
    'userCode': userCode,
    'userName': userName,
    'roleId': roleId,
    'roleName': roleName,
    'userType': userType,
    'permissionLevel': permissionLevel,
    'phone': phone,
    'idCardNo': idCardNo,
    'hisUserCode': hisUserCode,
    'mchisUserCode': mchisUserCode,
    'certId': certId,
    'signatureImage': signatureImage,
    'avatarImage': avatarImage,
    'deptId': deptId,
    'deptName': deptName,
    'campusId': campusId,
    'campusName': campusName,
    'hospId': hospId,
    'hospName': hospName,
  };
}
