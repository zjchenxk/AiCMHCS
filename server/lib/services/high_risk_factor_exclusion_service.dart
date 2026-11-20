import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/utils/uuid_util.dart';

/// 高危因素互斥规则业务异常：httpStatus / code / message 直接映射到
/// HTTP 响应（模式同 HighRiskFactorException）。
final class HighRiskFactorExclusionException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const HighRiskFactorExclusionException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'HighRiskFactorExclusionException($httpStatus, $code): $message';
}

/// 高危因素互斥规则管理服务：按医院隔离的列表、详情与增删改。
///
/// 经 DatabaseGateway 访问 BASE_HIGH_RISK_FACTOR_EXCLUSION。一条规则表示
/// 「这几项高危因素互斥，只能选其一」：FIRST/SECOND 必填、THIRD 可空，
/// 三个 ID 均逻辑引用 BASE_HIGH_RISK_FACTOR.ID，服务层校验其存在且属于
/// 同一医院。规则组合按**无序集合**判重（A+B 与 B+A 视为同一规则）；
/// 组合内 ID 不得重复。医院与创建人冗余列由路由层从令牌会话推导后传入
/// （不信任客户端上报）。主键为应用侧生成的 UUID v7（CHAR(36)），时间
/// 列统一 Dart 侧 formatTimestamp 生成后绑定。
class HighRiskFactorExclusionService {
  /// 构造函数：注入数据库网关。
  HighRiskFactorExclusionService(this._db);

  final DatabaseGateway _db;

  /// 可经 update 修改的字段（创建人、医院与时间列不可改）。
  static const Set<String> _editableFields = {
    'firstRiskFactorId',
    'secondRiskFactorId',
    'thirdRiskFactorId',
  };

