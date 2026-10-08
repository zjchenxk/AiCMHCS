import 'county.dart';

class City {
  final String code;
  final String name;
  final List<County> counties;

  City({required this.code, required this.name, required this.counties});

  factory City.fromJson(Map<String, dynamic> json) {
    return City(code: json['code'], name: json['name'], counties: (json['counties'] as List<dynamic>).map((e) => County.fromJson(e)).toList());
  }

  Map<String, dynamic> toJson() {
    return {'code': code, 'name': name, 'counties': counties.map((county) => county.toJson()).toList()};
  }
}
