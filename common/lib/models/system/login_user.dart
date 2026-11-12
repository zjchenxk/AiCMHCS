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
    required this.roleId,
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

  /// 登录角色ID
  final String roleId;

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

  /// 科室 ID
  final String? deptId;

  /// 科室名称
  final String? deptName;

  /// 院区 ID
  final String? campusId;

  /// 院区名称
  final String? campusName;

  /// 医院 ID
  final String? hospId;

  /// 医院名称
  final String? hospName;

  /// 复制并替换指定字段
  LoginUser copyWith({
    String? id,
    String? userCode,
    String? userName,
    String? roleId,
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

  /// 将 LoginUser 转换为 JSON 对象（后端 login/me 响应的 user 字段同此结构）
  Map<String, dynamic> toJson() => {
    'id': id,
    'userCode': userCode,
    'userName': userName,
    'roleId': roleId,
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
