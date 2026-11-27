import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 指导建议模板服务：基于 BaseService 走后端 /api/guidanceTemplate/*
/// （自动加解密信封、携带 token）。数据按医院隔离，医院与创建人及科
/// 室/院区归属由服务端从登录会话推导，客户端无需传入。模板名同医院
/// 内唯一、GUIDANCE 内容按 UTF-8 字节数限长均由服务端兜底校验。
class GuidanceTemplateService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  // ---------------- 模板 ----------------

  /// 查询登录用户所属医院的全部指导建议模板（显示顺序非空在前按值升
  /// 序，空值按创建时间续后）。
  Future<List<BaseGuidanceTemplate>> queryTemplates() async {
    final data = await _base.post('/api/guidanceTemplate/query', const {});
    final list = data['templates'] as List<dynamic>? ?? const [];
    return list.map((e) => BaseGuidanceTemplate.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 按 ID 查询模板详情。
  ///param id: 模板 ID
  Future<BaseGuidanceTemplate> queryTemplate(String id) async {
    final data = await _base.post('/api/guidanceTemplate/query', {'id': id});
    return BaseGuidanceTemplate.fromJson(data['template'] as Map<String, dynamic>);
  }

  /// 新增指导建议模板，返回新增后的模板（含服务端生成的主键）。
  ///param templateName: 模板名称（必填，同医院内唯一）
  ///param displayOrder: 显示顺序（可空，小值在前）
  Future<BaseGuidanceTemplate> createTemplate({required String templateName, int? displayOrder}) async {
    final data = await _base.post('/api/guidanceTemplate/add', {
      'templateName': templateName,
      'displayOrder': displayOrder,
    });
    return BaseGuidanceTemplate.fromJson(data['template'] as Map<String, dynamic>);
  }

  /// 修改指导建议模板。
  ///param id: 模板 ID
  ///param changes: 要修改的字段集合（键为 templateName / displayOrder，
  /// 仅传本次要修改的字段）
  Future<void> updateTemplate(String id, Map<String, Object?> changes) async {
    await _base.post('/api/guidanceTemplate/update', {'id': id, ...changes});
  }

  /// 删除指导建议模板（服务端连带删除其全部项目）。
  ///param id: 模板 ID
  ///returns: 删除的模板行数
  Future<int> deleteTemplate(String id) async {
    final data = await _base.post('/api/guidanceTemplate/delete', {'id': id});
    return data['deleted'] as int;
  }

  // ---------------- 模板项目 ----------------

  /// 查询指定模板下的全部项目（按创建时间正序，先录入的在前）。
  ///param templateId: 模板 ID
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
