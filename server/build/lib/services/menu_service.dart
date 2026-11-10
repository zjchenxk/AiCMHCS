import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 菜单类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException / DepartmentException）。
final class MenuException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const MenuException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'MenuException($httpStatus, $code): $message';
}

/// 菜单管理服务：全量列表、新增、修改与删除。
///
/// 经 DatabaseGateway 访问 SYS_MENU（PARENT_ID 自关联构成「模块→菜单→
/// 操作」树，不建物理外键）。菜单规模有限，列表接口整表返回、由前端
/// 组树；名称含中文时由达梦网关参数改写自动内联，业务层直接写参数化
/// SQL。ID 为自增主键，两库网关无 last-insert-id 通道，新增后按唯一
/// ITEM_CODE 回读确定新行 ID（并发下不受会话级自增值串扰）。表按需求
/// 设计不设时间列。挂载（parentId）不允许经 update 调整（树形结构
/// 调整走增删）；删除前须先删除全部下级项目。MENU_ROUTE 可选
/// （占位菜单可暂不配置路由，接入主界面路由后按需补齐）。
class MenuService {
  /// 构造函数：注入数据库网关。
  MenuService(this._db);

  final DatabaseGateway _db;

  /// 项目类型：模块。
  static const String itemTypeModule = '1';

  /// 项目类型：菜单。
  static const String itemTypeMenu = '2';

  /// 项目类型：操作。
  static const String itemTypeAction = '3';

  /// 全部合法项目类型。
  static const Set<String> itemTypes = {itemTypeModule, itemTypeMenu, itemTypeAction};

  /// 各字段长度上限（与表列宽对齐）。
  static const int _codeMaxLength = 10;
  static const int _nameMaxLength = 50;
  static const int _routeMaxLength = 100;
  static const int _iconMaxLength = 100;

  /// 可经 update 修改的字段（parentId 不可改，树形结构调整走增删）。
  static const Set<String> _editableFields = {'itemCode', 'itemName', 'itemType', 'menuRoute', 'menuIcon', 'visible'};

  /// 查询全部菜单项目（按上级项目、创建顺序），供前端构建树。
  Future<List<Menu>> listAll() async {
    final result = await _db.query(
      'SELECT ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE, MENU_ROUTE, '
      'MENU_ICON, VISIBLE FROM SYS_MENU ORDER BY PARENT_ID, ID',
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个菜单项目，不存在时抛业务异常。
  Future<Menu> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE, MENU_ROUTE, '
      'MENU_ICON, VISIBLE FROM SYS_MENU WHERE ID = ?',
      [_toInt(id, '菜单ID')],
    );
    if (result.rows.isEmpty) {
      throw MenuException(400, 40001, '菜单项目不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增菜单项目，返回新增后的对象。
  ///
  /// parentId 非空时挂上级项目下（上级必须存在），空为顶级项目；
  /// 校验：ITEM_CODE 必填且全表唯一（回读新行 ID 的自然键）、名称必填、
  /// 类型限 1-模块/2-菜单/3-操作、路由与图标可选、各字段不超长。
  Future<Menu> create({required String itemCode, required String itemName, required String itemType, required String visible, String? parentId, String? menuRoute, String? menuIcon}) async {
    final code = _required(itemCode, '项目编码', _codeMaxLength);
    final name = _required(itemName, '项目名称', _nameMaxLength);
    final type = _itemType(itemType);
    final route = _optional(menuRoute, '菜单路由', _routeMaxLength);
    final icon = _optional(menuIcon, '菜单图标', _iconMaxLength);

    final parent = parentId?.trim() ?? '';
    final parentValue = parent.isEmpty ? null : await _ensureParent(parent);

    await _ensureCodeUnique(code);

    await _db.execute(
      'INSERT INTO SYS_MENU (PARENT_ID, ITEM_CODE, ITEM_NAME, ITEM_TYPE, '
      'MENU_ROUTE, MENU_ICON, VISIBLE) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [parentValue, code, name, type, route, icon, visible],
    );
    // 自增 ID 经唯一 ITEM_CODE 回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM SYS_MENU WHERE ITEM_CODE = ?',
      [code],
    );
    if (row.rows.isEmpty) {
      throw const MenuException(500, 50000, '新增菜单项目后回读失败');
    }
    return getById(row.rows.first[0]!);
  }

  /// 修改菜单项目（changes 为本次要更新的字段集合，键与 JSON 契约
  /// 一致；值为 null 表示清空该列——仅可空列允许）。挂载（parentId）
  /// 不可改（树形结构调整走增删）；路由与图标可选。
  Future<Menu> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!_editableFields.contains(key)) {
        throw MenuException(400, 40002, '不支持的修改字段：$key');
      }
    }
    await getById(id);
    final idValue = _toInt(id, '菜单ID');

