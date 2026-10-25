import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 行政区划服务：基于 BaseService 走后端 /api/admin-divisions（自动
/// 加解密信封、携带 token）。表为单表树形（约 70 万行），一律按
/// parentCode 懒加载某一级子列表，不做整表拉取。
class AdminDivisionsService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  List<AdminDivision> _parseList(Map<String, dynamic> data) {
    final list = data['divisions'] as List<dynamic>? ?? const [];
    return list.map((e) => AdminDivision.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取下一级行政区划列表
  /// param parentCode：上级行政区划代码（空为省级）
  /// return 子级行政区划列表（含 hasChildren 标记），按代码排序
  Future<List<AdminDivision>> getChildren({String? parentCode}) async {
    final parent = parentCode?.trim();
    final data = await _base.get(
      '/api/admin-divisions',
      queryParameters: parent == null || parent.isEmpty ? null : {'parentCode': parent},
    );
    return _parseList(data);
  }

  /// 获取行政区划详情与子树规模（删除前确认提示用）
  /// param code：行政区划代码
  /// return 子树行数（含自身）
  Future<int> getSubtreeCount(String code) async {
    final data = await _base.get('/api/admin-divisions/$code');
    return data['subtreeCount'] as int;
  }

  /// 新增行政区划
  /// param code：行政区划代码（2~12 位数字，主键，创建后不可变更）
  /// param name：行政区划名称
  /// param parentCode：上级行政区划代码（空为省级）
  /// return 新增后的行政区划
  Future<AdminDivision> create({required String code, required String name, String? parentCode}) async {
    final parent = parentCode?.trim();
    final data = await _base.post('/api/admin-divisions', {
      'code': code,
      'name': name,
      'parentCode': parent == null || parent.isEmpty ? null : parent,
    });
    return AdminDivision.fromJson(data['division'] as Map<String, dynamic>);
  }

  /// 修改行政区划（名称与编码均可改；改编码时后端级联更新全部下级父引用，
  /// 上级行政区划代码不允许修改，树形结构调整走增删）
  /// param code：当前行政区划代码
  /// param newCode：新行政区划代码（不传或相同表示不改）
  /// param name：新名称（不传表示不改）
  /// return 修改后的行政区划
  Future<AdminDivision> update({required String code, String? newCode, String? name}) async {
    final data = await _base.put('/api/admin-divisions/$code', {
      if (newCode != null && newCode.trim().isNotEmpty) 'code': newCode.trim(),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    });
    return AdminDivision.fromJson(data['division'] as Map<String, dynamic>);
  }

  /// 级联删除行政区划及其全部下级
  /// param code：行政区划代码
  /// return 删除的行数（含全部下级）
  Future<int> delete(String code) async {
    final data = await _base.delete('/api/admin-divisions/$code');
    return data['deleted'] as int;
  }

  /// 以下为地址级联表单（医院信息等）的便捷方法：把扁平的子级列表包装
  /// 成既有的嵌套模型（下级列表置空，选中时再逐级加载）。

  /// 获取省/自治区/直辖市列表
  /// return 省/自治区/直辖市列表
  Future<List<Province>?> getProvinces() async {
    return (await getChildren()).map((d) => Province(code: d.code, name: d.name, cities: const [])).toList();
  }

  /// 获取指定省/自治区/直辖市的市/州列表
  /// param provinceCode：省/直辖市/自治区代码
  /// return 市/州列表
  Future<List<City>?> getCitiesByProvince(String provinceCode) async {
    return (await getChildren(parentCode: provinceCode)).map((d) => City(code: d.code, name: d.name, counties: const [])).toList();
  }

  /// 获取指定市/州的县/区/旗列表
  /// param cityCode：市/州代码
  /// return 县/区/旗列表
  Future<List<County>?> getCountiesByCity(String cityCode) async {
    return (await getChildren(parentCode: cityCode)).map((d) => County(code: d.code, name: d.name, towns: const [])).toList();
  }

  /// 获取指定县/区/旗的乡镇/街道列表
  /// param countyCode：县/区/旗代码
  /// return 乡镇/街道列表
  Future<List<Town>?> getTownsByCounty(String countyCode) async {
    return (await getChildren(parentCode: countyCode)).map((d) => Town(code: d.code, name: d.name, villages: const [])).toList();
  }

  /// 获取指定乡镇/街道的村/居委会列表
  /// param townCode：乡镇/街道代码
  /// return 村/居委会列表
  Future<List<Village>?> getVillagesByTown(String townCode) async {
    return (await getChildren(parentCode: townCode)).map((d) => Village(code: d.code, name: d.name)).toList();
  }
}
