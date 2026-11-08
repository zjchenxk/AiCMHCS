import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 角色服务：基于 BaseService 走后端 /api/role/*（自动加解密信封、
/// 携带 token）。角色归属登录用户所属医院，本服务的医院参数由调用方
/// 传 loginUser.hospId。
class RoleService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 查询指定医院下的角色列表（按创建顺序）。
  ///param hospId: 医院 ID（登录用户所属医院）
  Future<List<Role>> getByHospital(String hospId) async {
    final data = await _base.post('/api/role/query', {'hospId': hospId});
    final list = data['roles'] as List<dynamic>? ?? const [];
    return list.map((e) => Role.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 查询单个角色。
  ///param id: 角色 ID
  Future<Role> getById(String id) async {
    final data = await _base.post('/api/role/query', {'id': id});
    return Role.fromJson(data['role'] as Map<String, dynamic>);
  }

  /// 新增角色。
  ///param hospId: 所属医院 ID（登录用户所属医院）
  ///param roleCode: 角色编码（同医院内唯一）
  ///param roleName: 角色名称（同医院内唯一）
  ///param remark: 备注
  ///returns: 新增后的角色（含生成的 ID）
  Future<Role> create({
    required String hospId,
    required String roleCode,
    required String roleName,
    String? remark,
  }) async {
    final data = await _base.post('/api/role/add', {
      'hospId': hospId,
      'roleCode': roleCode,
      'roleName': roleName,
      'remark': remark,
    });
    return Role.fromJson(data['role'] as Map<String, dynamic>);
  }

  /// 修改角色。
  ///param id: 角色 ID
  ///param changes: 要修改的字段集合（键为 roleCode/roleName/remark，
  /// 值 null 表示清空；归属医院不可改）
  ///returns: 修改后的角色
  Future<Role> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/role/update', {'id': id, ...changes});
    return Role.fromJson(data['role'] as Map<String, dynamic>);
  }

  /// 删除角色（连同其菜单权限关联一并删除）。
  ///param id: 角色 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/role/delete', {'id': id});
    return data['deleted'] as int;
  }

  /// 查询角色已授权的菜单 ID 列表。
  ///param roleId: 角色 ID
  Future<List<String>> queryPermissionMenuIds(String roleId) async {
    final data = await _base.post('/api/role/permissionQuery', {'roleId': roleId});
    final list = data['menuIds'] as List<dynamic>? ?? const [];
    return list.cast<String>();
  }

  /// 全量保存角色的菜单权限（空列表即清空权限）。
  ///param roleId: 角色 ID
  ///param menuIds: 目标全量菜单 ID 列表
  ///returns: 插入的关联行数
  Future<int> savePermissionMenuIds(String roleId, List<String> menuIds) async {
    final data = await _base.post('/api/role/permissionSave', {
      'roleId': roleId,
      'menuIds': menuIds,
    });
    return data['saved'] as int;
  }
}
