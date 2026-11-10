import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 科室类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException / CampusException）。
final class DepartmentException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const DepartmentException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'DepartmentException($httpStatus, $code): $message';
}

/// 科室管理服务：全量列表、新增、修改与删除。
///
/// 经 DatabaseGateway 访问 SYS_DEPARTMENT（HOSP_ID 关联 SYS_HOSPITAL、
/// CAMPUS_ID 可选关联 SYS_CAMPUS、PARENT_ID 自关联）。科室规模有限
/// （医院百级以内），列表接口整表返回、由前端构建「医院→院区→科室」树；
/// 名称含中文时由达梦网关参数改写自动内联，业务层直接写参数化 SQL。
/// ID 为自增主键，两库网关无 last-insert-id 通道，新增后按唯一 CODE
/// 回读确定新行 ID（并发下不受会话级自增值串扰）。
///
/// 挂载规则（服务层为准，前端入口同步约束）：医院下已设置院区时顶级
/// 科室必须挂院区下（CAMPUS_ID 非空），未设置院区时直接挂医院下；
/// 下级科室经 PARENT_ID 挂上级科室下，CAMPUS_ID 继承上级科室。归属
/// （hospId/campusId/parentId）不允许经 update 调整（树形结构调整走
/// 增删）。删除院区/医院前须先删除其下科室（见 CampusService.delete
/// 与 HospitalService.deleteSubtree 的前置校验），本服务不反向约束。
class DepartmentService {
  /// 构造函数：注入数据库网关。
  DepartmentService(this._db);

  final DatabaseGateway _db;

  /// 各字段长度上限（与表列宽对齐）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 50;
  static const int _addressMaxLength = 100;
  static const int _telMaxLength = 20;

