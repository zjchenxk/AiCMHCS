/// 科室（归属医院经 hospId 关联 SYS_HOSPITAL，可选归属院区经 campusId
/// 关联 SYS_CAMPUS，上级科室经 parentId 自关联 SYS_DEPARTMENT）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）。
class Department {
  /// 构造函数：注入科室各字段。
  const Department({
    required this.id,
    required this.hospId,
    required this.code,
    required this.name,
    this.campusId,
    this.parentId,
    this.address,
    this.tel,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 所属医院 ID。
  final String hospId;

  /// 所属院区 ID（直接挂医院下的顶级科室为 null）。
  final String? campusId;

  /// 上级科室 ID（顶级科室为 null）。
  final String? parentId;

  /// 科室代码（全表唯一）。
  final String code;

  /// 科室名称（同挂载点内唯一）。
  final String name;

  /// 地址。
  final String? address;

  /// 联系电话。
  final String? tel;

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as String,
      hospId: json['hospId'] as String,
      campusId: json['campusId'] as String?,
      parentId: json['parentId'] as String?,
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
      'campusId': campusId,
      'parentId': parentId,
      'code': code,
      'name': name,
      'address': address,
      'tel': tel,
    };
  }
}
