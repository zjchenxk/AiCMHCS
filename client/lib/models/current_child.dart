/// 当前儿童上下文（主界面顶部搜索选中后写入 MainViewModel，随
/// BasePage 分发到各功能页；未选择儿童时各字段为空串占位）。
class CurrentChild {
  /// 儿童档案 ID（CHILD_INFO.ID；未选择/未建档为空串，儿童建档页据此
  /// 自动载入整档）。
  final String id;
  final String visitCardNo; // 就诊卡号
  final String patientId; // 病人ID
  final String name; // 姓名
  final String gender; // 性别
  final DateTime birthDate; // 出生日期
  final String gestationalWeek; // 出生孕周 如 38+2
  final String actualAge; // 实际年龄
  final String correctedAge; // 纠正年龄
  final String phone; // 联系电话

  const CurrentChild({
    this.id = '',
    required this.visitCardNo,
    required this.patientId,
    required this.name,
    required this.gender,
    required this.birthDate,
    this.gestationalWeek = '',
    this.actualAge = '',
    this.correctedAge = '',
    required this.phone,
  });
}
