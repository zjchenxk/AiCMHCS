/// 医院详细信息
class HospitalInfo {
  String id;
  String orgCode; // 组织机构代码（统一社会信用代码）
  String name; // 医院名称
  String nameEn; // 医院英文名称
  String? logoBase64; // Logo base64（分辨率 <= 200x200）
  String? sealBase64; // 印章 base64（分辨率 <= 300x300）
  String province; // 省
  String city; // 市
  String county; // 区/县
  String town; //乡镇/街道
  String address; // 详细地址
  String phone; // 联系电话
  List<String> childIds; // 下级医院 id 列表（用于权限控制）

  HospitalInfo({
    required this.id,
    this.orgCode = '',
    this.name = '',
    this.nameEn = '',
    this.logoBase64,
    this.sealBase64,
    this.province = '',
    this.city = '',
    this.county = '',
    this.town = '',
    this.address = '',
    this.phone = '',
    List<String>? childIds,
  }) : childIds = childIds ?? [];
}
