class ChildInfo {
  final String cardNo; // 就诊卡号
  final String patientId; // 病人ID
  final String name; // 姓名
  final String gender; // 性别
  final DateTime birthDate; // 出生日期
  final String gestationalWeek; // 出生孕周 如 38+2
  final String actualAge; // 实际年龄
  final String correctedAge; // 纠正年龄
  final String phone; // 联系电话

  const ChildInfo({
    required this.cardNo,
    required this.patientId,
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.gestationalWeek,
    required this.actualAge,
    required this.correctedAge,
    required this.phone,
  });
}
