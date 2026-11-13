import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 数据字典服务：基于 BaseService 走后端 /api/dict/*（自动加解密信封、
/// 携带 token）。字典按医院隔离，医院与创建人由服务端从登录会话推导，
/// 客户端无需传入。
class DictService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 查询登录用户所属医院的全部数据字典（扁平列表，前端按 parentId 组树）。
  Future<List<Dict>> queryAll() async {
    final data = await _base.post('/api/dict/query', {});
    final list = data['dicts'] as List<dynamic>? ?? const [];
    return list.map((e) => Dict.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增数据字典。
  ///param dictCode: 字典编码（同医院内唯一）
  ///param dictName: 字典名称
  ///param parentId: 上级字典 ID（null 为顶级字典）
  ///param displayOrder: 显示顺序（可选）
  ///returns: 新增后的字典（含生成的 ID）
  Future<Dict> create({
    required String dictCode,
    required String dictName,
    String? parentId,
    String? displayOrder,
  }) async {
    final data = await _base.post('/api/dict/add', {
      'dictCode': dictCode,
      'dictName': dictName,
      'parentId': parentId,
      'displayOrder': displayOrder,
    });
    return Dict.fromJson(data['dict'] as Map<String, dynamic>);
  }

  /// 修改数据字典。
  ///param id: 字典 ID
  ///param changes: 要修改的字段集合（键为 dictCode/dictName/displayOrder，
  /// 值 null 表示清空；上级字典不可改）
  ///returns: 修改后的字典
  Future<Dict> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/dict/update', {'id': id, ...changes});
    return Dict.fromJson(data['dict'] as Map<String, dynamic>);
  }

  /// 删除数据字典（存在下级字典或数据项时后端拒绝）。
  ///param id: 字典 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/dict/delete', {'id': id});
    return data['deleted'] as int;
  }

  /// 查询指定字典的全部数据项（按创建顺序，前端按显示顺序排序展示）。
  ///param dictId: 字典 ID
  Future<List<DictItem>> queryItems(String dictId) async {
    final data = await _base.post('/api/dict/itemQuery', {'dictId': dictId});
    final list = data['items'] as List<dynamic>? ?? const [];
    return list.map((e) => DictItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增数据项。
  ///param dictId: 所属字典 ID
  ///param itemCode: 项目编码（同字典内唯一）
  ///param itemValue: 项目值
  ///param displayOrder: 显示顺序（可选）
  ///param isDefault: 是否默认值（'1'-是，'0'-否；置默认时同字典原默认项自动取消）
  ///returns: 新增后的数据项（含生成的 ID）
  Future<DictItem> createItem({
    required String dictId,
    required String itemCode,
    required String itemValue,
    String? displayOrder,
    String isDefault = '0',
  }) async {
    final data = await _base.post('/api/dict/itemAdd', {
      'dictId': dictId,
      'itemCode': itemCode,
      'itemValue': itemValue,
      'displayOrder': displayOrder,
      'isDefault': isDefault,
    });
    return DictItem.fromJson(data['item'] as Map<String, dynamic>);
  }

  /// 修改数据项（默认标记不经本方法修改，走 setItemDefault）。
  ///param id: 数据项 ID
  ///param changes: 要修改的字段集合（键为 itemCode/itemValue/displayOrder，
  /// 值 null 表示清空）
  ///returns: 修改后的数据项
  Future<DictItem> updateItem(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/dict/itemUpdate', {'id': id, ...changes});
    return DictItem.fromJson(data['item'] as Map<String, dynamic>);
  }

  /// 删除数据项。
  ///param id: 数据项 ID
  ///returns: 删除的行数
  Future<int> deleteItem(String id) async {
    final data = await _base.post('/api/dict/itemDelete', {'id': id});
    return data['deleted'] as int;
  }

  /// 设置数据项为所属字典的默认项（同字典内至多一项默认）。
  ///param id: 数据项 ID
  ///returns: 设置后的数据项
  Future<DictItem> setItemDefault(String id) async {
    final data = await _base.post('/api/dict/itemSetDefault', {'id': id});
    return DictItem.fromJson(data['item'] as Map<String, dynamic>);
  }
}