  /// 查询指定医院的全部互斥规则（按创建顺序）。
  ///
  /// hospId 为空（用户未归属医院）时返回空列表。
  Future<List<BaseHighRiskFactorExclusion>> listByHospital(String hospId) async {
    final scope = hospId.trim();
    if (scope.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, FIRST_RISK_FACTOR_ID, SECOND_RISK_FACTOR_ID, '
      'THIRD_RISK_FACTOR_ID, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, '
      'CREATE_TIME, UPDATE_TIME FROM BASE_HIGH_RISK_FACTOR_EXCLUSION '
      'WHERE HOSP_ID = ? ORDER BY ID',
      [scope],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单条互斥规则，不存在时抛业务异常。
  Future<BaseHighRiskFactorExclusion> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, FIRST_RISK_FACTOR_ID, SECOND_RISK_FACTOR_ID, '
      'THIRD_RISK_FACTOR_ID, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, '
      'CREATE_TIME, UPDATE_TIME FROM BASE_HIGH_RISK_FACTOR_EXCLUSION '
      'WHERE ID = ?',
      [_id(id, '互斥规则ID')],
    );
    if (result.rows.isEmpty) {
      throw HighRiskFactorExclusionException(400, 40001, '互斥规则不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增互斥规则，返回新增后的对象。
  ///
  /// 第一个/第二个高危因素必填、第三个可选；三者不得重复，且均须为
  /// 本院存在的高危因素。同一医院的规则组合（无序）不可重复。
  /// hospId/hospName/creatorId/creatorName 由路由层从登录会话推导传入。
  Future<BaseHighRiskFactorExclusion> create({
    required String firstRiskFactorId,
    required String secondRiskFactorId,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
    String? thirdRiskFactorId,
  }) async {
    final first = _id(firstRiskFactorId, '第一个高危因素ID');
    final second = _id(secondRiskFactorId, '第二个高危因素ID');
    final third = _optionalId(thirdRiskFactorId, '第三个高危因素ID');
    final ids = _distinctIds(first, second, third);
    final hospIdValue = _id(hospId, '医院ID');
    final hosp = _required(hospName, '医院名称', 100);
    final creatorIdValue = _id(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', 30);

    await _ensureFactors(hospIdValue, ids);
    await _ensureCombinationUnique(hospIdValue, ids);

    final newId = newUuid();
    await _db.execute(
      'INSERT INTO BASE_HIGH_RISK_FACTOR_EXCLUSION (ID, '
      'FIRST_RISK_FACTOR_ID, SECOND_RISK_FACTOR_ID, THIRD_RISK_FACTOR_ID, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        newId,
        first,
        second,
        third,
        creatorIdValue,
        creator,
        hospIdValue,
        hosp,
        formatTimestamp(DateTime.now()),
      ],
    );
    return getById(newId);
  }

  /// 修改互斥规则（changes 为本次要更新的字段集合，键与 JSON 契约一致；
  /// thirdRiskFactorId 为 null 表示清空该列）。
  ///
  /// 修改后同样校验三者互不重复、均为本院高危因素、组合无序唯一
  /// （排除自身）。
  Future<BaseHighRiskFactorExclusion> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!_editableFields.contains(key)) {
        throw HighRiskFactorExclusionException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _id(id, '互斥规则ID');

    // 先解析目标值（未传的字段沿用当前值；third 传 null 清空）
    final first = changes.containsKey('firstRiskFactorId') ? _id(changes['firstRiskFactorId']?.toString() ?? '', '第一个高危因素ID') : current.firstRiskFactorId;
    final second = changes.containsKey('secondRiskFactorId') ? _id(changes['secondRiskFactorId']?.toString() ?? '', '第二个高危因素ID') : current.secondRiskFactorId;
    final third = changes.containsKey('thirdRiskFactorId') ? _optionalId(changes['thirdRiskFactorId']?.toString(), '第三个高危因素ID') : current.thirdRiskFactorId;
    final ids = _distinctIds(first, second, third);

    await _ensureFactors(current.hospId, ids);
    await _ensureCombinationUnique(current.hospId, ids, excludeId: idValue);

    final setters = <String>[];
    final params = <Object?>[];
    if (changes.containsKey('firstRiskFactorId')) {
      setters.add('FIRST_RISK_FACTOR_ID = ?');
      params.add(first);
    }
    if (changes.containsKey('secondRiskFactorId')) {
      setters.add('SECOND_RISK_FACTOR_ID = ?');
      params.add(second);
    }
    if (changes.containsKey('thirdRiskFactorId')) {
      setters.add('THIRD_RISK_FACTOR_ID = ?');
      params.add(third);
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE BASE_HIGH_RISK_FACTOR_EXCLUSION SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除互斥规则，返回删除行数（0 或 1）。
  Future<int> delete(String id) async {
    await getById(id);
    return _db.execute('DELETE FROM BASE_HIGH_RISK_FACTOR_EXCLUSION WHERE ID = ?', [
      _id(id, '互斥规则ID'),
    ]);
  }

  // ---------------- 内部辅助 ----------------

  /// 从数据库行解析互斥规则。
  BaseHighRiskFactorExclusion _fromRow(Map<String, String?> row) => BaseHighRiskFactorExclusion(
    id: row['ID'] ?? '',
    firstRiskFactorId: row['FIRST_RISK_FACTOR_ID'] ?? '',
    secondRiskFactorId: row['SECOND_RISK_FACTOR_ID'] ?? '',
    thirdRiskFactorId: row['THIRD_RISK_FACTOR_ID'],
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 规则内高危因素去重校验：任意两个 ID 不得相同，返回按输入序的
  /// 非空 ID 列表。
  List<String> _distinctIds(String first, String second, String? third) {
    final ids = [first, second, if (third != null) third];
    if (ids.toSet().length != ids.length) {
      throw const HighRiskFactorExclusionException(400, 40002, '互斥规则涉及的高危因素不能重复');
    }
    return ids;
  }

  /// 校验规则涉及的高危因素均存在且属于指定医院。
  Future<void> _ensureFactors(String hospId, List<String> ids) async {
    final placeholders = List.filled(ids.length, '?').join(', ');
    final result = await _db.query(
      'SELECT ID, HOSP_ID FROM BASE_HIGH_RISK_FACTOR WHERE ID IN ($placeholders)',
      ids,
    );
    final hospitalOf = {for (final row in result.rowsAsMaps) row['ID']: row['HOSP_ID']};
    for (final id in ids) {
      final factorHospId = hospitalOf[id];
      if (factorHospId == null) {
        throw HighRiskFactorExclusionException(400, 40002, '高危因素不存在：$id');
      }
      if (factorHospId != hospId) {
        throw HighRiskFactorExclusionException(400, 40002, '高危因素不属于当前医院：$id');
      }
    }
  }

  /// 校验同一医院内不存在相同组合（无序）的互斥规则。
  ///
  /// excludeId 用于修改时排除自身。规则量小（数十条量级），应用侧
  /// 逐条比较集合即可，无需在 SQL 中拼三列排序条件。
  Future<void> _ensureCombinationUnique(String hospId, List<String> ids, {String? excludeId}) async {
    final target = ids.toSet();
    final existing = await listByHospital(hospId);
    for (final rule in existing) {
      if (excludeId != null && rule.id == excludeId) continue;
      final current = rule.riskFactorIds.toSet();
      if (current.length == target.length && current.containsAll(target)) {
        throw const HighRiskFactorExclusionException(400, 40001, '该高危因素组合的互斥规则已存在');
      }
    }
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw HighRiskFactorExclusionException(400, 40002, '$label不能为空');
    }
    if (v.length > maxLength) {
      throw HighRiskFactorExclusionException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 必填 ID 校验：UUID 主键经网关以字符串取回，仅需去空格、非空。
  String _id(String id, String label) {
    final v = id.trim();
    if (v.isEmpty) {
      throw HighRiskFactorExclusionException(400, 40002, '$label不能为空');
    }
    return v;
  }

  /// 可空 ID 校验：空值归一为 null。
  String? _optionalId(String? id, String label) {
    final v = id?.trim() ?? '';
    if (v.isEmpty) return null;
    return _id(v, label);
  }
}