  /// 查询全部科室（按所属院区、上级科室、创建顺序），供前端按医院
  /// 分组并构建树。
  Future<List<Department>> listAll() async {
    final result = await _db.query(
      'SELECT ID, HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, NAME, ADDRESS, TEL '
      'FROM SYS_DEPARTMENT ORDER BY CAMPUS_ID, PARENT_ID, ID',
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个科室，不存在时抛业务异常。
  Future<Department> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, NAME, ADDRESS, TEL '
      'FROM SYS_DEPARTMENT WHERE ID = ?',
      [_toInt(id, '科室ID')],
    );
    if (result.rows.isEmpty) {
      throw DepartmentException(400, 40001, '科室不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增科室，返回新增后的对象。
  ///
  /// 挂载目标三选一：parentId 非空挂上级科室下（CAMPUS_ID 继承上级，
  /// 上级必须存在且属同一医院）；parentId 空且 campusId 非空挂院区下
  /// （院区必须存在且属该医院）；均空直接挂医院下（该医院必须未设置
  /// 任何院区）。校验：CODE 必填且全表唯一（回读新行 ID 的自然键）、
  /// 名称必填且同挂载点内唯一、各字段不超长。
  Future<Department> create({required String hospId, required String code, required String name, String? campusId, String? parentId, String? address, String? tel}) async {
    final c = _required(code, '科室代码', _codeMaxLength);
    final n = _required(name, '科室名称', _nameMaxLength);
    final hospValue = await _ensureHospital(hospId);
    final parent = parentId?.trim() ?? '';
    final campus = campusId?.trim() ?? '';

    int? campusValue;
    int? parentValue;
    if (parent.isNotEmpty) {
      // 下级科室：上级必须存在且属同一医院，CAMPUS_ID 继承上级
      parentValue = _toInt(parent, '上级科室ID');
      final parentRow = await _db.query(
        'SELECT HOSP_ID, CAMPUS_ID FROM SYS_DEPARTMENT WHERE ID = ?',
        [parentValue],
      );
      if (parentRow.rows.isEmpty) {
        throw DepartmentException(400, 40001, '上级科室不存在：$parent');
      }
      final row = parentRow.rowsAsMaps.first;
      if (row['HOSP_ID'] != hospValue.toString()) {
        throw const DepartmentException(
          400,
          40001,
          '上级科室不属于该医院，不能跨医院挂载',
        );
      }
      final parentCampus = row['CAMPUS_ID'];
      campusValue = parentCampus == null || parentCampus.isEmpty ? null : int.parse(parentCampus);
    } else if (campus.isNotEmpty) {
      // 院区下的顶级科室：院区必须存在且属该医院
      final campusValueById = _toInt(campus, '院区ID');
      final campusRow = await _db.query(
        'SELECT ID FROM SYS_CAMPUS WHERE ID = ? AND HOSP_ID = ?',
        [campusValueById, hospValue],
      );
      if (campusRow.rows.isEmpty) {
        throw DepartmentException(400, 40001, '所属院区不存在：$campus');
      }
      campusValue = campusValueById;
    } else {
      // 取消下面的限制！chenxk，2026-11-10
      // 医院下的顶级科室：该医院必须未设置任何院区
      // final dup = await _db.query(
      //   'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE HOSP_ID = ?',
      //   [hospValue],
      // );
      // if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      //   throw const DepartmentException(
      //     400,
      //     40001,
      //     '该医院已设置院区，科室必须挂在院区下',
      //   );
      // }
    }

    await _ensureCodeUnique(c);
    await _ensureNameUnique(
      hospValue,
      campusValue: campusValue,
      parentId: parentValue,
      name: n,
    );

    await _db.execute(
      'INSERT INTO SYS_DEPARTMENT (HOSP_ID, CAMPUS_ID, PARENT_ID, CODE, NAME, '
      'ADDRESS, TEL, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        hospValue,
        campusValue,
        parentValue,
        c,
        n,
        _optional(address, '地址', _addressMaxLength),
        _optional(tel, '联系电话', _telMaxLength),
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经唯一 CODE 回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM SYS_DEPARTMENT WHERE CODE = ?',
      [c],
    );
    if (row.rows.isEmpty) {
      throw const DepartmentException(500, 50000, '新增科室后回读失败');
    }
    return getById(row.rows.first[0]!);
  }

  /// 修改科室（changes 为本次要更新的字段集合，键与 JSON 契约一致；
  /// 值为 null 表示清空该列——仅可空列允许）。归属（hospId/campusId/
  /// parentId）与 CREATE_TIME 不可改（树形结构调整走增删），
  /// UPDATE_TIME 由本方法统一写入。
  Future<Department> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!{'code', 'name', 'address', 'tel'}.contains(key)) {
        throw DepartmentException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _toInt(id, '科室ID');

    // 先解析目标值并完成唯一性校验（判重按当前挂载点 + 目标名称）
    final code = changes.containsKey('code') ? _required(changes['code']?.toString(), '科室代码', _codeMaxLength) : null;
    if (code != null) {
      await _ensureCodeUnique(code, excludeId: idValue);
    }
    final name = changes.containsKey('name') ? _required(changes['name']?.toString(), '科室名称', _nameMaxLength) : null;
    if (name != null) {
      await _ensureNameUnique(
        _toInt(current.hospId, '医院ID'),
        campusValue: current.campusId == null ? null : _toInt(current.campusId!, '院区ID'),
        parentId: current.parentId == null ? null : _toInt(current.parentId!, '上级科室ID'),
        name: name,
        excludeId: idValue,
      );
    }

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'code':
          setters.add('CODE = ?');
          params.add(code);
        case 'name':
          setters.add('NAME = ?');
          params.add(name);
        case 'address':
          setters.add('ADDRESS = ?');
          params.add(_optional(entry.value?.toString(), '地址', _addressMaxLength));
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
      'UPDATE SYS_DEPARTMENT SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除科室，返回删除行数（0 或 1）。
  ///
  /// 存在下级科室（PARENT_ID 指向自身）时阻止删除——须先删除下级，
  /// 防止下级科室沦为孤儿数据。
  Future<int> delete(String id) async {
    await getById(id);
    final idValue = _toInt(id, '科室ID');
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_DEPARTMENT WHERE PARENT_ID = ?',
      [idValue],
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw const DepartmentException(400, 40001, '请先删除下级科室后，再删除科室');
    }
    return _db.execute('DELETE FROM SYS_DEPARTMENT WHERE ID = ?', [idValue]);
  }

  /// 从数据库行解析。
  Department _fromRow(Map<String, String?> row) => Department(
    id: row['ID'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    campusId: row['CAMPUS_ID'],
    parentId: row['PARENT_ID'],
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
      throw DepartmentException(400, 40001, '所属医院不存在：$hospId');
    }
    return value;
  }

  /// 校验科室代码全表唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureCodeUnique(String code, {int? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM SYS_DEPARTMENT WHERE CODE = ?' : 'SELECT COUNT(*) AS CNT FROM SYS_DEPARTMENT WHERE CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[code] : <Object?>[code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw DepartmentException(400, 40001, '科室代码已存在：$code');
    }
  }

  /// 校验同挂载点内科室名称唯一：下级科室按同一上级（PARENT_ID）判重，
  /// 顶级科室按同一挂载根（同院区，或同医院且均无院区）判重
  /// （excludeId 用于修改时排除自身）。可空挂载条件的 null 匹配以
  /// IS NULL 字面量写进 SQL、不经参数绑定（两库对 null 绑定行为不一致）。
  Future<void> _ensureNameUnique(int hospId, {required int? campusValue, required int? parentId, required String name, int? excludeId}) async {
    String where;
    List<Object?> params;
    if (parentId != null) {
      where = 'PARENT_ID = ? AND NAME = ?';
      params = [parentId, name];
    } else if (campusValue != null) {
      where = 'CAMPUS_ID = ? AND PARENT_ID IS NULL AND NAME = ?';
      params = [campusValue, name];
    } else {
      where = 'HOSP_ID = ? AND CAMPUS_ID IS NULL AND PARENT_ID IS NULL AND NAME = ?';
      params = [hospId, name];
    }
    if (excludeId != null) {
      where += ' AND ID <> ?';
      params = [...params, excludeId];
    }
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_DEPARTMENT WHERE $where',
      params,
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw DepartmentException(400, 40001, '同级下科室名称已存在：$name');
    }
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw DepartmentException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw DepartmentException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw DepartmentException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
