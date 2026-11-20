/// 高危因素互斥规则（BASE_HIGH_RISK_FACTOR_EXCLUSION，按医院隔离）。
///
/// 一条规则表示「这几项高危因素互斥，只能选其一」：first/second 必填、
/// third 可空，三个 ID 逻辑引用 BASE_HIGH_RISK_FACTOR.ID（无序集合，
/// 同一组合不区分前后顺序）。创建人与医院由服务端从登录会话推导并
/// 冗余存储，客户端只读。所有列经数据库网关以字符串返回。
class BaseHighRiskFactorExclusion {
  /// 构造函数：注入互斥规则各字段。
  const BaseHighRiskFactorExclusion({
    required this.id,
    required this.firstRiskFactorId,
    required this.secondRiskFactorId,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.thirdRiskFactorId,
    this.createTime,
    this.updateTime,
  });

  /// 主键（应用侧生成的 UUID v7）。
  final String id;

  /// 第一个高危因素 ID（BASE_HIGH_RISK_FACTOR.ID）。
  final String firstRiskFactorId;

  /// 第二个高危因素 ID（BASE_HIGH_RISK_FACTOR.ID）。
  final String secondRiskFactorId;

  /// 第三个高危因素 ID（BASE_HIGH_RISK_FACTOR.ID；空为两项互斥）。
  final String? thirdRiskFactorId;

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

  /// 规则涉及的高危因素 ID 列表（按 first/second/third 顺序，过滤空值）。
  List<String> get riskFactorIds => [
    firstRiskFactorId,
    secondRiskFactorId,
    if (thirdRiskFactorId != null && thirdRiskFactorId!.isNotEmpty) thirdRiskFactorId!,
  ];

  factory BaseHighRiskFactorExclusion.fromJson(Map<String, dynamic> json) {
    return BaseHighRiskFactorExclusion(
      id: json['id'] as String,
      firstRiskFactorId: json['firstRiskFactorId'] as String,
      secondRiskFactorId: json['secondRiskFactorId'] as String,
      thirdRiskFactorId: json['thirdRiskFactorId'] as String?,
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
      'firstRiskFactorId': firstRiskFactorId,
      'secondRiskFactorId': secondRiskFactorId,
      'thirdRiskFactorId': thirdRiskFactorId,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
