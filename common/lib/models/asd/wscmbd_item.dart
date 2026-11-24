/// 儿童心理行为发育问题预警征象筛查表条目（对应 SCALE_WSCMBD 表）。
///
/// 全局基础数据（不按医院隔离、无管理界面），按月龄 month 存放各检查
/// 时段的预警征象条目，初筛记录界面的【预警征象筛查结果】选项即取同
/// 月龄条目并按 itemOrder 升序排列（另加一个互斥的【未见异常】选项）。
class WscmbdItem {
  /// 构造函数：注入预警征象条目各字段。
  const WscmbdItem({
    required this.id,
    required this.month,
    required this.itemName,
    required this.itemType,
    required this.itemOrder,
    this.itemDesc,
  });

  /// 主键（自增 BIGINT）。
  final int id;

  /// 月龄（3/6/8/12/18/24/30/36，48/60/72=4/5/6 岁）。
  final int month;

  /// 条目名称（如「对很大声音没有反应」）。
  final String itemName;

  /// 条目类别（1-语言，2-个人社交，3-精细动作，4-大运动）。
  final int itemType;

  /// 条目序号（同月龄内升序展示）。
  final int itemOrder;

  /// 条目描述（可空）。
  final String? itemDesc;

  factory WscmbdItem.fromJson(Map<String, dynamic> json) {
    return WscmbdItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      itemName: json['itemName'] as String? ?? '',
      itemType: (json['itemType'] as num?)?.toInt() ?? 0,
      itemOrder: (json['itemOrder'] as num?)?.toInt() ?? 0,
      itemDesc: json['itemDesc'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'month': month,
      'itemName': itemName,
      'itemType': itemType,
      'itemOrder': itemOrder,
      'itemDesc': itemDesc,
    };
  }
}
