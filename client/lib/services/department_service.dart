import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 科室服务：基于 BaseService 走后端 /api/department/*（自动加解密信封、
/// 携带 token）。科室归属登录用户的所属医院，查询按医院 ID 过滤，
/// 列表为扁平结构、由 ViewModel 构建「医院→院区→科室」树。
class DepartmentService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 获取指定医院下的科室列表（扁平，按院区、上级、创建顺序）。
  ///param hospId: 医院 ID
  Future<List<Department>> getByHospital(String hospId) async {
    final data = await _base.post('/api/department/query', {'hospId': hospId});
    final list = data['departments'] as List<dynamic>? ?? const [];
    return list.map((e) => Department.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增科室（挂载目标三选一：parentId 挂上级科室、campusId 挂院区、
  /// 均空挂医院——医院已设置院区时须挂院区下）。
  ///param hospId: 所属医院 ID
  ///param code: 科室代码（全表唯一）
  ///param name: 科室名称（同挂载点内唯一）
  ///returns: 新增后的科室（含生成的 ID）
  Future<Department> create({
    required String hospId,
    required String code,
    required String name,
    String? campusId,
    String? parentId,
    String? address,
    String? tel,
  }) async {
    final data = await _base.post('/api/department/add', {
      'hospId': hospId,
      'code': code,
      'name': name,
      'campusId': campusId,
      'parentId': parentId,
      'address': address,
      'tel': tel,
    });
    return Department.fromJson(data['department'] as Map<String, dynamic>);
  }

  /// 修改科室。
  ///param id: 科室 ID
  ///param changes: 要修改的字段集合（键为 code/name/address/tel，值 null 表示清空）
  ///returns: 修改后的科室
  Future<Department> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/department/update', {'id': id, ...changes});
    return Department.fromJson(data['department'] as Map<String, dynamic>);
  }

  /// 删除科室。
  ///param id: 科室 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/department/delete', {'id': id});
    return data['deleted'] as int;
  }
}
