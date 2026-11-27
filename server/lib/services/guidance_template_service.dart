import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/utils/uuid_util.dart';

/// 指导建议模板管理业务异常：httpStatus / code / message 直接映射到
/// HTTP 响应（模式同 HolidayException）。
final class GuidanceTemplateException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const GuidanceTemplateException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'GuidanceTemplateException($httpStatus, $code): $message';
}

/// 指导建议模板管理服务：模板（BASE_GUIDANCE_TEMPLATE）与模板项目
/// （BASE_GUIDANCE_TEMPLATE_ITEM）的增删改查。
///
/// 两表均按医院隔离（HOSP_ID 由路由层从令牌会话推导传入，跨院 ID 一
/// 律按不存在处理）。模板名同医院内唯一经服务层校验；显示顺序可空，
/// 列表排序非空在前按值升序、空值按创建时间续后（CASE 排序三方言通
/// 用，达梦/PostgreSQL/SQLite 对 NULL 的 ASC 缺省位置不一致）。项目经
/// TEMPLATE_ID 逻辑关联模板，GUIDANCE_TYPE 类别（可空）与 GUIDANCE
/// 内容按 UTF-8 字节数限长（内容必填，与列宽对齐）；新增项目须校验
/// 模板存在且属本院。删除模板连带删除其全部
/// 项目（先删项目再删模板）。主键为应用侧生成的 UUID v7（CHAR(36)，
/// 见 newUuid）。时间列统一 Dart 侧 formatTimestamp 生成后绑定。
class GuidanceTemplateService {
  /// 构造函数：注入数据库网关。
  GuidanceTemplateService(this._db);

  final DatabaseGateway _db;

  /// 各字段长度上限（与表列宽对齐，按 UTF-8 字节数）。
  static const int _nameMaxBytes = 50;
  static const int _typeMaxBytes = 50;
  static const int _guidanceMaxBytes = 1000;

  /// DISPLAY_ORDER 列类型 SMALLINT 的取值范围。
  static const int _displayOrderMin = -32768;
  static const int _displayOrderMax = 32767;

  /// 是否个人模板合法取值（0-否=公共，1-是=个人）。
  static const Set<String> isPersonalValues = {'0', '1'};

  /// 模板查询列清单（列表与详情共用）。
  static const String _templateColumns =
      'ID, TEMPLATE_NAME, DISPLAY_ORDER, CREATOR_ID, CREATOR_NAME, '
      'HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME';

  /// 项目查询列清单（列表与详情共用）。
  static const String _itemColumns =
      'ID, TEMPLATE_ID, GUIDANCE_TYPE, GUIDANCE, IS_PERSONAL, CREATOR_ID, '
      'CREATOR_NAME, DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, HOSP_ID, '
      'HOSP_NAME, CREATE_TIME, UPDATE_TIME';

  // ---------------- 模板：查询 ----------------

  /// 查询指定医院的全部指导建议模板（显示顺序非空在前按值升序，空值
  /// 按创建时间倒序续后）。hospId 为空（用户未归属医院）时返回空列表。
  Future<List<BaseGuidanceTemplate>> listByHospital(String hospId) async {
    final scopeHosp = _scope(hospId);
    if (scopeHosp.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT $_templateColumns FROM BASE_GUIDANCE_TEMPLATE WHERE HOSP_ID = ? '
      'ORDER BY CASE WHEN DISPLAY_ORDER IS NULL THEN 1 ELSE 0 END, '
      'DISPLAY_ORDER ASC, CREATE_TIME DESC, ID DESC',
      [scopeHosp],
    );
    return result.rowsAsMaps.map(_templateFromRow).toList(growable: false);
  }

  /// 按本院范围取模板行，不存在时抛业务异常（跨院 ID 同样落在此分支）。
  Future<Map<String, String?>> _requireTemplateRow(String id, String hospId) async {
    final result = await _db.query(
      'SELECT $_templateColumns FROM BASE_GUIDANCE_TEMPLATE WHERE ID = ? AND HOSP_ID = ?',
      [_requiredId(id, '模板ID'), _scope(hospId)],
    );
    if (result.rows.isEmpty) {
      throw GuidanceTemplateException(400, 40001, '指导建议模板不存在：$id');
    }
    return result.rowsAsMaps.first;
  }

  /// 按 ID 查询模板详情（医院隔离，跨院 ID 按不存在处理）。
  Future<BaseGuidanceTemplate> getTemplateById(String id, String hospId) async {
    return _templateFromRow(await _requireTemplateRow(id, hospId));
  }

  // ---------------- 模板：新增 / 修改 / 删除 ----------------

