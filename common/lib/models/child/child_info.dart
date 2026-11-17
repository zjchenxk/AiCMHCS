/// 儿童基本信息（对应 CHILD_INFO 表，归属医院经 hospId 关联
/// SYS_HOSPITAL）。
///
/// 各字段均为数据库列的字符串形式（两库网关所有列均以字符串返回）；
/// 敏感字段（ecardId/name/certificateNo/addressDetails/phone）在
/// JSON 协议中为服务端解密后的明文，传输由信封加密保护。
class ChildInfo {
  /// 构造函数：注入儿童基本信息各字段。
  const ChildInfo({
    required this.id,
    required this.checkTime,
    required this.name,
    required this.sex,
    required this.birthDate,
    required this.addressProvince,
    required this.addressCity,
    required this.addressCounty,
    required this.addressDetails,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.visitCardNo,
    this.patientId,
    this.ecardId,
    this.birthTime,
    this.country,
    this.nation,
    this.certificateType,
    this.certificateNo,
    this.healthNo,
    this.mchisHealthNo,
    this.addressTown,
    this.addressVillage,
    this.addressCode,
    this.phone,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7 字符串形式；客户端新建时为空串）。
  final String id;

  /// 建档时间。
  final String checkTime;

  /// 就诊号/就诊卡号（与医院 HIS 系统对接预留）。
  final String? visitCardNo;

  /// 病人ID（由 HIS 系统自动获取，不支持录入和修改）。
  final String? patientId;

  /// 电子健康卡ID（服务端加密存储）。
  final String? ecardId;

  /// 姓名（服务端加密存储）。
  final String name;

  /// 性别（1-男，2-女）。
  final String sex;

  /// 出生日期（yyyy-MM-dd）。
  final String birthDate;

  /// 出生时间（时和分，HH:mm）。
  final String? birthTime;

  /// 国籍（存数据字典项目值）。
  final String? country;

  /// 民族（存数据字典项目值）。
  final String? nation;

  /// 证件类型（存数据字典项目值）。
  final String? certificateType;

  /// 证件号码（服务端加密存储）。
  final String? certificateNo;

  /// 保健号。
  final String? healthNo;

  /// 区域妇幼健康信息系统保健号。
  final String? mchisHealthNo;

  /// 居住地址-省/直辖市/自治区。
  final String addressProvince;

  /// 居住地址-市/自治州/地区。
  final String addressCity;

  /// 居住地址-县/区/旗。
  final String addressCounty;

  /// 居住地址-乡/镇/街道。
  final String? addressTown;

  /// 居住地址-村/居委会。
  final String? addressVillage;

  /// 居住地址-路/门牌号码（服务端加密存储）。
  final String addressDetails;

  /// 居住地址-编码（级联选择的最后一级行政区划代码）。
  final String? addressCode;

  /// 联系电话（服务端加密存储）。
  final String? phone;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 归属科室 ID（建档人所属科室，建档时随会话写入、不可修改）。
  final String? deptId;

  /// 归属科室名称。
  final String? deptName;

  /// 归属院区 ID（建档人所属院区，建档时随会话写入、不可修改）。
  final String? campusId;

  /// 归属院区名称。
  final String? campusName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory ChildInfo.fromJson(Map<String, dynamic> json) {
    return ChildInfo(
      id: json['id'] as String? ?? '',
      checkTime: json['checkTime'] as String? ?? '',
      visitCardNo: json['visitCardNo'] as String?,
      patientId: json['patientId'] as String?,
      ecardId: json['ecardId'] as String?,
      name: json['name'] as String? ?? '',
      sex: json['sex'] as String? ?? '',
      birthDate: json['birthDate'] as String? ?? '',
      birthTime: json['birthTime'] as String?,
      country: json['country'] as String?,
      nation: json['nation'] as String?,
      certificateType: json['certificateType'] as String?,
      certificateNo: json['certificateNo'] as String?,
      healthNo: json['healthNo'] as String?,
      mchisHealthNo: json['mchisHealthNo'] as String?,
      addressProvince: json['addressProvince'] as String? ?? '',
      addressCity: json['addressCity'] as String? ?? '',
      addressCounty: json['addressCounty'] as String? ?? '',
      addressTown: json['addressTown'] as String?,
      addressVillage: json['addressVillage'] as String?,
      addressDetails: json['addressDetails'] as String? ?? '',
      addressCode: json['addressCode'] as String?,
      phone: json['phone'] as String?,
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      hospId: json['hospId'] as String? ?? '',
      hospName: json['hospName'] as String? ?? '',
      deptId: json['deptId'] as String?,
      deptName: json['deptName'] as String?,
      campusId: json['campusId'] as String?,
      campusName: json['campusName'] as String?,
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'checkTime': checkTime,
      'visitCardNo': visitCardNo,
      'patientId': patientId,
      'ecardId': ecardId,
      'name': name,
      'sex': sex,
      'birthDate': birthDate,
      'birthTime': birthTime,
      'country': country,
      'nation': nation,
      'certificateType': certificateType,
      'certificateNo': certificateNo,
      'healthNo': healthNo,
      'mchisHealthNo': mchisHealthNo,
      'addressProvince': addressProvince,
      'addressCity': addressCity,
      'addressCounty': addressCounty,
      'addressTown': addressTown,
      'addressVillage': addressVillage,
      'addressDetails': addressDetails,
      'addressCode': addressCode,
      'phone': phone,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'deptId': deptId,
      'deptName': deptName,
      'campusId': campusId,
      'campusName': campusName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
