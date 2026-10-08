class Village {
  String? code;
  String? name;

  Village({this.code, this.name});

  factory Village.fromJson(Map<String, dynamic> json) {
    return Village(
      code: json['code'] as String?,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
    };
  }
}