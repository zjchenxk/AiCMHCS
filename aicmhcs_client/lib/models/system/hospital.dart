class Hospital {
  final String id;
  final String? parentId;
  final String code;
  final String name;
  final String? nameEn;
  final String province;
  final String city;
  final String? county;
  final String? town;
  final String address;
  final String? phoneNumber;
  final String? logoBase64;
  final String? sealBase64;
  final String? watermarkBase64;

  Hospital({
    required this.id,
    this.parentId,
    required this.code,
    required this.name,
    this.nameEn,
    required this.province,
    required this.city,
    this.county,
    this.town,
    required this.address,
    this.phoneNumber,
    this.logoBase64,
    this.sealBase64,
    this.watermarkBase64,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(
      id: json['id'] as String,
      parentId: json['parent_id'] as String?,
      code: json['code'] as String,
      name: json['name'] as String,
      nameEn: json['name_en'] as String?,
      province: json['province'] as String,
      city: json['city'] as String,
      county: json['county'] as String?,
      town: json['town'] as String?,
      address: json['address'] as String,
      phoneNumber: json['phone_number'] as String?,
      logoBase64: json['logo_base64'] as String?,
      sealBase64: json['seal_base64'] as String?,
      watermarkBase64: json['watermark_base64'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parent_id': parentId,
      'code': code,
      'name': name,
      'name_en': nameEn,
      'province': province,
      'city': city,
      'county': county,
      'town': town,
      'address': address,
      'phone_number': phoneNumber,
      'logo_base64': logoBase64,
      'seal_base64': sealBase64,
      'watermark_base64': watermarkBase64,
    };
  }
}