  /// 新增指导建议模板，返回新增后的模板。
  ///
  /// TEMPLATE_NAME 必填且同医院内唯一；DISPLAY_ORDER 可空（SMALLINT
  /// 范围）。创建人与医院冗余列由路由层从登录会话推导传入。
  Future<BaseGuidanceTemplate> createTemplate({
    required String templateName,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
    Object? displayOrder,
  }) async {
    final scopeHosp = _scope(hospId);
    final name = _requiredEnc(templateName, '模板名称', _nameMaxBytes);
    final order = _optionalDisplayOrder(displayOrder);
    await _ensureNameUnique(name, scopeHosp);

    final newId = newUuid();
    await _db.execute(
      'INSERT INTO BASE_GUIDANCE_TEMPLATE (ID, TEMPLATE_NAME, DISPLAY_ORDER, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (${List.filled(8, '?').join(', ')})',
      [
        newId,
        name,
        order,
        _required(creatorId, '创建人ID', 36),
        _required(creatorName, '创建人姓名', 30),
        scopeHosp,
        _required(hospName, '医院名称', 100),
        formatTimestamp(DateTime.now()),
      ],
    );
    return getTemplateById(newId, scopeHosp);
  }

  /// 修改指导建议模板（changes 为本次要更新的字段集合，键与 JSON 契约
  /// 一致：templateName / displayOrder；未传的字段沿用当前值），返回
  /// 修改后的模板。创建人与医院冗余列不变，仅刷新 UPDATE_TIME。
  Future<BaseGuidanceTemplate> updateTemplate(String id, Map<String, Object?> changes, String hospId) async {
    final scopeHosp = _scope(hospId);
    final current = _templateFromRow(await _requireTemplateRow(id, scopeHosp));

    // 先解析目标值（未传的字段沿用当前值），整行校验通过后再落库
    final name = changes.containsKey('templateName') ? _requiredEnc(changes['templateName']?.toString() ?? '', '模板名称', _nameMaxBytes) : current.templateName;
    final order = changes.containsKey('displayOrder') ? _optionalDisplayOrder(changes['displayOrder']) : current.displayOrder;
    if (name != current.templateName) {
      await _ensureNameUnique(name, scopeHosp, excludeId: current.id);
    }

    final setters = <String>[];
    final params = <Object?>[];
    if (changes.containsKey('templateName')) {
      setters.add('TEMPLATE_NAME = ?');
      params.add(name);
    }
    if (changes.containsKey('displayOrder')) {
      setters.add('DISPLAY_ORDER = ?');
      params.add(order);
    }
    if (setters.isEmpty) {
      return current;
    }
    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(current.id)
      ..add(scopeHosp);
    await _db.execute(
      'UPDATE BASE_GUIDANCE_TEMPLATE SET ${setters.join(', ')} WHERE ID = ? AND HOSP_ID = ?',
      params,
    );
    return getTemplateById(current.id, scopeHosp);
  }

  /// 删除指导建议模板，连带删除其全部项目（先删项目再删模板），返回
  /// 删除的模板行数（0 或 1）。
  Future<int> deleteTemplate(String id, String hospId) async {
    final scopeHosp = _scope(hospId);
    final template = await _requireTemplateRow(id, scopeHosp);
    await _db.execute(
      'DELETE FROM BASE_GUIDANCE_TEMPLATE_ITEM WHERE TEMPLATE_ID = ? AND HOSP_ID = ?',
      [template['ID'], scopeHosp],
    );
    return _db.execute(
      'DELETE FROM BASE_GUIDANCE_TEMPLATE WHERE ID = ? AND HOSP_ID = ?',
      [template['ID'], scopeHosp],
    );
  }

  /// 模板名同医院内唯一校验（excludeId 供修改时排除自身）。
  Future<void> _ensureNameUnique(String name, String hospId, {String? excludeId}) async {
    final result = await _db.query(
      excludeId == null ? 'SELECT ID FROM BASE_GUIDANCE_TEMPLATE WHERE HOSP_ID = ? AND TEMPLATE_NAME = ?' : 'SELECT ID FROM BASE_GUIDANCE_TEMPLATE WHERE HOSP_ID = ? AND TEMPLATE_NAME = ? AND ID <> ?',
      excludeId == null ? [hospId, name] : [hospId, name, excludeId],
    );
    if (result.rows.isNotEmpty) {
      throw const GuidanceTemplateException(400, 40002, '模板名称已存在');
    }
  }

  // ---------------- 项目：查询 ----------------

