/// 儿童监护人信息（对应 CHILD_GUARDIAN_INFO 表，经 childId 逻辑关联
/// 儿童 CHILD_INFO）。
///
/// 各字段均为数据库列的字符串形式（两库网关所有列均以字符串返回）；
/// 敏感字段（name/certificateNo/phone）在 JSON 协议中为服务端解密后
/// 的明文，传输由信封加密保护。id 为数据库自增主键的字符串形式，
/// 客户端本地维护（未随儿童保存入库）时为空。
class ChildGuardianInfo {
  /// 构造函数：注入儿童监护人信息各字段。
  const ChildGuardianInfo({
    required this.childId,
    required this.name,
    required this.guardianRelationship,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.id,
    this.birthDate,
    this.certificateType,
    this.certificateNo,
    this.country,
    this.nation,
    this.educationLevel,
    this.occupation,
    this.phone,
    this.height,
    this.weight,
    this.employer,
    this.guardianOrder,
    this.createTime,
    this.updateTime,
  });

  /// 主键（自增 ID 的字符串形式；未入库时为 null）。
  final String? id;

  /// 儿童 ID（CHILD_INFO.ID 的字符串形式）。
  final String childId;

  /// 姓名（服务端加密存储）。
  final String name;

  /// 出生日期（yyyy-MM-dd）。
  final String? birthDate;

  /// 证件类型（存数据字典项目值）。
  final String? certificateType;

  /// 证件号码（服务端加密存储）。
  final String? certificateNo;

  /// 国籍（存数据字典项目值）。
  final String? country;

  /// 民族（存数据字典项目值）。
  final String? nation;

  /// 文化程度（存数据字典项目值）。
  final String? educationLevel;

  /// 职业（存数据字典项目值）。
  final String? occupation;

  /// 联系电话（服务端加密存储）。
  final String? phone;

  /// 身高（cm）。
  final String? height;

  /// 体重（kg）。
  final String? weight;

  /// 工作单位。
  final String? employer;

  /// 监护人与儿童关系（存数据字典项目值）。
  final String guardianRelationship;

  /// 监护人顺序（1-第一监护人，2-第二监护人）。
  final String? guardianOrder;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory ChildGuardianInfo.fromJson(Map<String, dynamic> json) {
    return ChildGuardianInfo(
      id: json['id'] as String?,
      childId: json['childId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      birthDate: json['birthDate'] as String?,
      certificateType: json['certificateType'] as String?,
      certificateNo: json['certificateNo'] as String?,
      country: json['country'] as String?,
      nation: json['nation'] as String?,
      educationLevel: json['educationLevel'] as String?,
      occupation: json['occupation'] as String?,
      phone: json['phone'] as String?,
      height: json['height'] as String?,
      weight: json['weight'] as String?,
      employer: json['employer'] as String?,
      guardianRelationship: json['guardianRelationship'] as String? ?? '',
      guardianOrder: json['guardianOrder'] as String?,
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      hospId: json['hospId'] as String? ?? '',
      hospName: json['hospName'] as String? ?? '',
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'childId': childId,
      'name': name,
      'birthDate': birthDate,
      'certificateType': certificateType,
      'certificateNo': certificateNo,
      'country': country,
      'nation': nation,
      'educationLevel': educationLevel,
      'occupation': occupation,
      'phone': phone,
      'height': height,
      'weight': weight,
      'employer': employer,
      'guardianRelationship': guardianRelationship,
      'guardianOrder': guardianOrder,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
