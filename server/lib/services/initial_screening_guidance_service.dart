import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/services/initial_screening_service.dart';
import 'package:server/utils/uuid_util.dart';

/// 孤独症初筛指导建议自定义模板服务：本院模板列表、新增、修改与删除。
///
/// 经 DatabaseGateway 访问 ASD_INITIAL_SCREENING_GUIDANCE 表（按医院
/// 隔离，HOSP_ID 由路由层从令牌会话推导传入）。可见性：公共模板
/// （IS_PERSONAL='0'）全院可见，个人模板（'1'）仅创建人可见——列表按
/// 「公共 OR 本人录入」过滤；修改/删除仅限创建人本人（服务层校验，
/// 他人模板一律 40001 提示）。GUIDANCE 内容按 UTF-8 字节数限长（与
/// ASD_INITIAL_SCREENING.GUIDANCE 列宽对齐）。主键为应用侧生成的
/// UUID v7（CHAR(36)，见 newUuid）。时间列统一 Dart 侧 formatTimestamp
/// 生成后绑定；异常复用 AsdException（同一初筛业务域）。
class InitialScreeningGuidanceService {
  /// 构造函数：注入数据库网关。
  InitialScreeningGuidanceService(this._db);

  final DatabaseGateway _db;

  /// 各字段长度上限（与表列宽对齐，按 UTF-8 字节数）。
  static const int _guidanceMaxBytes = 1000;
  static const int _typeMaxBytes = 50;

  /// 是否个人模板合法取值（0-否=公共，1-是=个人）。
  static const Set<String> isPersonalValues = {'0', '1'};

  // ---------------- 查询 ----------------

