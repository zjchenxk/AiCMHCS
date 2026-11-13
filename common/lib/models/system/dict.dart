/// 数据字典（归属医院经 hospId 关联 SYS_HOSPITAL，上级字典经 parentId
/// 自关联 BASE_DICT）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）。
class Dict {
  /// 构造函数：注入数据字典各字段。
  const Dict({
    required this.id,
    required this.dictCode,
    required this.dictName,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.parentId,
    this.displayOrder,
    this.createTime,
    this.updateTime,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 上级字典 ID（顶级字典为 null）。
  final String? parentId;

  /// 字典编码（同医院内唯一，回读新行 ID 的自然键之一）。
  final String dictCode;

  /// 字典名称。
  final String dictName;

  /// 显示顺序（树排序依据，未设置为 null、靠后显示）。
  final String? displayOrder;

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

  factory Dict.fromJson(Map<String, dynamic> json) {
    return Dict(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      dictCode: json['dictCode'] as String,
      dictName: json['dictName'] as String,
      displayOrder: json['displayOrder'] as String?,
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
      'parentId': parentId,
      'dictCode': dictCode,
      'dictName': dictName,
      'displayOrder': displayOrder,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}

/// 数据字典项目（经 dictId 逻辑关联所属字典 BASE_DICT，医院冗余列与
/// 所属字典保持一致）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）。
class DictItem {
  /// 构造函数：注入数据字典项目各字段。
  const DictItem({
    required this.id,
    required this.dictId,
    required this.itemCode,
    required this.itemValue,
    required this.isDefault,
    required this.creatorId,
    required this.creatorName,
    required this.hospId,
    required this.hospName,
    this.displayOrder,
    this.createTime,
    this.updateTime,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 所属字典 ID。
  final String dictId;

  /// 项目编码（同字典内唯一，回读新行 ID 的自然键之一）。
  final String itemCode;

  /// 项目值。
  final String itemValue;

  /// 是否默认值（1-是，0-否；同字典内至多一项默认，由服务层互斥保证）。
  final String isDefault;

  /// 显示顺序（列表排序依据，未设置为 null、靠后显示）。
  final String? displayOrder;

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

  factory DictItem.fromJson(Map<String, dynamic> json) {
    return DictItem(
      id: json['id'] as String,
      dictId: json['dictId'] as String,
      itemCode: json['itemCode'] as String,
      itemValue: json['itemValue'] as String,
      isDefault: json['isDefault'] as String,
      displayOrder: json['displayOrder'] as String?,
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
      'dictId': dictId,
      'itemCode': itemCode,
      'itemValue': itemValue,
      'isDefault': isDefault,
      'displayOrder': displayOrder,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'hospId': hospId,
      'hospName': hospName,
      'createTime': createTime,
      'updateTime': updateTime,
    };
  }
}
