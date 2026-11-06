/// 院区（归属医院经 hospId 关联 SYS_HOSPITAL）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）。
class Campus {
  /// 构造函数：注入院区各字段。
  const Campus({
    required this.id,
    required this.hospId,
    required this.code,
    required this.name,
    this.address,
    this.tel,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 所属医院 ID。
  final String hospId;

  /// 院区代码（全表唯一）。
  final String code;

  /// 院区名称（同医院内唯一）。
  final String name;

  /// 院区地址。
  final String? address;

  /// 联系电话。
  final String? tel;

  factory Campus.fromJson(Map<String, dynamic> json) {
    return Campus(
      id: json['id'] as String,
      hospId: json['hospId'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      tel: json['tel'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hospId': hospId,
      'code': code,
      'name': name,
      'address': address,
      'tel': tel,
    };
  }
}