  /// 查询指定模板下的全部项目（公用查询：按 GUIDANCE_TYPE 类别升序排
  /// 序、空类别默认排最后——CASE 写法三方言通用，同类别内按创建时间
  /// 正序；初筛页指导建议选择与管理页项目列表共用）。
  ///
  /// 模板须存在且属本院（跨院模板 ID 按不存在处理）。
  Future<List<BaseGuidanceTemplateItem>> listItemsByTemplate(String templateId, String hospId) async {
    final scopeHosp = _scope(hospId);
    final template = await _requireTemplateRow(templateId, scopeHosp);
    final result = await _db.query(
      'SELECT $_itemColumns FROM BASE_GUIDANCE_TEMPLATE_ITEM '
      'WHERE TEMPLATE_ID = ? AND HOSP_ID = ? '
      'ORDER BY CASE WHEN GUIDANCE_TYPE IS NULL THEN 1 ELSE 0 END, '
      'GUIDANCE_TYPE ASC, CREATE_TIME ASC, ID ASC',
      [template['ID'], scopeHosp],
    );
    return result.rowsAsMaps.map(_itemFromRow).toList(growable: false);
  }

  /// 按本院范围取项目行，不存在时抛业务异常（跨院 ID 同样落在此分支）。
  Future<Map<String, String?>> _requireItemRow(String id, String hospId) async {
    final result = await _db.query(
      'SELECT $_itemColumns FROM BASE_GUIDANCE_TEMPLATE_ITEM WHERE ID = ? AND HOSP_ID = ?',
      [_requiredId(id, '项目ID'), _scope(hospId)],
    );
    if (result.rows.isEmpty) {
      throw GuidanceTemplateException(400, 40001, '指导建议项目不存在：$id');
    }
    return result.rowsAsMaps.first;
  }

  /// 按 ID 查询项目详情（医院隔离，跨院 ID 按不存在处理）。
  Future<BaseGuidanceTemplateItem> getItemById(String id, String hospId) async {
    return _itemFromRow(await _requireItemRow(id, hospId));
  }

  // ---------------- 项目：新增 / 修改 / 删除 ----------------

  /// 新增指导建议项目（挂到指定模板），返回新增后的项目。
  ///
  /// 模板须存在且属本院；GUIDANCE_TYPE 类别可空（填则按 UTF-8 字节
  /// 数限长）；GUIDANCE 必填且按 UTF-8 字节数限长；IS_PERSONAL 为
  /// 0-否/1-是。创建人与医院/科室/院区冗余列由路由层从登录会话推导
  /// 传入（科室/院区未归属时为空）。
  Future<BaseGuidanceTemplateItem> createItem({
    required String templateId,
    required String guidance,
    required String isPersonal,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
    String? guidanceType,
    String? deptId,
    String? deptName,
    String? campusId,
    String? campusName,
  }) async {
    final scopeHosp = _scope(hospId);
    final template = await _requireTemplateRow(templateId, scopeHosp);
    final type = _optionalEnc(guidanceType, '指导建议类别', _typeMaxBytes);
    final content = _requiredEnc(guidance, '指导建议', _guidanceMaxBytes);
    final personal = _requiredFlag(isPersonal);

    final newId = newUuid();
    await _db.execute(
      'INSERT INTO BASE_GUIDANCE_TEMPLATE_ITEM (ID, TEMPLATE_ID, '
      'GUIDANCE_TYPE, GUIDANCE, IS_PERSONAL, CREATOR_ID, CREATOR_NAME, '
      'DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, HOSP_ID, HOSP_NAME, '
      'CREATE_TIME) VALUES (${List.filled(14, '?').join(', ')})',
      [
        newId,
        template['ID'],
        type,
        content,
        personal,
        _required(creatorId, '创建人ID', 36),
        _required(creatorName, '创建人姓名', 30),
        _optionalId(deptId),
        _optional(deptName, '科室名称', 50),
        _optionalId(campusId),
        _optional(campusName, '院区名称', 50),
        scopeHosp,
        _required(hospName, '医院名称', 100),
        formatTimestamp(DateTime.now()),
      ],
    );
    return getItemById(newId, scopeHosp);
  }

  /// 修改指导建议项目（changes 键与 JSON 契约一致：guidanceType /
  /// guidance / isPersonal；TEMPLATE_ID 不可改），返回修改后的项目。
  /// 创建人与归属冗余列不变，仅刷新 UPDATE_TIME。
  Future<BaseGuidanceTemplateItem> updateItem(String id, Map<String, Object?> changes, String hospId) async {
    final scopeHosp = _scope(hospId);
    final current = _itemFromRow(await _requireItemRow(id, scopeHosp));

    // 先解析目标值（未传的字段沿用当前值），整行校验通过后再落库
    final type = changes.containsKey('guidanceType') ? _optionalEnc(changes['guidanceType']?.toString(), '指导建议类别', _typeMaxBytes) : current.guidanceType;
    final content = changes.containsKey('guidance') ? _requiredEnc(changes['guidance']?.toString() ?? '', '指导建议', _guidanceMaxBytes) : current.guidance;
    final personal = changes.containsKey('isPersonal') ? _requiredFlag(changes['isPersonal']?.toString() ?? '') : current.isPersonal;

    await _db.execute(
      'UPDATE BASE_GUIDANCE_TEMPLATE_ITEM SET GUIDANCE_TYPE = ?, '
      'GUIDANCE = ?, IS_PERSONAL = ?, UPDATE_TIME = ? '
      'WHERE ID = ? AND HOSP_ID = ?',
      [type, content, personal, formatTimestamp(DateTime.now()), current.id, scopeHosp],
    );
    return getItemById(current.id, scopeHosp);
  }

