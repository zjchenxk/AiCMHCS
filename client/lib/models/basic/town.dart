import 'package:client/models/basic/village.dart';

class Town {
  final String code;
  final String name;
  final List<Village> villages;

  Town({required this.code, required this.name, required this.villages});

  factory Town.fromJson(Map<String, dynamic> json) {
    return Town(
      code: json['code'],
      name: json['name'],
      villages: (json['villages'] as List<dynamic>).map((e) => Village.fromJson(e)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'villages': villages.map((village) => village.toJson()).toList(),
    };
  }
}