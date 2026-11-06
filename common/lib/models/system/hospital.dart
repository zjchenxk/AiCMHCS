/// 医院（医联体树形，PARENT_ID 自关联上级医院，顶级为 null）。
///
/// id 为数据库自增主键的字符串形式（两库网关所有列均以字符串返回）；
/// hasChildren 由列表查询附带（供树形 UI 显示展开箭头），落库不存。
class Hospital {
  /// 构造函数：注入医院各字段。
  const Hospital({
    required this.id,
    this.parentId,
    this.code,
    required this.name,
    this.nameEn,
    required this.province,
    required this.city,
    this.county,
    this.town,
    required this.address,
    this.tel,
    this.logoBase64,
    this.sealBase64,
    this.watermarkBase64,
    this.hasChildren = false,
  });

  /// 主键（自增 ID 的字符串形式）。
  final String id;

  /// 上级医院 ID（顶级医院为 null）。
  final String? parentId;

  /// 组织机构代码（统一社会信用代码）。
  final String? code;

  /// 医院名称。
  final String name;

  /// 医院英文名称。
  final String? nameEn;

  /// 地址：省/直辖市/自治区。
  final String province;

  /// 地址：市/自治州/地区。
  final String city;

  /// 地址：县/区/旗。
  final String? county;

  /// 地址：乡/镇/街道。
  final String? town;

  /// 地址：路/门牌号码。
  final String address;

  /// 联系电话。
  final String? tel;

  /// LOGO 图片 base64。
  final String? logoBase64;

  /// 印章图片 base64。
  final String? sealBase64;

  /// 水印图片 base64。
  final String? watermarkBase64;

  /// 是否存在下级医院（列表接口附带，缺省视为无）。
  final bool hasChildren;

  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      code: json['code'] as String?,
      name: json['name'] as String,
      nameEn: json['nameEn'] as String?,
      province: json['province'] as String,
      city: json['city'] as String,
      county: json['county'] as String?,
      town: json['town'] as String?,
      address: json['address'] as String,
      tel: json['tel'] as String?,
      logoBase64: json['logoBase64'] as String?,
      sealBase64: json['sealBase64'] as String?,
      watermarkBase64: json['watermarkBase64'] as String?,
      hasChildren: json['hasChildren'] == true || json['hasChildren'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'code': code,
      'name': name,
      'nameEn': nameEn,
      'province': province,
      'city': city,
      'county': county,
      'town': town,
      'address': address,
      'tel': tel,
      'logoBase64': logoBase64,
      'sealBase64': sealBase64,
      'watermarkBase64': watermarkBase64,
      'hasChildren': hasChildren,
    };
  }
}
