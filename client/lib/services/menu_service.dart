import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 菜单服务：基于 BaseService 走后端 /api/menu/*（自动加解密信封、
/// 携带 token）。列表为扁平结构、由 ViewModel 按 parentId 构建
/// 「模块→菜单→操作」树。
class MenuService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 获取全部菜单项目（扁平，按上级项目、创建顺序）。
  Future<List<Menu>> queryAll() async {
    final data = await _base.post('/api/menu/query', const {});
    final list = data['menus'] as List<dynamic>? ?? const [];
    return list.map((e) => Menu.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取可见菜单项目（扁平，按上级项目、创建顺序）。
  Future<List<Menu>> queryVisible() async {
    final data = await _base.post('/api/menu/queryVisible', const {});
    final list = data['menus'] as List<dynamic>? ?? const [];
    return list.map((e) => Menu.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 查询当前登录角色已授权的操作类权限编码集合（ITEM_TYPE=3，服务端
  /// 从令牌会话推导角色），供功能页做按钮级显隐控制。
  Future<Set<String>> queryOperationCodes() async {
    final data = await _base.post('/api/menu/operations', const {});
    final list = data['operationCodes'] as List<dynamic>? ?? const [];
    return list.whereType<String>().toSet();
  }

  /// 查询单个菜单项目。
  ///param id: 菜单项目 ID
  Future<Menu> getById(String id) async {
    final data = await _base.post('/api/menu/query', {'id': id});
    return Menu.fromJson(data['menu'] as Map<String, dynamic>);
  }

  /// 新增菜单项目。
  ///param itemCode: 项目编码（全表唯一）
  ///param itemName: 项目名称
  ///param itemType: 项目类型（1-模块、2-菜单、3-操作）
  ///param parentId: 上级项目 ID（顶级项目为 null）
  ///param menuRoute: 菜单路由（类型为菜单时必填）
  ///param menuIcon: 菜单图标名
  ///returns: 新增后的菜单项目（含生成的 ID）
  Future<Menu> create({required String itemCode, required String itemName, required String itemType, required String visible, String? parentId, String? menuRoute, String? menuIcon}) async {
    final data = await _base.post('/api/menu/add', {
      'itemCode': itemCode,
      'itemName': itemName,
      'itemType': itemType,
      'parentId': parentId,
      'menuRoute': menuRoute,
      'menuIcon': menuIcon,
      'visible': visible,
    });
    return Menu.fromJson(data['menu'] as Map<String, dynamic>);
  }

  /// 修改菜单项目。
  ///param id: 菜单项目 ID
  ///param changes: 要修改的字段集合（键为 itemCode/itemName/itemType/
  /// menuRoute/menuIcon，值 null 表示清空；上级不可改）
  ///returns: 修改后的菜单项目
  Future<Menu> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/menu/update', {'id': id, ...changes});
    return Menu.fromJson(data['menu'] as Map<String, dynamic>);
  }

  /// 删除菜单项目。
  ///param id: 菜单项目 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/menu/delete', {'id': id});
    return data['deleted'] as int;
  }
}
