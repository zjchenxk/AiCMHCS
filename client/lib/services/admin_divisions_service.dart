import 'dart:convert';
import 'package:client/main.dart';
import 'package:client/utils/security_util.dart';
import 'package:common/model.dart';

class AdminDivisionsService {
  /// 获取省/自治区/直辖市列表
  /// return 省/自治区/直辖市列表
  Future<List<Province>?> getProvinces() async {
    if (token == null) {
      throw Exception('用户未登录或登录已过期，请重新登录！');
    }

    var encryptedResponse = ''; // await client.adminDivisions.getProvinces(token!);
    if (encryptedResponse.isEmpty) {
      throw Exception('获取省/自治区/直辖市列表失败！响应消息为空');
    }

    var decryptedResponse = await SecurityUtil.decryptAES(encryptedResponse);

    var jsonResponse = jsonDecode(decryptedResponse) as Map<String, dynamic>;
    if (jsonResponse.isEmpty) {
      throw Exception('获取省/自治区/直辖市列表失败！出参为空');
    }

    if (!jsonResponse.containsKey('code')) {
      throw Exception('获取省/自治区/直辖市列表失败！出参中未包含: code');
    }

    var code = jsonResponse['code'] as int;
    if (code != 0) {
      if (!jsonResponse.containsKey('message')) {
        throw Exception('获取省/自治区/直辖市列表失败！出参中未包含: message');
      }

      var message = jsonResponse['message'] as String;
      throw Exception('获取省/自治区/直辖市列表失败！$message');
    }

    if (!jsonResponse.containsKey('data')) {
      throw Exception('获取省/自治区/直辖市列表失败！出参中未包含: data');
    }

    List<Map<String, dynamic>> maps = (jsonResponse['data'] as List).cast<Map<String, dynamic>>();
    if (maps.isNotEmpty) {
      final provinces = maps.map((m) => Province.fromJson(m)).toList();
      return provinces;
    }
    return null;
  }

  /// 获取指定省/自治区/直辖市的市/州列表
  /// param provinceCode：省/直辖市/自治区代码
  /// return 市/州列表
  Future<List<City>?> getCitiesByProvince(String provinceCode) async {
    if (token == null) {
      throw Exception('用户未登录或登录已过期，请重新登录！');
    }

    var encryptedResponse = ''; // await client.adminDivisions.getCitiesByProvince(token!, provinceCode);
    if (encryptedResponse.isEmpty) {
      throw Exception('获取市/州列表失败！响应消息为空');
    }

    var decryptedResponse = await SecurityUtil.decryptAES(encryptedResponse);

    var jsonResponse = jsonDecode(decryptedResponse) as Map<String, dynamic>;
    if (jsonResponse.isEmpty) {
      throw Exception('获取市/州列表失败！出参为空');
    }

    if (!jsonResponse.containsKey('code')) {
      throw Exception('获取市/州列表失败！出参中未包含: code');
    }

    var code = jsonResponse['code'] as int;
    if (code != 0) {
      if (!jsonResponse.containsKey('message')) {
        throw Exception('获取市/州列表失败！出参中未包含: message');
      }

      var message = jsonResponse['message'] as String;
      throw Exception('获取市/州列表失败！$message');
    }

    if (!jsonResponse.containsKey('data')) {
      throw Exception('获取市/州列表失败！出参中未包含: data');
    }

    List<Map<String, dynamic>> maps = (jsonResponse['data'] as List).cast<Map<String, dynamic>>();
    if (maps.isNotEmpty) {
      final cities = maps.map((m) => City.fromJson(m)).toList();
      return cities;
    }
    return null;
  }

