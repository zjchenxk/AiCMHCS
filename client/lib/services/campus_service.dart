import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 院区服务：基于 BaseService 走后端 /api/campus/*（自动加解密信封、
/// 携带 token）。院区归属登录用户的所属医院，查询按医院 ID 过滤。
class CampusService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 获取指定医院下的院区列表（按创建顺序）。
  ///param hospId: 医院 ID
  Future<List<Campus>> getByHospital(String hospId) async {
    final data = await _base.post('/api/campus/query', {'hospId': hospId});
    final list = data['campuses'] as List<dynamic>? ?? const [];
    return list.map((e) => Campus.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增院区
  ///param hospId: 所属医院 ID
  ///param code: 院区代码（全表唯一）
  ///param name: 院区名称（同医院内唯一）
  ///returns: 新增后的院区（含生成的 ID）
  Future<Campus> create({
    required String hospId,
    required String code,
    required String name,
    String? address,
    String? tel,
  }) async {
    final data = await _base.post('/api/campus/add', {
      'hospId': hospId,
      'code': code,
      'name': name,
      'address': address,
      'tel': tel,
    });
    return Campus.fromJson(data['campus'] as Map<String, dynamic>);
  }

  /// 修改院区。
  ///param id: 院区 ID
  ///param changes: 要修改的字段集合（键同 add 的业务字段，值 null 表示清空）
  ///returns: 修改后的院区
  Future<Campus> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/campus/update', {'id': id, ...changes});
    return Campus.fromJson(data['campus'] as Map<String, dynamic>);
  }

  /// 删除院区。
  ///param id: 院区 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/campus/delete', {'id': id});
    return data['deleted'] as int;
  }
}
