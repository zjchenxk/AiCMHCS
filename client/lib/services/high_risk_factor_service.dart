import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 高危因素服务：基于 BaseService 走后端 /api/highRiskFactor/*（自动
/// 加解密信封、携带 token）。数据按医院隔离，医院与创建人由服务端从
/// 登录会话推导，客户端无需传入。
class HighRiskFactorService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 查询登录用户所属医院的全部高危因素（扁平列表，前端按颜色分组、
  /// 按大类/小类组树）。
  Future<List<BaseHighRiskFactor>> queryAll() async {
    final data = await _base.post('/api/highRiskFactor/query', const {});
    final list = data['factors'] as List<dynamic>? ?? const [];
    return list.map((e) => BaseHighRiskFactor.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增高危因素。
  ///param riskFactorCode: 高危因素编码（同医院内唯一）
  ///param riskFactorName: 高危因素名称
  ///param riskFactorCategory: 大类（可选）
  ///param riskFactorSubcategory: 小类（可选）
  ///param riskColor: 高危颜色（中文五色；可选）
  ///param riskLevel: 高危等级（BASE_DICT_ITEM.ITEM_VALUE；可选）
  ///param riskScore: 高危分值（0-127；可选）
  ///returns: 新增后的高危因素（含生成的 ID）
  Future<BaseHighRiskFactor> create({
    required String riskFactorCode,
    required String riskFactorName,
    String? riskFactorCategory,
    String? riskFactorSubcategory,
    String? riskColor,
    String? riskLevel,
    String? riskScore,
  }) async {
    final data = await _base.post('/api/highRiskFactor/add', {
      'riskFactorCode': riskFactorCode,
      'riskFactorName': riskFactorName,
      'riskFactorCategory': riskFactorCategory,
      'riskFactorSubcategory': riskFactorSubcategory,
      'riskColor': riskColor,
      'riskLevel': riskLevel,
      'riskScore': riskScore,
    });
    return BaseHighRiskFactor.fromJson(data['factor'] as Map<String, dynamic>);
  }

  /// 修改高危因素。
  ///param id: 高危因素 ID
  ///param changes: 要修改的字段集合（键为 riskFactorCategory /
  /// riskFactorSubcategory / riskFactorCode / riskFactorName / riskColor /
  /// riskLevel / riskScore，值 null 表示清空可空列）
  ///returns: 修改后的高危因素
  Future<BaseHighRiskFactor> update(String id, Map<String, Object?> changes) async {
    final data = await _base.post('/api/highRiskFactor/update', {'id': id, ...changes});
    return BaseHighRiskFactor.fromJson(data['factor'] as Map<String, dynamic>);
  }

  /// 删除高危因素。
  ///param id: 高危因素 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/highRiskFactor/delete', {'id': id});
    return data['deleted'] as int;
  }
}
