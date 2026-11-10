/// 用户（归属医院经 hospId 关联 SYS_HOSPITAL、挂载科室经 deptId 关联
/// SYS_DEPARTMENT，角色经 SYS_USER_ROLE 关联 SYS_ROLE）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）；
/// phone / idCardNo 库中为密文，服务端解密后明文下发（传输由信封保护）；
/// 不含 PASSWORD——口令散列仅在服务端处理，任何接口不下发。
class User {
  /// 构造函数：注入用户各字段。
  const User({
    required this.id,
    required this.userCode,
    required this.userName,
    required this.hospId,
    this.userType,
    this.permissionLevel,
    this.phone,
    this.idCardNo,
    this.hisUserCode,
    this.mchisUserCode,
    this.certId,
    this.signatureImage,
    this.deptId,
    this.status,
    this.roleIds = const [],
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 登录账号（全局唯一）。
  final String userCode;

  /// 姓名。
  final String userName;

  /// 用户类别（ADMIN / DOCTOR / NURSE / TECHNICIAN，存量另有
  /// TEACHER / PARENT 待人工订正）。
  final String? userType;

  /// 权限级别（0-个人级 / 1-机构级 / 2-跨机构级）。
  final String? permissionLevel;

  /// 手机号（明文，库中为 AES-GCM 密文）。
  final String? phone;

  /// 身份证号（明文，库中为 AES-GCM 密文）。
  final String? idCardNo;

  /// HIS 用户代码。
  final String? hisUserCode;

  /// 妇幼保健系统用户代码。
  final String? mchisUserCode;

  /// CA 证书 ID。
  final String? certId;

  /// 手写签名（base64 图片）。
  final String? signatureImage;

  /// 挂载科室 ID。
  final String? deptId;

  /// 所属医院 ID。
  final String hospId;

  /// 状态（1-启用 / 0-停用）。
  final String? status;

  /// 拥有的角色 ID 列表（SYS_USER_ROLE 关联）。
  final List<String> roleIds;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      userCode: json['userCode'] as String,
      userName: json['userName'] as String,
      userType: json['userType'] as String?,
      permissionLevel: json['permissionLevel'] as String?,
      phone: json['phone'] as String?,
      idCardNo: json['idCardNo'] as String?,
      hisUserCode: json['hisUserCode'] as String?,
      mchisUserCode: json['mchisUserCode'] as String?,
      certId: json['certId'] as String?,
      signatureImage: json['signatureImage'] as String?,
      deptId: json['deptId'] as String?,
      hospId: json['hospId'] as String,
      status: json['status'] as String?,
      roleIds: (json['roleIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userCode': userCode,
      'userName': userName,
      'userType': userType,
      'permissionLevel': permissionLevel,
      'phone': phone,
      'idCardNo': idCardNo,
      'hisUserCode': hisUserCode,
      'mchisUserCode': mchisUserCode,
      'certId': certId,
      'signatureImage': signatureImage,
      'deptId': deptId,
      'hospId': hospId,
      'status': status,
      'roleIds': roleIds,
    };
  }
}
