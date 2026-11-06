import 'package:common/model.dart';

/// 医院详细信息（表单编辑态的可变模型，后端态为 common 包的 Hospital）。
class HospitalInfo {
  String id;
  String? parentId; // 上级医院 id
  String? code; // 组织机构代码（统一社会信用代码）
  String name; // 医院名称
  String? nameEn; // 医院英文名称
  String province; // 省
  String city; // 市
  String? county; // 区/县
  String? town; //乡镇/街道
  String address; // 详细地址
  String tel; // 联系电话
  String? logoImage; // Logo base64（分辨率 <= 200x200）
  String? sealImage; // 印章 base64（分辨率 <= 300x300）
  String? watermarkImage; // 水印 base64（分辨率 <= 300x300）
  List<String> childIds; // 下级医院 id 列表（用于权限控制）

  HospitalInfo({
    required this.id,
    this.parentId,
    this.code,
    this.name = '',
    this.nameEn,
    this.province = '',
    this.city = '',
    this.county,
    this.town,
    this.address = '',
    this.tel = '',
    this.logoImage,
    this.sealImage,
    this.watermarkImage,
    List<String>? childIds,
  }) : childIds = childIds ?? [];

  /// 从后端共享模型构建（编辑态表单回填）。
  factory HospitalInfo.fromHospital(Hospital hospital) {
    return HospitalInfo(
      id: hospital.id,
      parentId: hospital.parentId,
      code: hospital.code,
      name: hospital.name,
      nameEn: hospital.nameEn,
      province: hospital.province,
      city: hospital.city,
      county: hospital.county,
      town: hospital.town,
      address: hospital.address,
      tel: hospital.tel ?? '',
      logoImage: hospital.logoBase64,
      sealImage: hospital.sealBase64,
      watermarkImage: hospital.watermarkBase64,
    );
  }

  /// 导出为修改接口的 changes（键与 /api/hospital/update 契约一致）。
  Map<String, Object?> toChanges() {
    return {
      'code': code,
      'name': name,
      'nameEn': nameEn,
      'province': province,
      'city': city,
      'county': county,
      'town': town,
      'address': address,
      'tel': tel,
      'logoBase64': logoImage,
      'sealBase64': sealImage,
      'watermarkBase64': watermarkImage,
    };
  }
}
