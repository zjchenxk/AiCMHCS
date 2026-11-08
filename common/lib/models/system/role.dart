/// 角色（归属医院经 hospId 关联 SYS_HOSPITAL，菜单权限经
/// SYS_ROLE_PERMISSION 关联 SYS_MENU）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）。
class Role {
  /// 构造函数：注入角色各字段。
  const Role({
    required this.id,
    required this.roleCode,
    required this.roleName,
    required this.hospId,
    this.remark,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 角色编码（同医院内唯一）。
  final String roleCode;

  /// 角色名称（同医院内唯一）。
  final String roleName;

  /// 备注。
  final String? remark;

  /// 所属医院 ID。
  final String hospId;

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] as String,
      roleCode: json['roleCode'] as String,
      roleName: json['roleName'] as String,
      remark: json['remark'] as String?,
      hospId: json['hospId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roleCode': roleCode,
      'roleName': roleName,
      'remark': remark,
      'hospId': hospId,
    };
  }
}
