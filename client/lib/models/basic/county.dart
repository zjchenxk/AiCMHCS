import 'package:client/models/basic/town.dart';

class County {
  final String code;
  final String name;
  final List<Town> towns;

  County({required this.code, required this.name, required this.towns});

  factory County.fromJson(Map<String, dynamic> json) {
    return County(
      code: json['code'] as String,
      name: json['name'] as String,
      towns: (json['towns'] as List<dynamic>).map((e) => Town.fromJson(e)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'towns': towns.map((town) => town.toJson()).toList(),
    };
  }
}