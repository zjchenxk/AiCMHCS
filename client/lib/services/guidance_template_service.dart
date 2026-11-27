import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 指导建议模板服务：基于 BaseService 走后端 /api/guidanceTemplate/*
/// （自动加解密信封、携带 token）。数据按医院隔离，医院与创建人及科
/// 室/院区归属由服务端从登录会话推导，客户端无需传入。
///
/// 模板列表为只读数据源（新增/修改/删除操作已于 2026-11-27 取消，模
/// 板由运维侧按医院录入）；模板项目按 [defaultTemplateId]（初筛页指
/// 导建议选择的默认模板）或管理页选中的模板 ID 查询——itemQuery 即
/// 公用查询方法（服务端按 GUIDANCE_TYPE 类别升序、空类别排最后）。
class GuidanceTemplateService {
  /// 初筛页指导建议选择的默认指导建议模板 ID（需求 2026-11-27 指定）。
  static const String defaultTemplateId = '01a21bb5-b4df-7000-bb50-bbb3c24a025d';

  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 查询登录用户所属医院的全部指导建议模板（显示顺序非空在前按值升
  /// 序，空值按创建时间续后）。
  Future<List<BaseGuidanceTemplate>> queryTemplates() async {
    final data = await _base.post('/api/guidanceTemplate/query', const {});
    final list = data['templates'] as List<dynamic>? ?? const [];
    return list.map((e) => BaseGuidanceTemplate.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 查询指定模板下的全部项目（公用查询：按指导建议类别升序、空类别
  /// 排最后，同类别内按创建时间正序）。
  ///param templateId: 指导建议模板 ID（初筛页传 [defaultTemplateId]）
  Future<List<BaseGuidanceTemplateItem>> queryItems(String templateId) async {
    final data = await _base.post('/api/guidanceTemplate/itemQuery', {'templateId': templateId});
    final list = data['items'] as List<dynamic>? ?? const [];
    return list.map((e) => BaseGuidanceTemplateItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增指导建议项目，返回新增后的项目（含服务端生成的主键）。
  ///param templateId: 所属模板 ID
  ///param guidanceType: 指导建议类别（可空）
  ///param guidance: 指导建议内容（必填，1000 字节限长）
  ///param isPersonal: 是否个人模板（'0'-否 / '1'-是）
  Future<BaseGuidanceTemplateItem> createItem({
    required String templateId,
    String? guidanceType,
    required String guidance,
    required String isPersonal,
  }) async {
    final data = await _base.post('/api/guidanceTemplate/itemAdd', {
      'templateId': templateId,
      'guidanceType': guidanceType,
      'guidance': guidance,
      'isPersonal': isPersonal,
    });
    return BaseGuidanceTemplateItem.fromJson(data['item'] as Map<String, dynamic>);
  }

  /// 修改指导建议项目。
  ///param id: 项目 ID
  ///param changes: 要修改的字段集合（键为 guidanceType / guidance /
  /// isPersonal，仅传本次要修改的字段）
  Future<void> updateItem(String id, Map<String, Object?> changes) async {
    await _base.post('/api/guidanceTemplate/itemUpdate', {'id': id, ...changes});
  }

  /// 删除指导建议项目。
  ///param id: 项目 ID
  ///returns: 删除的行数
  Future<int> deleteItem(String id) async {
    final data = await _base.post('/api/guidanceTemplate/itemDelete', {'id': id});
    return data['deleted'] as int;
  }
}
