/// 儿童高危因素（对应 CHILD_HIGH_RISK_FACTOR 表，经 childId 逻辑关联
/// 儿童 CHILD_INFO，按医院隔离；随儿童档案保存整表替换，同一儿童仅
/// 保留最近一次保存的勾选集合）。
///
/// highRiskFactorId 逻辑引用高危因素字典 BASE_HIGH_RISK_FACTOR.ID；
/// riskFactorCode/riskFactorName/riskColor/riskLevel/riskScore 为保存
/// 当时的字典值冗余快照（字典项后续改名/改级不影响历史档案）。各字段
/// 均为字符串口径（网关契约），riskScore 为分值的字符串形式。
class ChildHighRiskFactor {
  /// 构造函数：注入儿童高危因素各字段。
  const ChildHighRiskFactor({
    required this.childId,
    required this.highRiskFactorId,
    required this.riskFactorCode,
    required this.riskFactorName,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.id,
    this.riskColor,
    this.riskLevel,
    this.riskScore,
    this.deptId,
    this.deptName,
    this.campusId,
    this.campusName,
    this.createTime,
    this.updateTime,
  });

  /// 主键（UUID v7 字符串形式；未入库时为 null）。
  final String? id;

  /// 儿童 ID（CHILD_INFO.ID）。
  final String childId;

  /// 高危因素 ID（BASE_HIGH_RISK_FACTOR.ID）。
  final String highRiskFactorId;

  /// 高危因素编码（保存当时的字典值快照）。
  final String riskFactorCode;

  /// 高危因素名称（保存当时的字典值快照）。
  final String riskFactorName;

  /// 高危颜色（绿色/黄色/橙色/红色/紫色）。
  final String? riskColor;

  /// 高危等级（如Ⅰ、Ⅱ、Ⅲ，A、B等）。
  final String? riskLevel;

  /// 高危分值（字符串形式的整数）。
  final String? riskScore;

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

  factory ChildHighRiskFactor.fromJson(Map<String, dynamic> json) {
    return ChildHighRiskFactor(
      id: json['id'] as String?,
      childId: json['childId'] as String? ?? '',
      highRiskFactorId: json['highRiskFactorId'] as String? ?? '',
      riskFactorCode: json['riskFactorCode'] as String? ?? '',
      riskFactorName: json['riskFactorName'] as String? ?? '',
      riskColor: json['riskColor'] as String?,
      riskLevel: json['riskLevel'] as String?,
      riskScore: json['riskScore'] as String?,
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
      'highRiskFactorId': highRiskFactorId,
      'riskFactorCode': riskFactorCode,
      'riskFactorName': riskFactorName,
      'riskColor': riskColor,
      'riskLevel': riskLevel,
      'riskScore': riskScore,
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
