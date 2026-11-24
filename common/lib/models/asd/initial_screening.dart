/// 孤独症初筛记录（对应 ASD_INITIAL_SCREENING 表，经 childId 逻辑关联
/// 儿童 CHILD_INFO，按医院隔离；同一儿童同一检查时段 checkMonth 至多
/// 一条记录，TAB 界面按月龄逐条新增/修改）。
///
/// 实足年龄（ageYear/ageMonth/ageDay）由客户端按检查日期与出生日期
/// 算好后随保存下发；纠正年龄三段仅早产儿在矫正窗口内存在（可空）。
/// warningSignResult 为预警征象条目名称集合（未见异常或若干条目名，
/// 顿号连接）；languageSocialCommunicationResult 为语言功能和社会交往
/// 能力询问结果（未见异常，或「语言功能障碍或倒退」「社会交往能力
/// 障碍或倒退」的顿号连接组合）；checkResult 由前两者自动推导（均未见
/// 异常→未见异常，否则异常）。hasReferral='0' 时 referralHospName
/// 统一存「无」（列 NOT NULL，达梦空串作 NULL 不可用）、科室名称为空。
class InitialScreening {
  /// 构造函数：注入孤独症初筛记录各字段。
  const InitialScreening({
    required this.childId,
    required this.checkDate,
    required this.ageYear,
    required this.ageMonth,
    required this.ageDay,
    required this.checkMonth,
    required this.warningSignResult,
    required this.languageSocialCommunicationResult,
    required this.checkResult,
    required this.hasReferral,
    required this.referralHospName,
    required this.doctorId,
    required this.doctorName,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.id,
    this.correctedAgeYear,
    this.correctedAgeMonth,
    this.correctedAgeDay,
    this.referralHospId,
    this.referralDeptId,
    this.referralDeptName,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7 字符串形式；未入库时为 null）。
  final String? id;

  /// 儿童 ID（CHILD_INFO.ID 的字符串形式）。
  final String childId;

  /// 检查日期（yyyy-MM-dd）。
  final String checkDate;

  /// 实足年龄-岁。
  final int ageYear;

  /// 实足年龄-月。
  final int ageMonth;

  /// 实足年龄-天。
  final int ageDay;

  /// 纠正年龄-岁（非早产儿/超出矫正窗口为 null）。
  final int? correctedAgeYear;

  /// 纠正年龄-月。
  final int? correctedAgeMonth;

  /// 纠正年龄-天。
  final int? correctedAgeDay;

  /// 检查时段（3-3月龄，6-6月龄，8-8月龄，12-12月龄，18-18月龄，
  /// 24-24月龄，30-30月龄，36-36月龄，48-4岁，60-5岁，72-6岁）。
  final int checkMonth;

  /// 预警征象筛查结果（未见异常，或若干条目名称顿号连接）。
  final String warningSignResult;

  /// 语言功能和社会交往能力询问结果。
  final String languageSocialCommunicationResult;

  /// 初筛结果（未见异常/异常）。
  final String checkResult;

  /// 有无转诊（0-无/1-有）。
  final String hasReferral;

  /// 转诊医院 ID（选中字典数据项时存 BASE_DICT_ITEM.ID；自由输入为 null）。
  final String? referralHospId;

  /// 转诊医院名称（无转诊时存「无」）。
  final String referralHospName;

  /// 转诊科室 ID（可空）。
  final String? referralDeptId;

  /// 转诊科室名称（可空）。
  final String? referralDeptName;

  /// 检查医生 ID。
  final String doctorId;

  /// 检查医生姓名。
  final String doctorName;

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

  factory InitialScreening.fromJson(Map<String, dynamic> json) {
    return InitialScreening(
      id: json['id'] as String?,
      childId: json['childId'] as String? ?? '',
      checkDate: json['checkDate'] as String? ?? '',
      ageYear: (json['ageYear'] as num?)?.toInt() ?? 0,
      ageMonth: (json['ageMonth'] as num?)?.toInt() ?? 0,
      ageDay: (json['ageDay'] as num?)?.toInt() ?? 0,
      correctedAgeYear: (json['correctedAgeYear'] as num?)?.toInt(),
      correctedAgeMonth: (json['correctedAgeMonth'] as num?)?.toInt(),
      correctedAgeDay: (json['correctedAgeDay'] as num?)?.toInt(),
      checkMonth: (json['checkMonth'] as num?)?.toInt() ?? 0,
      warningSignResult: json['warningSignResult'] as String? ?? '',
      languageSocialCommunicationResult: json['languageSocialCommunicationResult'] as String? ?? '',
      checkResult: json['checkResult'] as String? ?? '',
      hasReferral: json['hasReferral'] as String? ?? '0',
      referralHospId: json['referralHospId'] as String?,
      referralHospName: json['referralHospName'] as String? ?? '',
      referralDeptId: json['referralDeptId'] as String?,
      referralDeptName: json['referralDeptName'] as String?,
      doctorId: json['doctorId'] as String? ?? '',
      doctorName: json['doctorName'] as String? ?? '',
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
      'correctedAgeYear': correctedAgeYear,
      'correctedAgeMonth': correctedAgeMonth,
      'correctedAgeDay': correctedAgeDay,
      'checkMonth': checkMonth,
      'warningSignResult': warningSignResult,
      'languageSocialCommunicationResult': languageSocialCommunicationResult,
      'checkResult': checkResult,
      'hasReferral': hasReferral,
      'referralHospId': referralHospId,
      'referralHospName': referralHospName,
      'referralDeptId': referralDeptId,
      'referralDeptName': referralDeptName,
      'doctorId': doctorId,
      'doctorName': doctorName,
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
