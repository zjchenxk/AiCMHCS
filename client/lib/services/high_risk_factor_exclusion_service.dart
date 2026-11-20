import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 高危因素互斥规则服务：基于 BaseService 走后端
/// /api/highRiskFactorExclusion/*（自动加解密信封、携带 token）。
/// 数据按医院隔离，医院与创建人由服务端从登录会话推导，客户端无需传入。
class HighRiskFactorExclusionService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 查询登录用户所属医院的全部互斥规则。
  Future<List<BaseHighRiskFactorExclusion>> queryAll() async {
    final data = await _base.post('/api/highRiskFactorExclusion/query', const {});
    final list = data['exclusions'] as List<dynamic>? ?? const [];
    return list.map((e) => BaseHighRiskFactorExclusion.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增互斥规则。
  ///param firstRiskFactorId: 第一个高危因素 ID（必填）
  ///param secondRiskFactorId: 第二个高危因素 ID（必填）
  ///param thirdRiskFactorId: 第三个高危因素 ID（可选）
  ///returns: 新增后的互斥规则（含生成的 ID）
  Future<BaseHighRiskFactorExclusion> create({
    required String firstRiskFactorId,
    required String secondRiskFactorId,
    String? thirdRiskFactorId,
  }) async {
    final data = await _base.post('/api/highRiskFactorExclusion/add', {
      'firstRiskFactorId': firstRiskFactorId,
      'secondRiskFactorId': secondRiskFactorId,
      'thirdRiskFactorId': thirdRiskFactorId,
    });
    return BaseHighRiskFactorExclusion.fromJson(data['exclusion'] as Map<String, dynamic>);
  }

  /// 修改互斥规则。
  ///param id: 互斥规则 ID
  ///param changes: 要修改的字段集合（键为 firstRiskFactorId /
  /// secondRiskFactorId / thirdRiskFactorId，thirdRiskFactorId 为 null
  /// 表示清空第三项）
  ///returns: 修改后的互斥规则
  Future<BaseHighRiskFactorExclusion> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/highRiskFactorExclusion/update', {'id': id, ...changes});
    return BaseHighRiskFactorExclusion.fromJson(data['exclusion'] as Map<String, dynamic>);
  }

  /// 删除互斥规则。
  ///param id: 互斥规则 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/highRiskFactorExclusion/delete', {'id': id});
    return data['deleted'] as int;
  }
}
