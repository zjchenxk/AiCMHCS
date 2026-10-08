import 'city.dart';

class Province {
  final String code;
  final String name;
  final List<City> cities;

  Province({required this.code, required this.name, required this.cities});

  factory Province.fromJson(Map<String, dynamic> json) {
    return Province(code: json['code'] as String, name: json['name'] as String, cities: (json['cities'] as List<dynamic>).map((e) => City.fromJson(e)).toList());
  }

  Map<String, dynamic> toJson() {
    return {'code': code, 'name': name, 'cities': cities.map((city) => city.toJson()).toList()};
  }
}
