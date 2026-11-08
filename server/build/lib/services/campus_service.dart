import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 院区类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException / HospitalException）。
final class CampusException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const CampusException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'CampusException($httpStatus, $code): $message';
}

/// 院区管理服务：全量列表、新增、修改与删除。
///
/// 经 DatabaseGateway 访问 SYS_CAMPUS（HOSP_ID 关联 SYS_HOSPITAL）。
/// 院区规模有限（医院百级以内、每院院区个位数），列表接口整表返回、
/// 由前端按医院分组；名称含中文时由达梦网关参数改写自动内联，业务层
/// 直接写参数化 SQL。ID 为自增主键，两库网关无 last-insert-id 通道，
/// 新增后按唯一 CODE 回读确定新行 ID（并发下不受会话级自增值串扰）。
/// 删除医院前须先删除其下院区（见 HospitalService.deleteSubtree 的
/// 前置校验），本服务不反向约束。
class CampusService {
  /// 构造函数：注入数据库网关。
  CampusService(this._db);

  final DatabaseGateway _db;

  /// 各字段长度上限（与表列宽对齐）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 100;
  static const int _addressMaxLength = 100;
  static const int _telMaxLength = 20;

  /// 查询全部院区（按所属医院、创建顺序），供前端按医院分组展示。
  Future<List<Campus>> listAll() async {
    final result = await _db.query(
      'SELECT ID, HOSP_ID, CODE, NAME, ADDRESS, TEL FROM SYS_CAMPUS '
      'ORDER BY HOSP_ID, ID',
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个院区，不存在时抛业务异常。
  Future<Campus> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, HOSP_ID, CODE, NAME, ADDRESS, TEL FROM SYS_CAMPUS '
      'WHERE ID = ?',
      [_toInt(id, '院区ID')],
    );
    if (result.rows.isEmpty) {
      throw CampusException(400, 40001, '院区不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增院区，返回新增后的对象。
  ///
  /// 校验：所属医院必须存在、CODE 必填且全表唯一（回读新行 ID 的
  /// 自然键）、名称必填且同医院内唯一、各字段不超长。
  Future<Campus> create({
    required String hospId,
    required String code,
    required String name,
    String? address,
    String? tel,
  }) async {
    final c = _required(code, '院区代码', _codeMaxLength);
    final n = _required(name, '院区名称', _nameMaxLength);
    final hospValue = await _ensureHospital(hospId);
    await _ensureCodeUnique(c);
    await _ensureNameUnique(hospValue, n);

    await _db.execute(
      'INSERT INTO SYS_CAMPUS (HOSP_ID, CODE, NAME, ADDRESS, TEL, '
      'CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?)',
      [
        hospValue,
        c,
        n,
        _optional(address, '院区地址', _addressMaxLength),
        _optional(tel, '联系电话', _telMaxLength),
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经唯一 CODE 回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM SYS_CAMPUS WHERE CODE = ?',
      [c],
    );
    if (row.rows.isEmpty) {
      throw const CampusException(500, 50000, '新增院区后回读失败');
    }
    return getById(row.rows.first[0]!);
  }

  /// 修改院区（changes 为本次要更新的字段集合，键与 JSON 契约一致；
  /// 值为 null 表示清空该列——仅可空列允许）。hospId 可改（调整归属，
  /// 目标医院必须存在），名称判重按「目标归属 + 目标名称」统一校验；
  /// CREATE_TIME 不可改，UPDATE_TIME 由本方法统一写入。
  Future<Campus> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!{'hospId', 'code', 'name', 'address', 'tel'}.contains(key)) {
        throw CampusException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _toInt(id, '院区ID');

    // 先解析目标值并完成唯一性校验（判重按目标归属 + 目标名称）
    final hospValue = changes.containsKey('hospId') ? await _ensureHospital(changes['hospId']?.toString() ?? '') : null;
    final code = changes.containsKey('code') ? _required(changes['code']?.toString(), '院区代码', _codeMaxLength) : null;
    if (code != null) {
      await _ensureCodeUnique(code, excludeId: idValue);
    }
    final name = changes.containsKey('name') ? _required(changes['name']?.toString(), '院区名称', _nameMaxLength) : null;
    if (name != null || hospValue != null) {
      await _ensureNameUnique(
        hospValue ?? _toInt(current.hospId, '医院ID'),
        name ?? current.name,
        excludeId: idValue,
      );
    }

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'hospId':
          setters.add('HOSP_ID = ?');
          params.add(hospValue);
        case 'code':
          setters.add('CODE = ?');
          params.add(code);
        case 'name':
          setters.add('NAME = ?');
          params.add(name);
        case 'address':
          setters.add('ADDRESS = ?');
          params.add(_optional(entry.value?.toString(), '院区地址', _addressMaxLength));
        case 'tel':
          setters.add('TEL = ?');
          params.add(_optional(entry.value?.toString(), '联系电话', _telMaxLength));
      }
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE SYS_CAMPUS SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除院区，返回删除行数（0 或 1）。
  ///
  /// 院区下存在科室（SYS_DEPARTMENT.CAMPUS_ID 指向自身）时阻止删除——
  /// 须先在科室管理中删除对应科室，防止科室沦为孤儿数据。
  Future<int> delete(String id) async {
    await getById(id);
    final idValue = _toInt(id, '院区ID');
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_DEPARTMENT WHERE CAMPUS_ID = ?',
      [idValue],
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw const CampusException(400, 40001, '院区下存在科室，不能删除，请先删除科室');
    }
    return _db.execute('DELETE FROM SYS_CAMPUS WHERE ID = ?', [idValue]);
  }

  /// 从数据库行解析。
  Campus _fromRow(Map<String, String?> row) => Campus(
    id: row['ID'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    code: row['CODE'] ?? '',
    name: row['NAME'] ?? '',
    address: row['ADDRESS'],
    tel: row['TEL'],
  );

  /// 校验医院存在，返回其 int 形式 ID。
  Future<int> _ensureHospital(String hospId) async {
    final value = _toInt(hospId, '医院ID');
    final result = await _db.query(
      'SELECT ID FROM SYS_HOSPITAL WHERE ID = ?',
      [value],
    );
    if (result.rows.isEmpty) {
      throw CampusException(400, 40001, '所属医院不存在：$hospId');
    }
    return value;
  }

  /// 校验院区代码全表唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureCodeUnique(String code, {int? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE CODE = ?' : 'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[code] : <Object?>[code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw CampusException(400, 40001, '院区代码已存在：$code');
    }
  }

  /// 校验同医院内院区名称唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureNameUnique(int hospId, String name, {int? excludeId}) async {
    final sql = excludeId == null
        ? 'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE HOSP_ID = ? AND NAME = ?'
        : 'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE HOSP_ID = ? AND '
              'NAME = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[hospId, name] : <Object?>[hospId, name, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw CampusException(400, 40001, '该医院下院区名称已存在：$name');
    }
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw CampusException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw CampusException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw CampusException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
