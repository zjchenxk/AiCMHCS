import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 医院服务：基于 BaseService 走后端 /api/hospital/*（自动加解密信封、
/// 携带 token）。医联体树形（PARENT_ID 自关联），规模有限，查询接口
/// 整表取扁平列表、由 ViewModel 建树。
class HospitalService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 获取全部医院（扁平列表，含 hasChildren 标记），按创建顺序。
  Future<List<Hospital>> getAll() async {
    final data = await _base.post('/api/hospital/query', {});
    final list = data['hospitals'] as List<dynamic>? ?? const [];
    return list.map((e) => Hospital.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取医院详情与子树规模（删除前确认提示用）。
  ///param id: 医院 ID
  ///returns: (医院详情, 子树行数含自身)
  Future<(Hospital, int)> getDetail(String id) async {
    final data = await _base.post('/api/hospital/query', {'id': id});
    return (
      Hospital.fromJson(data['hospital'] as Map<String, dynamic>),
      data['subtreeCount'] as int,
    );
  }

  /// 新增医院
  ///param parentId: 上级医院 ID（空为顶级医院）
  ///returns: 新增后的医院（含生成的 ID）
  Future<Hospital> create({
    String? parentId,
    required String code,
    required String name,
    String? nameEn,
    required String province,
    required String city,
    String? county,
    String? town,
    required String address,
    String? tel,
    String? logoBase64,
    String? sealBase64,
    String? watermarkBase64,
  }) async {
    final parent = parentId?.trim();
    final data = await _base.post('/api/hospital/add', {
      'parentId': parent == null || parent.isEmpty ? null : parent,
      'code': code,
      'name': name,
      'nameEn': nameEn,
      'province': province,
      'city': city,
      'county': county,
      'town': town,
      'address': address,
      'tel': tel,
      'logoBase64': logoBase64,
      'sealBase64': sealBase64,
      'watermarkBase64': watermarkBase64,
    });
    return Hospital.fromJson(data['hospital'] as Map<String, dynamic>);
  }

  /// 修改医院（ID 与上级医院不可改，树形结构调整走增删）。
  ///param id: 医院 ID
  ///param changes: 要修改的字段集合（键同 add 的业务字段，值 null 表示清空）
  ///returns: 修改后的医院
  Future<Hospital> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/hospital/update', {'id': id, ...changes});
    return Hospital.fromJson(data['hospital'] as Map<String, dynamic>);
  }

  /// 级联删除医院及其全部下级。
  ///param id: 医院 ID
  ///returns: 删除的行数（含全部下级）
  Future<int> delete(String id) async {
    final data = await _base.post('/api/hospital/delete', {'id': id});
    return data['deleted'] as int;
  }
}
