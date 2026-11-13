import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 字典类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 MenuException / RoleException）。
final class DictException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const DictException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'DictException($httpStatus, $code): $message';
}

/// 数据字典管理服务：字典树列表、数据项列表与字典/数据项增删改。
///
/// 经 DatabaseGateway 访问 BASE_DICT / BASE_DICT_ITEM。BASE_DICT 按
/// PARENT_ID 自关联构成字典树，按医院隔离（HOSP_ID 匹配登录用户所属
/// 医院，由路由层从令牌会话推导后传入，不信任客户端上报，名称含中文
/// 时由达梦网关参数改写自动内联，业务层直接写参数化 SQL）。DICT_CODE
/// 同医院内唯一、ITEM_CODE 同字典内唯一均由服务层 COUNT 校验（表上
/// 不建唯一约束，与 SYS_MENU 的 ITEM_CODE 同策略）。ID 为自增主键，
/// 两库网关无 last-insert-id 通道，字典新增后按「HOSP_ID+DICT_CODE」、
/// 数据项新增后按「DICT_ID+ITEM_CODE」唯一自然键回读新行 ID。
/// IS_DEFAULT 默认项同字典内至多一项：新增即默认或设置默认时先清
/// 字典内全部默认位再置位。删除策略保守：字典存在下级字典或数据项时
/// 均阻止删除（防孤儿数据与误删），数据项直接删除。挂载（parentId）
/// 不允许经 update 调整（树形结构调整走增删）。时间列统一 Dart 侧
/// formatTimestamp 生成后绑定。
class DictService {
  /// 构造函数：注入数据库网关。
  DictService(this._db);

  final DatabaseGateway _db;

  /// 是否默认值：是。
  static const String isDefaultYes = '1';

  /// 是否默认值：否。
  static const String isDefaultNo = '0';

  /// 各字段长度上限（与表列宽对齐）。
  static const int _codeMaxLength = 10;
  static const int _nameMaxLength = 50;
  static const int _hospNameMaxLength = 100;
  static const int _creatorNameMaxLength = 30;
  static const int _itemCodeMaxLength = 50;
  static const int _itemValueMaxLength = 100;

  /// 显示顺序上限（DISPLAY_ORDER 为 SMALLINT，取非负段）。
  static const int _orderMaxValue = 32767;

  /// 可经 update 修改的字典字段（parentId 不可改，树形结构调整走增删）。
  static const Set<String> _dictEditableFields = {'dictCode', 'dictName', 'displayOrder'};

  /// 可经 updateItem 修改的数据项字段。
  static const Set<String> _itemEditableFields = {'itemCode', 'itemValue', 'displayOrder'};

  // ---------------- 字典 ----------------