  /// 获取指定市/州的县/区/旗列表
  /// param cityCode：市/州代码
  /// return 县/区/旗列表
  Future<List<County>?> getCountiesByCity(String cityCode) async {
    if (token == null) {
      throw Exception('用户未登录或登录已过期，请重新登录！');
    }

    var encryptedResponse = ''; // await client.adminDivisions.getCountiesByCity(token!, cityCode);
    if (encryptedResponse.isEmpty) {
      throw Exception('获取县/区/旗列表失败！响应消息为空');
    }

    var decryptedResponse = await SecurityUtil.decryptAES(encryptedResponse);

    var jsonResponse = jsonDecode(decryptedResponse) as Map<String, dynamic>;
    if (jsonResponse.isEmpty) {
      throw Exception('获取县/区/旗列表失败！出参为空');
    }

    if (!jsonResponse.containsKey('code')) {
      throw Exception('获取县/区/旗列表失败！出参中未包含: code');
    }

    var code = jsonResponse['code'] as int;
    if (code != 0) {
      if (!jsonResponse.containsKey('message')) {
        throw Exception('获取县/区/旗列表失败！出参中未包含: message');
      }

      var message = jsonResponse['message'] as String;
      throw Exception('获取县/区/旗列表失败！$message');
    }

    if (!jsonResponse.containsKey('data')) {
      throw Exception('获取县/区/旗列表失败！出参中未包含: data');
    }

    List<Map<String, dynamic>> maps = (jsonResponse['data'] as List).cast<Map<String, dynamic>>();
    if (maps.isNotEmpty) {
      final counties = maps.map((m) => County.fromJson(m)).toList();
      return counties;
    }
    return null;
  }

  /// 获取指定县/区/旗的乡镇/街道列表
  /// param countyCode：县/区/旗代码
  /// return 乡镇/街道列表
  Future<List<Town>?> getTownsByCounty(String countyCode) async {
    if (token == null) {
      throw Exception('用户未登录或登录已过期，请重新登录！');
    }

    var encryptedResponse = ''; // await client.adminDivisions.getTownsByCounty(token!, countyCode);
    if (encryptedResponse.isEmpty) {
      throw Exception('获取乡镇/街道列表失败！响应消息为空');
    }

    var decryptedResponse = await SecurityUtil.decryptAES(encryptedResponse);

    var jsonResponse = jsonDecode(decryptedResponse) as Map<String, dynamic>;
    if (jsonResponse.isEmpty) {
      throw Exception('获取乡镇/街道列表失败！出参为空');
    }

    if (!jsonResponse.containsKey('code')) {
      throw Exception('获取乡镇/街道列表失败！出参中未包含: code');
    }

    var code = jsonResponse['code'] as int;
    if (code != 0) {
      if (!jsonResponse.containsKey('message')) {
        throw Exception('获取乡镇/街道列表失败！出参中未包含: message');
      }

      var message = jsonResponse['message'] as String;
      throw Exception('获取乡镇/街道列表失败！$message');
    }

    if (!jsonResponse.containsKey('data')) {
      throw Exception('获取乡镇/街道列表失败！出参中未包含: data');
    }

    List<Map<String, dynamic>> maps = (jsonResponse['data'] as List).cast<Map<String, dynamic>>();
    if (maps.isNotEmpty) {
      final towns = maps.map((m) => Town.fromJson(m)).toList();
      return towns;
    }
    return null;
  }

  /// 获取指定乡镇/街道的村/居委会列表
  /// param townCode：乡镇/街道代码
  /// return 村/居委会列表
  Future<List<Village>?> getVillagesByTown(String townCode) async {
    if (token == null) {
      throw Exception('用户未登录或登录已过期，请重新登录！');
    }

    var encryptedResponse = ''; // await client.adminDivisions.getVillagesByTown(token!, townCode);
    if (encryptedResponse.isEmpty) {
      throw Exception('获取村/居委会列表失败！响应消息为空');
    }

    var decryptedResponse = await SecurityUtil.decryptAES(encryptedResponse);

    var jsonResponse = jsonDecode(decryptedResponse) as Map<String, dynamic>;
    if (jsonResponse.isEmpty) {
      throw Exception('获取村/居委会列表失败！出参为空');
    }

    if (!jsonResponse.containsKey('code')) {
      throw Exception('获取村/居委会列表失败！出参中未包含: code');
    }

    var code = jsonResponse['code'] as int;
    if (code != 0) {
      if (!jsonResponse.containsKey('message')) {
        throw Exception('获取村/居委会列表失败！出参中未包含: message');
      }

      var message = jsonResponse['message'] as String;
      throw Exception('获取村/居委会列表失败！$message');
    }

    if (!jsonResponse.containsKey('data')) {
      throw Exception('获取村/居委会列表失败！出参中未包含: data');
    }

    List<Map<String, dynamic>> maps = (jsonResponse['data'] as List).cast<Map<String, dynamic>>();
    if (maps.isNotEmpty) {
      final villages = maps.map((m) => Village.fromJson(m)).toList();
      return villages;
    }
    return null;
  }
}
