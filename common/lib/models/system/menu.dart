/// 菜单项目（上级项目经 parentId 自关联构成「模块→菜单→操作」树）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）。
class Menu {
  /// 构造函数：注入菜单项目各字段。
  const Menu({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.itemType,
    required this.visible,
    this.parentId,
    this.menuRoute,
    this.menuIcon,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 上级项目 ID（顶级项目为 null）。
  final String? parentId;

  /// 项目编码（全表唯一）。
  final String itemCode;

  /// 项目名称。
  final String itemName;

  /// 项目类型：'1'-模块、'2'-菜单、'3'-操作。
  final String itemType;

  /// 菜单路由（项目类型为菜单时必有）。
  final String? menuRoute;

  /// 菜单图标名（Material 图标名的字符串形式）。
  final String? menuIcon;

  /// 是否显示：'1'-是、'0'-否。
  final String visible;

  factory Menu.fromJson(Map<String, dynamic> json) {
    return Menu(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      itemCode: json['itemCode'] as String,
      itemName: json['itemName'] as String,
      itemType: json['itemType'] as String,
      menuRoute: json['menuRoute'] as String?,
      menuIcon: json['menuIcon'] as String?,
      visible: json['visible'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'itemCode': itemCode,
      'itemName': itemName,
      'itemType': itemType,
      'menuRoute': menuRoute,
      'menuIcon': menuIcon,
      'visible': visible,
    };
  }
}
