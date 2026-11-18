/// 高危因素字典项（BASE_HIGH_RISK_FACTOR，按医院隔离）。
///
/// 展示层按「高危颜色 → 大类 → 小类 → 名称」组织：大类/小类可为空
/// （空时名称直接置顶层），风险等级取数据字典 BASE_DICT（DICT_CODE=
/// 99010001）数据项的 ITEM_VALUE。所有列经数据库网关以字符串返回
/// （TINYINT 分值亦然），由模型层按需转换。
class BaseHighRiskFactor {
  /// 合法高危颜色（数据库存中文，顺序即界面分组顺序）。
  ///
  /// 服务端写入校验与客户端颜色下拉/分组共用本常量，避免两处维护。
  static const List<String> riskColors = ['绿色', '黄色', '橙色', '红色', '紫色'];

  /// 高危分值取值范围（RISK_SCORE 为 TINYINT 非负段；PostgreSQL 用
  /// SMALLINT 承载，应用层仍按此范围校验）。
  static const int riskScoreMin = 0;

  /// 高危分值上限。
  static const int riskScoreMax = 127;

  /// 构造函数：注入高危因素各字段。
  const BaseHighRiskFactor({
    required this.id,
    required this.riskFactorCode,
    required this.riskFactorName,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.riskFactorCategory,
    this.riskFactorSubcategory,
    this.riskColor,
    this.riskLevel,
    this.riskScore,
    this.createTime,
    this.updateTime,
  });

  /// 主键（应用侧生成的 UUID v7）。
  final String id;

  /// 大类（空为未设置，名称直接置顶层）。
  final String? riskFactorCategory;

  /// 小类（空为未设置，名称直接挂大类下）。
  final String? riskFactorSubcategory;

  /// 高危因素编码（同医院内唯一，由服务层校验）。
  final String riskFactorCode;

  /// 高危因素名称。
  final String riskFactorName;

  /// 高危颜色（中文五色：绿色/黄色/橙色/红色/紫色；空为未设置）。
  final String? riskColor;

  /// 高危等级（数据字典 BASE_DICT DICT_CODE=99010001 的 ITEM_VALUE）。
  final String? riskLevel;

  /// 高危分值（TINYINT，网关以字符串返回；空为未设置）。
  final String? riskScore;

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

  factory BaseHighRiskFactor.fromJson(Map<String, dynamic> json) {
    return BaseHighRiskFactor(
      id: json['id'] as String,
      riskFactorCategory: json['riskFactorCategory'] as String?,
      riskFactorSubcategory: json['riskFactorSubcategory'] as String?,
      riskFactorCode: json['riskFactorCode'] as String,
      riskFactorName: json['riskFactorName'] as String,
      riskColor: json['riskColor'] as String?,
      riskLevel: json['riskLevel'] as String?,
      riskScore: json['riskScore']?.toString(),
      creatorId: json['creatorId'] as String,
      creatorName: json['creatorName'] as String,
      hospId: json['hospId'] as String,
      hospName: json['hospName'] as String,
      createTime: json['createTime'] as String?,
      updateTime: json['updateTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'riskFactorCategory': riskFactorCategory,
      'riskFactorSubcategory': riskFactorSubcategory,
      'riskFactorCode': riskFactorCode,
      'riskFactorName': riskFactorName,
      'riskColor': riskColor,
      'riskLevel': riskLevel,
      'riskScore': riskScore,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