  /// 删除指导建议项目，返回删除行数（0 或 1）。
  Future<int> deleteItem(String id, String hospId) async {
    final scopeHosp = _scope(hospId);
    final item = await _requireItemRow(id, scopeHosp);
    return _db.execute(
      'DELETE FROM BASE_GUIDANCE_TEMPLATE_ITEM WHERE ID = ? AND HOSP_ID = ?',
      [item['ID'], scopeHosp],
    );
  }

  // ---------------- 内部辅助 ----------------

  /// 从数据库行解析模板。
  BaseGuidanceTemplate _templateFromRow(Map<String, String?> row) => BaseGuidanceTemplate(
    id: row['ID'] ?? '',
    templateName: row['TEMPLATE_NAME'] ?? '',
    displayOrder: row['DISPLAY_ORDER'] == null ? null : int.tryParse(row['DISPLAY_ORDER']!),
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 从数据库行解析模板项目。
  BaseGuidanceTemplateItem _itemFromRow(Map<String, String?> row) => BaseGuidanceTemplateItem(
    id: row['ID'] ?? '',
    templateId: row['TEMPLATE_ID'] ?? '',
    guidanceType: row['GUIDANCE_TYPE'],
    guidance: row['GUIDANCE'] ?? '',
    isPersonal: row['IS_PERSONAL'] ?? BaseGuidanceTemplateItem.personalNo,
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    deptId: row['DEPT_ID'],
    deptName: row['DEPT_NAME'],
    campusId: row['CAMPUS_ID'],
    campusName: row['CAMPUS_NAME'],
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 去空格（医院隔离统一入口，便于集中处理）。
  String _scope(String hospId) => hospId.trim();

  /// 必填文本校验（按 UTF-8 字节数校验，与达梦 VARCHAR 按字节计列宽对齐）。
  String _requiredEnc(String? value, String label, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw GuidanceTemplateException(400, 40002, '$label不能为空');
    }
    if (utf8.encode(v).length > maxBytes) {
      throw GuidanceTemplateException(400, 40002, '$label超出长度限制（$maxBytes 字节）');
    }
    return v;
  }

  /// 可空文本校验（按 UTF-8 字节数校验）：空值归一为 null，非空不超长。
  String? _optionalEnc(String? value, String label, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (utf8.encode(v).length > maxBytes) {
      throw GuidanceTemplateException(400, 40002, '$label超出长度限制（$maxBytes 字节）');
    }
    return v;
  }

  /// 必填字符串校验：去空格、非空、不超长（按字符数）。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw GuidanceTemplateException(400, 40002, '$label不能为空');
    }
    if (v.length > maxLength) {
      throw GuidanceTemplateException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw GuidanceTemplateException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 显示顺序校验：JSON 直接给 int 或字符串数字兜底；空值合法（清空
  /// 顺序），超 SMALLINT 范围报错。
  int? _optionalDisplayOrder(Object? raw) {
    if (raw == null) return null;
    if (raw is String && raw.trim().isEmpty) return null;
    final v = raw is int ? raw : int.tryParse(raw.toString());
    if (v == null) {
      throw GuidanceTemplateException(400, 40002, '显示顺序须为整数：$raw');
    }
    if (v < _displayOrderMin || v > _displayOrderMax) {
      throw GuidanceTemplateException(400, 40002, '显示顺序超出范围（$_displayOrderMin ~ $_displayOrderMax）：$v');
    }
    return v;
  }

  /// 0/1 取值校验（必填，NOT NULL 列）。
  String _requiredFlag(Object? value) {
    final v = value?.toString().trim() ?? '';
    if (!isPersonalValues.contains(v)) {
      throw GuidanceTemplateException(400, 40002, '是否个人模板取值应为 0-否或 1-是：$value');
    }
    return v;
  }

  /// 可空 ID 校验：空值归一为 null。
  String? _optionalId(String? id) {
    final v = id?.trim() ?? '';
    if (v.isEmpty) return null;
    return v;
  }

  /// 必填 ID 校验：UUID 主键经网关以字符串取回，仅需去空格、非空。
  String _requiredId(String id, String label) {
    final v = id.trim();
    if (v.isEmpty) {
      throw GuidanceTemplateException(400, 40002, '$label不能为空');
    }
    return v;
  }
}
