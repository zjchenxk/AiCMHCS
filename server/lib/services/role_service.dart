import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 角色类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException / CampusException）。
final class RoleException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const RoleException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'RoleException($httpStatus, $code): $message';
}

/// 角色管理服务：按医院列表、新增、修改、删除与菜单权限读写。
///
/// 经 DatabaseGateway 访问 SYS_ROLE（HOSP_ID 关联 SYS_HOSPITAL，角色
/// 归属登录用户所属医院，归属不可改）与 SYS_ROLE_PERMISSION（角色-
/// 菜单多对多，复合主键 ROLE_ID+MENU_ID）。ROLE_CODE / ROLE_NAME 的
/// 同医院内唯一由本层校验（表上不建唯一约束，与 SYS_MENU 的 ITEM_CODE
/// 同策略）；名称含中文时由达梦网关参数改写自动内联，业务层直接写
/// 参数化 SQL。ID 为自增主键，两库网关无 last-insert-id 通道，新增后
/// 按「HOSP_ID + ROLE_CODE」自然键回读确定新行 ID（并发下不受会话级
/// 自增值串扰）。权限保存为全量覆盖（先清后插，网关 execute 不重试、
/// 无重复写入风险）；删除角色连带清空其权限关联（当前无其他表引用
/// 角色）。网关无事务通道，清插非原子——中断重保存可自愈，不影响
/// 其他数据。
class RoleService {
  /// 构造函数：注入数据库网关。
  RoleService(this._db);

  final DatabaseGateway _db;

  /// 各字段长度上限（与表列宽对齐）。
  static const int _codeMaxLength = 10;
  static const int _nameMaxLength = 50;
  static const int _remarkMaxLength = 100;

