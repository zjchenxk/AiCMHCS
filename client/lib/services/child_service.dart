import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 儿童整档：基本信息 + 扩展信息（可空）+ 监护人列表。
typedef ChildArchive = (ChildInfo, ChildExtInfo?, List<ChildGuardianInfo>);

/// 儿童建档服务：基于 BaseService 走后端 /api/child/*（自动加解密信封、
/// 携带 token）。归属医院与创建人由服务端从登录会话推导，客户端无需
/// 传入；敏感字段在 JSON 协议中为服务端解密后的明文，传输由信封保护。
class ChildService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 解析整档响应（child + ext + guardians）。
  ChildArchive _parseArchive(Map<String, dynamic> data) {
    final child = ChildInfo.fromJson(data['child'] as Map<String, dynamic>);
    final extJson = data['ext'];
    final ext = extJson is Map<String, dynamic> ? ChildExtInfo.fromJson(extJson) : null;
    final guardians = ((data['guardians'] as List<dynamic>? ?? const [])).whereType<Map<String, dynamic>>().map(ChildGuardianInfo.fromJson).toList();
    return (child, ext, guardians);
  }

  /// 按姓名（盲索引精确匹配）/就诊卡号/保健号检索本院儿童档案（至少
  /// 一个条件，返回前 20 条）。
  Future<List<ChildInfo>> search({String? name, String? visitCardNo, String? healthNo}) async {
    final data = await _base.post('/api/child/query', {
      'name': name,
      'visitCardNo': visitCardNo,
      'healthNo': healthNo,
    });
    final list = data['children'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChildInfo.fromJson).toList();
  }

  /// 装载儿童整档（基本信息 + 扩展信息 + 监护人列表）。
  Future<ChildArchive> load(String id) async {
    final data = await _base.post('/api/child/query', {'id': id});
    return _parseArchive(data);
  }

  /// 新增儿童档案（整档保存：child 必填，ext/guardians 可选），返回
  /// 入库后的整档（child 含生成的 ID）。
  Future<ChildArchive> create({
    required ChildInfo child,
    ChildExtInfo? ext,
    List<ChildGuardianInfo> guardians = const [],
  }) async {
    final data = await _base.post('/api/child/add', {
      'child': child.toJson(),
      'ext': ext?.toJson(),
      'guardians': guardians.map((g) => g.toJson()).toList(),
    });
    return _parseArchive(data);
  }

  /// 修改儿童档案（整档保存：基本信息全量更新、病人ID不可改；ext 传
  /// null 即清空扩展信息；监护人全量覆盖）。
  Future<ChildArchive> update({
    required String id,
    required ChildInfo child,
    ChildExtInfo? ext,
    List<ChildGuardianInfo> guardians = const [],
  }) async {
    final data = await _base.post('/api/child/update', {
      'id': id,
      'child': child.toJson(),
      'ext': ext?.toJson(),
      'guardians': guardians.map((g) => g.toJson()).toList(),
    });
    return _parseArchive(data);
  }

  /// 删除儿童档案（连带删除扩展信息与监护人）。
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/child/delete', {'id': id});
    return data['deleted'] as int;
  }
}
