/// 儿童检查记录（对应 CHILD_CHECK_RECORD 表，经 childId 逻辑关联儿童
/// CHILD_INFO，按医院隔离；初筛保存时按来源键联动写入/更新，供侧边栏
/// 「历次检查」时间轴等汇总展示）。
///
/// 各字段均为数据库列的字符串形式（网关契约）；CHECK_DATE 为
/// yyyy-MM-dd，AGE_YEAR/AGE_MONTH/AGE_DAY 为检查时的实足年龄三段。
class ChildCheckRecord {
  /// 构造函数：注入检查记录各字段。
  const ChildCheckRecord({
    required this.childId,
    required this.checkDate,
    required this.ageYear,
    required this.ageMonth,
    required this.ageDay,
    required this.checkType,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.id,
    this.checkFindings,
    this.checkResult,
    this.dataSrcName,
    this.dataSrcId,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7 字符串形式）。
  final String? id;

  /// 儿童 ID（CHILD_INFO.ID）。
  final String childId;

  /// 检查日期（yyyy-MM-dd）。
  final String checkDate;

  /// 检查时年龄-岁。
  final String ageYear;

  /// 检查时年龄-月。
  final String ageMonth;

  /// 检查时年龄-天。
  final String ageDay;

  /// 检查类型（如「孤独症初筛」）。
  final String checkType;

  /// 检查所见。
  final String? checkFindings;

  /// 检查结果。
  final String? checkResult;

  /// 数据来源名称（写入来源表名）。
  final String? dataSrcName;

  /// 数据来源 ID（来源记录主键）。
  final String? dataSrcId;

  /// 创建人 ID。
  final String creatorId;

  /// 创建人姓名。
  final String creatorName;

  /// 科室 ID。
  final String? deptId;

  /// 科室名称。
  final String? deptName;

  /// 院区 ID。
  final String? campusId;

  /// 院区名称。
  final String? campusName;

  /// 所属医院 ID。
  final String hospId;

  /// 所属医院名称。
  final String hospName;

  /// 创建时间。
  final String? createTime;

  /// 更新时间。
  final String? updateTime;

  factory ChildCheckRecord.fromJson(Map<String, dynamic> json) {
    return ChildCheckRecord(
      id: json['id'] as String?,
      childId: json['childId'] as String? ?? '',
      checkDate: json['checkDate'] as String? ?? '',
      ageYear: json['ageYear'] as String? ?? '',
      ageMonth: json['ageMonth'] as String? ?? '',
      ageDay: json['ageDay'] as String? ?? '',
      checkType: json['checkType'] as String? ?? '',
      checkFindings: json['checkFindings'] as String?,
      checkResult: json['checkResult'] as String?,
      dataSrcName: json['dataSrcName'] as String?,
      dataSrcId: json['dataSrcId'] as String?,
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
      'childId': childId,
      'checkDate': checkDate,
      'ageYear': ageYear,
      'ageMonth': ageMonth,
      'ageDay': ageDay,
      'checkType': checkType,
      'checkFindings': checkFindings,
      'checkResult': checkResult,
      'dataSrcName': dataSrcName,
      'dataSrcId': dataSrcId,
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
