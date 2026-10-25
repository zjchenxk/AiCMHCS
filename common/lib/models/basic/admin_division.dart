/// 行政区划（扁平模型，省/市/县/乡/村五级共用一张表，树形由 parentCode 关联）。
///
/// 与 Province/City/County/Town/Village 嵌套模型（表单地址级联用）不同，
/// 本模型面向行政区划管理：按需加载某一级的子列表（hasChildren 标记
/// 是否还有下级，供树形 UI 显示展开箭头），code 为主键不可变更。
class AdminDivision {
  /// 构造函数：注入区划代码、名称、上级行政区划代码、是否有下级。
  const AdminDivision({required this.code, required this.name, this.parentCode, this.hasChildren = false});

  /// 行政区划代码（2~12 位数字，主键）。
  final String code;

  /// 行政区划名称。
  final String name;

  /// 上级行政区划代码（省级为 null）。
  final String? parentCode;

  /// 是否存在下级行政区划（列表接口附带，缺省视为无）。
  final bool hasChildren;

  /// 是否村/居委会级：村级代码为 12 位（国标全码与最短码体系一致），
  /// 是五级区划的最末级，不允许再添加下级。
  bool get isVillageLevel => code.length >= 12;

  factory AdminDivision.fromJson(Map<String, dynamic> json) {
    return AdminDivision(code: json['code'] as String, name: json['name'] as String, parentCode: json['parentCode'] as String?, hasChildren: json['hasChildren'] == true || json['hasChildren'] == 1);
  }

  Map<String, dynamic> toJson() {
    return {'code': code, 'name': name, 'parentCode': parentCode, 'hasChildren': hasChildren};
  }
}
