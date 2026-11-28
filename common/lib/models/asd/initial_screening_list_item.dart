/// 初筛记录列表项（侧边栏「初筛儿童」列表查询结果，非 CHILD 表直映）。
///
/// 由 ASD_INITIAL_SCREENING 经 CHILD_ID JOIN CHILD_INFO 取解密后的儿童
/// 姓名，按医院隔离、检查日期倒序分页返回；仅含列表展示与「双击打开
/// 初筛记录表」所需的最小字段集。
class InitialScreeningListItem {
  /// 构造函数：注入列表项各字段。
  const InitialScreeningListItem({
    required this.id,
    required this.childId,
    required this.childName,
    required this.checkDate,
    required this.checkMonth,
    required this.checkResult,
  });

  /// 初筛记录主键（UUID v7）。
  final String id;

  /// 儿童 ID（CHILD_INFO.ID，双击打开初筛记录表时切换当前儿童用）。
  final String childId;

  /// 儿童姓名（服务端解密后的明文；儿童档案被删除时为「（已删除）」）。
  final String childName;

  /// 检查日期（yyyy-MM-dd）。
  final String checkDate;

  /// 检查时段（3/6/8/12/18/24/30/36/48/60/72）。
  final int checkMonth;

  /// 初筛结果（未见异常/异常）。
  final String checkResult;

  factory InitialScreeningListItem.fromJson(Map<String, dynamic> json) {
    return InitialScreeningListItem(
      id: json['id'] as String? ?? '',
      childId: json['childId'] as String? ?? '',
      childName: json['childName'] as String? ?? '',
      checkDate: json['checkDate'] as String? ?? '',
      checkMonth: (json['checkMonth'] as num?)?.toInt() ?? 0,
      checkResult: json['checkResult'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'childId': childId,
      'childName': childName,
      'checkDate': checkDate,
      'checkMonth': checkMonth,
      'checkResult': checkResult,
    };
  }
}