  /// 查询本院可见的指导建议模板（公共模板 + 本人个人模板，按创建时间
  /// 倒序；hospId 为空返回空列表）。
  Future<List<GuidanceTemplate>> listByHospital(String hospId, String operatorId) async {
    final scope = hospId.trim();
    final operator = operatorId.trim();
    if (scope.isEmpty || operator.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, GUIDANCE, GUIDANCE_TYPE, IS_PERSONAL, CREATOR_ID, '
      'CREATOR_NAME, DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, HOSP_ID, '
      'HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      "FROM ASD_INITIAL_SCREENING_GUIDANCE WHERE HOSP_ID = ? AND "
      "(IS_PERSONAL = '0' OR CREATOR_ID = ?) ORDER BY CREATE_TIME DESC, ID DESC",
      [scope, operator],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  // ---------------- 新增 / 修改 / 删除 ----------------

  /// 新增指导建议模板（创建人与医院/科室/院区归属从登录会话推导），
  /// 返回新增后的模板。
  Future<GuidanceTemplate> create({
    required String guidance,
    required String guidanceType,
    required String isPersonal,
    required String operatorId,
    required String operatorName,
    required String hospId,
    required String hospName,
    String? deptId,
    String? deptName,
    String? campusId,
    String? campusName,
  }) async {
    final content = _requiredEnc(guidance, '指导建议', _guidanceMaxBytes);
    final type = _requiredEnc(guidanceType, '指导建议类别', _typeMaxBytes);
    final personal = _optionalFlag(isPersonal);
    final newId = newUuid();
    await _db.execute(
      'INSERT INTO ASD_INITIAL_SCREENING_GUIDANCE (ID, GUIDANCE, '
      'GUIDANCE_TYPE, IS_PERSONAL, CREATOR_ID, CREATOR_NAME, DEPT_ID, '
      'DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (${List.filled(13, '?').join(', ')})',
      [
        newId,
        content,
        type,
        personal,
        _required(operatorId, '创建人ID', 36),
        _required(operatorName, '创建人姓名', 30),
        _optionalId(deptId),
        _optional(deptName, '科室名称', 50),
        _optionalId(campusId),
        _optional(campusName, '院区名称', 50),
        _required(hospId, '医院ID', 36),
        _required(hospName, '医院名称', 100),
        formatTimestamp(DateTime.now()),
      ],
    );
    return _getById(newId, _required(hospId, '医院ID', 36));
  }

  /// 修改指导建议模板（仅限创建人本人），返回修改后的模板。
  Future<GuidanceTemplate> update({
    required String id,
    required String guidance,
    required String guidanceType,
    required String isPersonal,
    required String operatorId,
    required String hospId,
  }) async {
    final scope = _required(hospId, '医院ID', 36);
    final row = await _requireOwn(id, operatorId.trim(), scope);
    final content = _requiredEnc(guidance, '指导建议', _guidanceMaxBytes);
    final type = _requiredEnc(guidanceType, '指导建议类别', _typeMaxBytes);
    final personal = _optionalFlag(isPersonal);
    await _db.execute(
      'UPDATE ASD_INITIAL_SCREENING_GUIDANCE SET GUIDANCE = ?, '
      'GUIDANCE_TYPE = ?, IS_PERSONAL = ?, UPDATE_TIME = ? '
      'WHERE ID = ? AND HOSP_ID = ?',
      [content, type, personal, formatTimestamp(DateTime.now()), row['ID'], scope],
    );
    return _getById(id.trim(), scope);
  }

  /// 删除指导建议模板（仅限创建人本人），返回删除行数（0 或 1）。
  Future<int> delete(String id, String operatorId, String hospId) async {
    final scope = _required(hospId, '医院ID', 36);
    final row = await _requireOwn(id, operatorId.trim(), scope);
    return _db.execute(
      'DELETE FROM ASD_INITIAL_SCREENING_GUIDANCE WHERE ID = ? AND HOSP_ID = ?',
      [row['ID'], scope],
    );
  }

  // ---------------- 内部辅助 ----------------

  /// 校验模板存在且属本院，且创建人为当前登录用户（他人模板统一 40001
  /// 提示，不区分「不存在」与「非本人」），返回行数据。
  Future<Map<String, String?>> _requireOwn(String id, String operatorId, String hospId) async {
    final idValue = _required(id, '模板ID', 36);
    final result = await _db.query(
      'SELECT ID, CREATOR_ID FROM ASD_INITIAL_SCREENING_GUIDANCE WHERE ID = ? AND HOSP_ID = ?',
      [idValue, hospId],
    );
    if (result.rows.isEmpty) {
      throw const AsdException(400, 40001, '指导建议模板不存在');
    }
    final row = result.rowsAsMaps.first;
    if ((row['CREATOR_ID'] ?? '') != operatorId) {
      throw const AsdException(400, 40001, '不能修改他人的指导建议');
    }
    return row;
  }

  /// 按本院范围取模板行，不存在时抛业务异常。
  Future<GuidanceTemplate> _getById(String id, String hospId) async {
    final result = await _db.query(
      'SELECT ID, GUIDANCE, GUIDANCE_TYPE, IS_PERSONAL, CREATOR_ID, '
      'CREATOR_NAME, DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, HOSP_ID, '
      'HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM ASD_INITIAL_SCREENING_GUIDANCE WHERE ID = ? AND HOSP_ID = ?',
      [id, hospId],
    );
    if (result.rows.isEmpty) {
      throw AsdException(400, 40001, '指导建议模板不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 从数据库行解析模板。
  GuidanceTemplate _fromRow(Map<String, String?> row) => GuidanceTemplate(
    id: row['ID'] ?? '',
    guidance: row['GUIDANCE'] ?? '',
    guidanceType: row['GUIDANCE_TYPE'] ?? '',
    isPersonal: row['IS_PERSONAL'] ?? '0',
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

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw AsdException(400, 40002, '$label不能为空');
    }
    return _optional(v, label, maxLength)!;
  }

  /// 必填文本校验（按 UTF-8 字节数校验，与达梦 VARCHAR 按字节计列宽对齐）。
  String _requiredEnc(String? value, String label, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw AsdException(400, 40002, '$label不能为空');
    }
    if (utf8.encode(v).length > maxBytes) {
      throw AsdException(400, 40002, '$label超出长度限制（$maxBytes 字节）');
    }
    return v;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw AsdException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 0/1 取值校验。
  String _optionalFlag(String? value) {
    final v = value?.trim() ?? '';
    if (!isPersonalValues.contains(v)) {
      throw AsdException(400, 40002, '是否个人模板取值应为 0-否或 1-是：$value');
    }
    return v;
  }

  /// 可空 ID 校验：空值归一为 null。
  String? _optionalId(String? id) {
    final v = id?.trim() ?? '';
    if (v.isEmpty) return null;
    return v;
  }
}
