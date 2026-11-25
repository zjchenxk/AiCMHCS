/// 孤独症初筛指导建议自定义模板（对应 ASD_INITIAL_SCREENING_GUIDANCE
/// 表，按医院隔离；科室/院区归属随创建人会话冗余）。
///
/// isPersonal='0' 为本院公共模板（全院可见），'1' 为个人模板（仅创建人
/// 可见、可改、可删——服务端校验仅创建人本人可修改/删除）。
class GuidanceTemplate {
  /// 构造函数：注入指导建议模板各字段。
  const GuidanceTemplate({
    required this.id,
    required this.guidance,
    required this.guidanceType,
    required this.isPersonal,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7 字符串形式）。
  final String id;

  /// 指导建议内容。
  final String guidance;

  /// 指导建议类别。
  final String guidanceType;

  /// 是否个人模板（0-否=本院公共，1-是=个人）。
  final String isPersonal;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 归属科室 ID。
  final String? deptId;

  /// 归属科室名称。
  final String? deptName;

  /// 归属院区 ID。
  final String? campusId;

  /// 归属院区名称。
  final String? campusName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory GuidanceTemplate.fromJson(Map<String, dynamic> json) {
    return GuidanceTemplate(
      id: json['id'] as String? ?? '',
      guidance: json['guidance'] as String? ?? '',
      guidanceType: json['guidanceType'] as String? ?? '',
      isPersonal: json['isPersonal'] as String? ?? '0',
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      deptId: json['deptId'] as String?,
      deptName: json['deptName'] as String?,
      campusId: json['campusId'] as String?,
      campusName: json['campusName'] as String?,
      hospId: json['hospId'] as String? ?? '',
      hospName: json['hospName'] as String? ?? '',
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'guidance': guidance,
      'guidanceType': guidanceType,
      'isPersonal': isPersonal,
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