  /// 查询指定医院的全部数据字典（按创建顺序），供前端构建树。
  ///
  /// hospId 为空（用户未归属医院）时返回空列表。
  Future<List<Dict>> listByHospital(String hospId) async {
    final scope = hospId.trim();
    if (scope.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, PARENT_ID, DICT_CODE, DICT_NAME, DISPLAY_ORDER, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM BASE_DICT WHERE HOSP_ID = ? ORDER BY ID',
      [_toInt(scope, '医院ID')],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个数据字典，不存在时抛业务异常。
  Future<Dict> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, PARENT_ID, DICT_CODE, DICT_NAME, DISPLAY_ORDER, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM BASE_DICT WHERE ID = ?',
      [_toInt(id, '字典ID')],
    );
    if (result.rows.isEmpty) {
      throw DictException(400, 40001, '数据字典不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增数据字典，返回新增后的对象。
  ///
  /// parentId 非空时挂上级字典下（上级必须存在且同属本院），空为顶级
  /// 字典；hospId/hospName/creatorId/creatorName 由路由层从登录会话
  /// 推导传入；校验：DICT_CODE 必填且同医院内唯一（回读新行 ID 的
  /// 自然键）、名称必填、各字段不超长、显示顺序可选。
  Future<Dict> create({
    required String dictCode,
    required String dictName,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
    String? parentId,
    String? displayOrder,
  }) async {
    final code = _required(dictCode, '字典编码', _codeMaxLength);
    final name = _required(dictName, '字典名称', _nameMaxLength);
    final hospIdValue = _toInt(hospId, '医院ID');
    final hosp = _required(hospName, '医院名称', _hospNameMaxLength);
    final creatorIdValue = _toInt(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', _creatorNameMaxLength);
    final order = _optionalInt(displayOrder);

    final parent = parentId?.trim() ?? '';
    final parentValue = parent.isEmpty ? null : await _ensureParent(parent, hospIdValue);

    await _ensureDictCodeUnique(hospIdValue, code);

    await _db.execute(
      'INSERT INTO BASE_DICT (PARENT_ID, DICT_CODE, DICT_NAME, DISPLAY_ORDER, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        parentValue,
        code,
        name,
        order,
        creatorIdValue,
        creator,
        hospIdValue,
        hosp,
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经「医院ID+字典编码」唯一自然键回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM BASE_DICT WHERE HOSP_ID = ? AND DICT_CODE = ?',
      [hospIdValue, code],
    );
    if (row.rows.isEmpty) {
      throw const DictException(500, 50000, '新增数据字典后回读失败');
    }
    return getById(row.rows.first[0]!);
  }

  /// 修改数据字典（changes 为本次要更新的字段集合，键与 JSON 契约
  /// 一致；值为 null 表示清空该列——仅可空列允许）。挂载（parentId）
  /// 不可改（树形结构调整走增删）；DICT_CODE 同医院内唯一。
  Future<Dict> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!_dictEditableFields.contains(key)) {
        throw DictException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _toInt(id, '字典ID');

    // 先解析目标值并完成唯一性校验（必填字段必须非空、可空字段 null 清空）
    final code = changes.containsKey('dictCode') ? _required(changes['dictCode']?.toString(), '字典编码', _codeMaxLength) : null;
    if (code != null) {
      await _ensureDictCodeUnique(_toInt(current.hospId, '医院ID'), code, excludeId: idValue);
    }
    final name = changes.containsKey('dictName') ? _required(changes['dictName']?.toString(), '字典名称', _nameMaxLength) : null;
    final order = changes.containsKey('displayOrder') ? _optionalInt(changes['displayOrder']?.toString()) : null;

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'dictCode':
          setters.add('DICT_CODE = ?');
          params.add(code);
        case 'dictName':
          setters.add('DICT_NAME = ?');
          params.add(name);
        case 'displayOrder':
          setters.add('DISPLAY_ORDER = ?');
          params.add(order);
      }
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE BASE_DICT SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除数据字典，返回删除行数（0 或 1）。
  ///
  /// 存在下级字典（PARENT_ID 指向自身）或已挂数据项时均阻止删除，
  /// 防止下级字典与数据项沦为孤儿数据。
  Future<int> delete(String id) async {
    await getById(id);
    final idValue = _toInt(id, '字典ID');
    final children = await _db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_DICT WHERE PARENT_ID = ?',
      [idValue],
    );
    if (int.parse(children.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw const DictException(400, 40001, '请先删除下级字典后，再删除该字典');
    }
    final items = await _db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_DICT_ITEM WHERE DICT_ID = ?',
      [idValue],
    );
    if (int.parse(items.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw const DictException(400, 40001, '该字典下存在数据项，请先删除全部数据项');
    }
    return _db.execute('DELETE FROM BASE_DICT WHERE ID = ?', [idValue]);
  }

  // ---------------- 数据项 ----------------

  /// 查询指定字典的全部数据项（按创建顺序），供前端按显示顺序排序展示。
  Future<List<DictItem>> listItems(String dictId) async {
    final result = await _db.query(
      'SELECT ID, DICT_ID, ITEM_CODE, ITEM_VALUE, DISPLAY_ORDER, IS_DEFAULT, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM BASE_DICT_ITEM WHERE DICT_ID = ? ORDER BY ID',
      [_toInt(dictId, '字典ID')],
    );
    return result.rowsAsMaps.map(_itemFromRow).toList(growable: false);
  }

  /// 按 ID 查询单个数据项，不存在时抛业务异常。
  Future<DictItem> getItemById(String id) async {
    final result = await _db.query(
      'SELECT ID, DICT_ID, ITEM_CODE, ITEM_VALUE, DISPLAY_ORDER, IS_DEFAULT, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM BASE_DICT_ITEM WHERE ID = ?',
      [_toInt(id, '数据项ID')],
    );
    if (result.rows.isEmpty) {
      throw DictException(400, 40001, '数据字典项目不存在：$id');
    }
    return _itemFromRow(result.rowsAsMaps.first);
  }

  /// 新增数据项，返回新增后的对象。
  ///
  /// 所属字典必须存在；医院冗余列（HOSP_ID/HOSP_NAME）取自所属字典
  /// 保持一致；creatorId/creatorName 由路由层从登录会话推导传入；
  /// 校验：ITEM_CODE 必填且同字典内唯一（回读新行 ID 的自然键）、
  /// 项目值必填、各字段不超长、显示顺序可选；isDefault 为「1」时
  /// 先清同字典内全部默认位（同字典至多一项默认）。
  Future<DictItem> createItem({
    required String dictId,
    required String itemCode,
    required String itemValue,
    required String isDefault,
    required String creatorId,
    required String creatorName,
    String? displayOrder,
  }) async {
    final dict = await getById(dictId);
    final dictIdValue = _toInt(dictId, '字典ID');
    final code = _required(itemCode, '项目编码', _itemCodeMaxLength);
    final value = _required(itemValue, '项目值', _itemValueMaxLength);
    final order = _optionalInt(displayOrder);
    final def = _isDefaultFlag(isDefault);
    final creatorIdValue = _toInt(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', _creatorNameMaxLength);

    await _ensureItemCodeUnique(dictIdValue, code);

    if (def == isDefaultYes) {
      await _clearDefault(dictIdValue);
    }

    await _db.execute(
      'INSERT INTO BASE_DICT_ITEM (DICT_ID, ITEM_CODE, ITEM_VALUE, DISPLAY_ORDER, '
      'IS_DEFAULT, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        dictIdValue,
        code,
        value,
        order,
        def,
        creatorIdValue,
        creator,
        _toInt(dict.hospId, '医院ID'),
        dict.hospName,
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经「字典ID+项目编码」唯一自然键回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM BASE_DICT_ITEM WHERE DICT_ID = ? AND ITEM_CODE = ?',
      [dictIdValue, code],
    );
    if (row.rows.isEmpty) {
      throw const DictException(500, 50000, '新增数据字典项目后回读失败');
    }
    return getItemById(row.rows.first[0]!);
  }

  /// 修改数据项（changes 为本次要更新的字段集合，键与 JSON 契约一致；
  /// 值为 null 表示清空该列——仅可空列允许）。默认标记不经本方法修改
  /// （走 setItemDefault 互斥置位）；ITEM_CODE 同字典内唯一。
  Future<DictItem> updateItem(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!_itemEditableFields.contains(key)) {
        throw DictException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getItemById(id);
    final idValue = _toInt(id, '数据项ID');

    // 先解析目标值并完成唯一性校验（必填字段必须非空、可空字段 null 清空）
    final code = changes.containsKey('itemCode') ? _required(changes['itemCode']?.toString(), '项目编码', _itemCodeMaxLength) : null;
    if (code != null) {
      await _ensureItemCodeUnique(_toInt(current.dictId, '字典ID'), code, excludeId: idValue);
    }
    final value = changes.containsKey('itemValue') ? _required(changes['itemValue']?.toString(), '项目值', _itemValueMaxLength) : null;
    final order = changes.containsKey('displayOrder') ? _optionalInt(changes['displayOrder']?.toString()) : null;

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'itemCode':
          setters.add('ITEM_CODE = ?');
          params.add(code);
        case 'itemValue':
          setters.add('ITEM_VALUE = ?');
          params.add(value);
        case 'displayOrder':
          setters.add('DISPLAY_ORDER = ?');
          params.add(order);
      }
    }

    if (setters.isEmpty) return getItemById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE BASE_DICT_ITEM SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getItemById(id);
  }

  /// 删除数据项，返回删除行数（0 或 1）。
  Future<int> deleteItem(String id) async {
    await getItemById(id);
    return _db.execute('DELETE FROM BASE_DICT_ITEM WHERE ID = ?', [_toInt(id, '数据项ID')]);
  }

  /// 设置数据项为所属字典的默认项，返回设置后的对象。
  ///
  /// 同字典内至多一项默认：先清字典内全部默认位，再置位目标项。
  Future<DictItem> setItemDefault(String id) async {
    final item = await getItemById(id);
    if (item.isDefault != isDefaultYes) {
      final dictIdValue = _toInt(item.dictId, '字典ID');
      final idValue = _toInt(id, '数据项ID');
      await _clearDefault(dictIdValue);
      await _db.execute(
        'UPDATE BASE_DICT_ITEM SET IS_DEFAULT = ?, UPDATE_TIME = ? WHERE ID = ?',
        [isDefaultYes, formatTimestamp(DateTime.now()), idValue],
      );
    }
    return getItemById(id);
  }

  // ---------------- 内部辅助 ----------------

  /// 清空指定字典内全部默认位（IS_DEFAULT = '0'）。
  Future<void> _clearDefault(int dictId) async {
    await _db.execute(
      'UPDATE BASE_DICT_ITEM SET IS_DEFAULT = ? WHERE DICT_ID = ?',
      [isDefaultNo, dictId],
    );
  }

  /// 从数据库行解析数据字典。
  Dict _fromRow(Map<String, String?> row) => Dict(
    id: row['ID'] ?? '',
    parentId: row['PARENT_ID'],
    dictCode: row['DICT_CODE'] ?? '',
    dictName: row['DICT_NAME'] ?? '',
    displayOrder: row['DISPLAY_ORDER'],
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 从数据库行解析数据项。
  DictItem _itemFromRow(Map<String, String?> row) => DictItem(
    id: row['ID'] ?? '',
    dictId: row['DICT_ID'] ?? '',
    itemCode: row['ITEM_CODE'] ?? '',
    itemValue: row['ITEM_VALUE'] ?? '',
    isDefault: row['IS_DEFAULT'] ?? isDefaultNo,
    displayOrder: row['DISPLAY_ORDER'],
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 校验上级字典存在且同属本院，返回其 int 形式 ID。
  Future<int> _ensureParent(String parentId, int hospId) async {
    final value = _toInt(parentId, '上级字典ID');
    final result = await _db.query(
      'SELECT ID FROM BASE_DICT WHERE ID = ? AND HOSP_ID = ?',
      [value, hospId],
    );
    if (result.rows.isEmpty) {
      throw DictException(400, 40001, '上级字典不存在：$parentId');
    }
    return value;
  }

  /// 校验字典编码同医院内唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureDictCodeUnique(int hospId, String code, {int? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM BASE_DICT WHERE HOSP_ID = ? AND DICT_CODE = ?' : 'SELECT COUNT(*) AS CNT FROM BASE_DICT WHERE HOSP_ID = ? AND DICT_CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[hospId, code] : <Object?>[hospId, code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw DictException(400, 40001, '该医院下字典编码已存在：$code');
    }
  }

  /// 校验项目编码同字典内唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureItemCodeUnique(int dictId, String code, {int? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM BASE_DICT_ITEM WHERE DICT_ID = ? AND ITEM_CODE = ?' : 'SELECT COUNT(*) AS CNT FROM BASE_DICT_ITEM WHERE DICT_ID = ? AND ITEM_CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[dictId, code] : <Object?>[dictId, code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw DictException(400, 40001, '该字典下项目编码已存在：$code');
    }
  }

  /// 是否默认值校验：限 1-是、0-否。
  String _isDefaultFlag(String? value) {
    final v = value?.trim() ?? '';
    if (v != isDefaultYes && v != isDefaultNo) {
      throw DictException(400, 40002, '是否默认值应为 1-是、0-否：$value');
    }
    return v;
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw DictException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw DictException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 可空显示顺序校验：空值归一为 null，非空时须为 0-32767 的整数
  /// （DISPLAY_ORDER 为 SMALLINT，网关列值均为字符串）。
  int? _optionalInt(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 0 || n > _orderMaxValue) {
      throw DictException(400, 40002, '显示顺序应为 0-$_orderMaxValue 的整数：$value');
    }
    return n;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw DictException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