    // 先解析目标值并完成唯一性校验（必填字段必须非空、可空字段 null 清空）
    final code = changes.containsKey('itemCode') ? _required(changes['itemCode']?.toString(), '项目编码', _codeMaxLength) : null;
    if (code != null) {
      await _ensureCodeUnique(code, excludeId: idValue);
    }
    final name = changes.containsKey('itemName') ? _required(changes['itemName']?.toString(), '项目名称', _nameMaxLength) : null;
    final type = changes.containsKey('itemType') ? _itemType(changes['itemType']?.toString()) : null;
    final route = changes.containsKey('menuRoute') ? _optional(changes['menuRoute']?.toString(), '菜单路由', _routeMaxLength) : null;
    final visible = changes.containsKey('visible') ? _required(changes['visible']?.toString(), '是否显示', 1) : null;

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'itemCode':
          setters.add('ITEM_CODE = ?');
          params.add(code);
        case 'itemName':
          setters.add('ITEM_NAME = ?');
          params.add(name);
        case 'itemType':
          setters.add('ITEM_TYPE = ?');
          params.add(type);
        case 'menuRoute':
          setters.add('MENU_ROUTE = ?');
          params.add(route);
        case 'menuIcon':
          setters.add('MENU_ICON = ?');
          params.add(_optional(entry.value?.toString(), '菜单图标', _iconMaxLength));
        case 'visible':
          setters.add('VISIBLE = ?');
          params.add(visible);
      }
    }

    if (setters.isEmpty) return getById(id);

    params.add(idValue);
    await _db.execute(
      'UPDATE SYS_MENU SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除菜单项目，返回删除行数（0 或 1）。
  ///
  /// 存在下级项目（PARENT_ID 指向自身）时阻止删除——须先删除下级，
  /// 防止下级项目沦为孤儿数据。
  Future<int> delete(String id) async {
    await getById(id);
    final idValue = _toInt(id, '菜单ID');
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_MENU WHERE PARENT_ID = ?',
      [idValue],
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw const MenuException(400, 40001, '请先删除下级项目后，再删除该项目');
    }
    return _db.execute('DELETE FROM SYS_MENU WHERE ID = ?', [idValue]);
  }

  /// 从数据库行解析。
  Menu _fromRow(Map<String, String?> row) => Menu(
    id: row['ID'] ?? '',
    parentId: row['PARENT_ID'],
    itemCode: row['ITEM_CODE'] ?? '',
    itemName: row['ITEM_NAME'] ?? '',
    itemType: row['ITEM_TYPE'] ?? '',
    menuRoute: row['MENU_ROUTE'],
    menuIcon: row['MENU_ICON'],
    visible: row['VISIBLE'] ?? '1',
  );

  /// 校验上级项目存在，返回其 int 形式 ID。
  Future<int> _ensureParent(String parentId) async {
    final value = _toInt(parentId, '上级项目ID');
    final result = await _db.query(
      'SELECT ID FROM SYS_MENU WHERE ID = ?',
      [value],
    );
    if (result.rows.isEmpty) {
      throw MenuException(400, 40001, '上级项目不存在：$parentId');
    }
    return value;
  }

  /// 校验项目编码全表唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureCodeUnique(String code, {int? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM SYS_MENU WHERE ITEM_CODE = ?' : 'SELECT COUNT(*) AS CNT FROM SYS_MENU WHERE ITEM_CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[code] : <Object?>[code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw MenuException(400, 40001, '项目编码已存在：$code');
    }
  }

  /// 项目类型校验：限 1-模块、2-菜单、3-操作。
  String _itemType(String? value) {
    final v = value?.trim() ?? '';
    if (!itemTypes.contains(v)) {
      throw MenuException(400, 40002, '项目类型应为 1-模块、2-菜单、3-操作：$value');
    }
    return v;
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw MenuException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw MenuException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw MenuException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