  /// 查询指定医院下的全部角色（按创建顺序）。
  Future<List<Role>> listByHospital(String hospId) async {
    final hospValue = _toInt(hospId, '医院ID');
    final result = await _db.query(
      'SELECT ID, ROLE_CODE, ROLE_NAME, REMARK, HOSP_ID FROM SYS_ROLE '
      'WHERE HOSP_ID = ? ORDER BY ID',
      [hospValue],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个角色，不存在时抛业务异常。
  Future<Role> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, ROLE_CODE, ROLE_NAME, REMARK, HOSP_ID FROM SYS_ROLE '
      'WHERE ID = ?',
      [_toInt(id, '角色ID')],
    );
    if (result.rows.isEmpty) {
      throw RoleException(400, 40001, '角色不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增角色，返回新增后的对象。
  ///
  /// 校验：所属医院必须存在、ROLE_CODE / ROLE_NAME 必填且同医院内
  /// 唯一（回读新行 ID 的自然键）、备注可选、各字段不超长。
  Future<Role> create({
    required String hospId,
    required String roleCode,
    required String roleName,
    String? remark,
  }) async {
    final code = _required(roleCode, '角色编码', _codeMaxLength);
    final name = _required(roleName, '角色名称', _nameMaxLength);
    final hospValue = await _ensureHospital(hospId);
    await _ensureCodeUnique(hospValue, code);
    await _ensureNameUnique(hospValue, name);

    await _db.execute(
      'INSERT INTO SYS_ROLE (ROLE_CODE, ROLE_NAME, REMARK, HOSP_ID, '
      'CREATE_TIME) VALUES (?, ?, ?, ?, ?)',
      [
        code,
        name,
        _optional(remark, '备注', _remarkMaxLength),
        hospValue,
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经「医院 + 唯一编码」回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM SYS_ROLE WHERE HOSP_ID = ? AND ROLE_CODE = ?',
      [hospValue, code],
    );
    if (row.rows.isEmpty) {
      throw const RoleException(500, 50000, '新增角色后回读失败');
    }
    return getById(row.rows.first[0]!);
  }

  /// 修改角色（changes 为本次要更新的字段集合，键与 JSON 契约一致；
  /// 值为 null 表示清空该列——仅备注可空）。归属医院（hospId）不可改；
  /// CREATE_TIME 不可改，UPDATE_TIME 由本方法统一写入。
  Future<Role> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!{'roleCode', 'roleName', 'remark'}.contains(key)) {
        throw RoleException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _toInt(id, '角色ID');

    // 先解析目标值并完成唯一性校验（判重按当前归属医院）
    final hospValue = _toInt(current.hospId, '医院ID');
    final code = changes.containsKey('roleCode') ? _required(changes['roleCode']?.toString(), '角色编码', _codeMaxLength) : null;
    if (code != null) {
      await _ensureCodeUnique(hospValue, code, excludeId: idValue);
    }
    final name = changes.containsKey('roleName') ? _required(changes['roleName']?.toString(), '角色名称', _nameMaxLength) : null;
    if (name != null) {
      await _ensureNameUnique(hospValue, name, excludeId: idValue);
    }

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'roleCode':
          setters.add('ROLE_CODE = ?');
          params.add(code);
        case 'roleName':
          setters.add('ROLE_NAME = ?');
          params.add(name);
        case 'remark':
          setters.add('REMARK = ?');
          params.add(_optional(entry.value?.toString(), '备注', _remarkMaxLength));
      }
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE SYS_ROLE SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除角色，返回删除行数（0 或 1）。
  ///
  /// 连带删除该角色在 SYS_ROLE_PERMISSION 中的全部权限关联（当前无
  /// 其他表引用角色，无需前置校验）。
  Future<int> delete(String id) async {
    await getById(id);
    final idValue = _toInt(id, '角色ID');
    await _db.execute(
      'DELETE FROM SYS_ROLE_PERMISSION WHERE ROLE_ID = ?',
      [idValue],
    );
    return _db.execute('DELETE FROM SYS_ROLE WHERE ID = ?', [idValue]);
  }

  /// 查询角色已授权的菜单 ID 列表（按 MENU_ID 升序）。
  Future<List<String>> listPermissionMenuIds(String roleId) async {
    final idValue = _toInt(roleId, '角色ID');
    await getById(roleId);
    final result = await _db.query(
      'SELECT MENU_ID FROM SYS_ROLE_PERMISSION WHERE ROLE_ID = ? '
      'ORDER BY MENU_ID',
      [idValue],
    );
    return result.rows.map((row) => row[0] ?? '').where((v) => v.isNotEmpty).toList(growable: false);
  }

  /// 全量保存角色的菜单权限（menuIds 为目标全量：先清空既有关联再
  /// 逐条插入，空列表即清空权限），返回插入行数。
  ///
  /// 角色必须存在；菜单 ID 去重后逐一校验存在于 SYS_MENU（菜单管理
  /// 先删菜单后删角色的时序下不会出现悬空关联，此处仍兜底拦截）。
  Future<int> savePermissions(String roleId, List<String> menuIds) async {
    final role = await getById(roleId);
    final idValue = _toInt(role.id, '角色ID');
    final menuValues = <int>{};
    for (final menuId in menuIds) {
      menuValues.add(_toInt(menuId, '菜单ID'));
    }
    await _ensureMenusExist(menuValues.toList());

    await _db.execute(
      'DELETE FROM SYS_ROLE_PERMISSION WHERE ROLE_ID = ?',
      [idValue],
    );
    var saved = 0;
    for (final menuId in menuValues) {
      saved += await _db.execute(
        'INSERT INTO SYS_ROLE_PERMISSION (ROLE_ID, MENU_ID) VALUES (?, ?)',
        [idValue, menuId],
      );
    }
    return saved;
  }

  /// 从数据库行解析。
  Role _fromRow(Map<String, String?> row) => Role(
    id: row['ID'] ?? '',
    roleCode: row['ROLE_CODE'] ?? '',
    roleName: row['ROLE_NAME'] ?? '',
    remark: row['REMARK'],
    hospId: row['HOSP_ID'] ?? '',
  );

  /// 校验医院存在，返回其 int 形式 ID。
  Future<int> _ensureHospital(String hospId) async {
    final value = _toInt(hospId, '医院ID');
    final result = await _db.query(
      'SELECT ID FROM SYS_HOSPITAL WHERE ID = ?',
      [value],
    );
    if (result.rows.isEmpty) {
      throw RoleException(400, 40001, '所属医院不存在：$hospId');
    }
    return value;
  }

  /// 校验菜单 ID 全部存在于 SYS_MENU。
  Future<void> _ensureMenusExist(List<int> menuIds) async {
    if (menuIds.isEmpty) return;
    final placeholders = List.filled(menuIds.length, '?').join(', ');
    final result = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_MENU WHERE ID IN ($placeholders)',
      menuIds,
    );
    if (int.parse(result.rowsAsMaps.first['CNT'] ?? '0') != menuIds.length) {
      throw const RoleException(400, 40001, '存在无效的菜单项目，请刷新后重试');
    }
  }

  /// 校验同医院内角色编码唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureCodeUnique(int hospId, String code, {int? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM SYS_ROLE WHERE HOSP_ID = ? AND ROLE_CODE = ?' : 'SELECT COUNT(*) AS CNT FROM SYS_ROLE WHERE HOSP_ID = ? AND ROLE_CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[hospId, code] : <Object?>[hospId, code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw RoleException(400, 40001, '该医院下角色编码已存在：$code');
    }
  }

  /// 校验同医院内角色名称唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureNameUnique(int hospId, String name, {int? excludeId}) async {
    final sql = excludeId == null
        ? 'SELECT COUNT(*) AS CNT FROM SYS_ROLE WHERE HOSP_ID = ? AND ROLE_NAME = ?'
        : 'SELECT COUNT(*) AS CNT FROM SYS_ROLE WHERE HOSP_ID = ? AND '
              'ROLE_NAME = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[hospId, name] : <Object?>[hospId, name, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw RoleException(400, 40001, '该医院下角色名称已存在：$name');
    }
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw RoleException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw RoleException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw RoleException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
