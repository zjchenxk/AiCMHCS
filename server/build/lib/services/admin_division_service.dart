import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 行政区划类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException）。
final class AdminDivisionException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const AdminDivisionException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'AdminDivisionException($httpStatus, $code): $message';
}

/// 行政区划管理服务：按层级查询、新增、改名、子树统计与级联删除。
///
/// 经 DatabaseGateway 访问 BASE_ADMIN_DIVISIONS（约 70 万行，只按
/// parentCode 走索引逐层取数，绝不整表返回）。名称含中文时由达梦网关
/// 参数改写自动内联，业务层直接写参数化 SQL。
class AdminDivisionService {
  /// 构造函数：注入数据库网关。
  AdminDivisionService(this._db);

  final DatabaseGateway _db;

  /// CODE 合法格式：2~12 位纯数字（与导入器一致；国标 6/9/12 位与
  /// 最短码 2/4/6/9 位体系均覆盖，只要父引用自洽即可建树）。
  static final RegExp _codePattern = RegExp(r'^\d{2,12}$');

  /// 名称最大长度（与表列 VARCHAR(200) 对齐）。
  static const int _nameMaxLength = 200;

  /// IN 批量查询/删除的单批参数上限（SQLite 变量上限与达梦语句长度
  /// 共同约束下的稳妥值，与导入器批大小一致）。
  static const int _batchSize = 500;

  /// 查询下一级行政区划列表（parentCode 为空取省级），按代码排序。
  ///
  /// hasChildren 经 EXISTS 子查询带出（PARENT_CODE 有索引），供树形 UI
  /// 决定是否显示展开箭头。
  Future<List<AdminDivision>> listChildren({String? parentCode}) async {
    final parent = parentCode?.trim();
    final result = await _db.query(
      'SELECT C.CODE, C.NAME, C.PARENT_CODE, '
      'CASE WHEN EXISTS (SELECT 1 FROM BASE_ADMIN_DIVISIONS C2 '
      'WHERE C2.PARENT_CODE = C.CODE) THEN 1 ELSE 0 END AS HAS_CHILDREN '
      'FROM BASE_ADMIN_DIVISIONS C '
      'WHERE C.PARENT_CODE ${parent == null || parent.isEmpty ? 'IS NULL' : '= ?'} '
      'ORDER BY C.CODE',
      parent == null || parent.isEmpty ? const [] : [parent],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按代码查询单个行政区划，不存在时抛业务异常。
  Future<AdminDivision> getByCode(String code) async {
    final result = await _db.query(
      'SELECT CODE, NAME, PARENT_CODE FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
      [code],
    );
    if (result.rows.isEmpty) {
      throw AdminDivisionException(400, 40001, '行政区划不存在：$code');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增行政区划（parentCode 为空表示省级），返回新增后的对象。
  ///
  /// 校验：CODE 为 2~12 位纯数字且不与现有重复、名称非空且不超长、
  /// 上级代码必须已存在。CODE 为主键，创建后不可变更。
  Future<AdminDivision> create({
    required String code,
    required String name,
    String? parentCode,
  }) async {
    final c = code.trim();
    final n = name.trim();
    if (c.isEmpty || !_codePattern.hasMatch(c)) {
      throw const AdminDivisionException(400, 40002, '行政区划代码应为 2~12 位数字');
    }
    if (n.isEmpty) {
      throw const AdminDivisionException(400, 40002, '行政区划名称不能为空');
    }
    if (n.length > _nameMaxLength) {
      throw const AdminDivisionException(400, 40002, '行政区划名称不能超过 $_nameMaxLength 个字符');
    }
    final parent = parentCode?.trim();
    final hasParent = parent != null && parent.isNotEmpty;
    if (hasParent) {
      if (parent == c) {
        throw const AdminDivisionException(400, 40002, '上级代码不能与自身相同');
      }
      if (parent.length >= 12) {
        throw const AdminDivisionException(400, 40002, '村/居委会为最末级，不能再添加下级行政区划');
      }
      final exists = await _db.query(
        'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
        [parent],
      );
      if (int.parse(exists.rowsAsMaps.first['CNT'] ?? '0') == 0) {
        throw AdminDivisionException(400, 40001, '上级行政区划不存在：$parent');
      }
    }
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS WHERE CODE = ?',
      [c],
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw AdminDivisionException(400, 40001, '行政区划代码已存在：$c');
    }

    final parentValue = hasParent ? parent : null;
    await _db.execute(
      'INSERT INTO BASE_ADMIN_DIVISIONS (CODE, NAME, PARENT_CODE) VALUES (?, ?, ?)',
      [c, n, parentValue],
    );
    return AdminDivision(code: c, name: n, parentCode: parentValue);
  }

  /// 修改行政区划（名称与编码均可改，编码可改但会级联更新全部下级的
  /// 父引用；上级代码不允许经此接口调整，树形结构调整走增删）。
  ///
  /// 编码变更校验：新编码格式合法且不与其他区划重复；更新顺序为先改
  /// 下级 PARENT_CODE 再改自身主键，中途失败重跑幂等。
  Future<AdminDivision> update(String oldCode, {String? newCode, String? newName}) async {
    final old = await getByCode(oldCode);

    // 编码归一：未传或与原值相同视为不变
    final normalizedCode = newCode?.trim();
    final codeChanged = normalizedCode != null && normalizedCode.isNotEmpty && normalizedCode != oldCode;
    if (codeChanged) {
      if (!_codePattern.hasMatch(normalizedCode)) {
        throw const AdminDivisionException(400, 40002, '行政区划代码应为 2~12 位数字');
      }
      final dup = await _db.query(
        'SELECT COUNT(*) AS CNT FROM BASE_ADMIN_DIVISIONS WHERE CODE = ? AND CODE <> ?',
        [normalizedCode, oldCode],
      );
      if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
        throw AdminDivisionException(400, 40001, '行政区划代码已存在：$normalizedCode');
      }
    }

    final n = newName?.trim();
    if (n != null && n.isEmpty) {
      throw const AdminDivisionException(400, 40002, '行政区划名称不能为空');
    }
    if (n != null && n.length > _nameMaxLength) {
      throw const AdminDivisionException(400, 40002, '行政区划名称不能超过 $_nameMaxLength 个字符');
    }
    if (!codeChanged && n == null) {
      return old;
    }

    if (codeChanged) {
      // 先把下级父引用指到新编码，再改自身主键
      await _db.execute(
        'UPDATE BASE_ADMIN_DIVISIONS SET PARENT_CODE = ? WHERE PARENT_CODE = ?',
        [normalizedCode, oldCode],
      );
    }
    final sets = <String>[
      if (codeChanged) 'CODE = ?',
      if (n != null) 'NAME = ?',
    ];
    final params = <Object?>[
      if (codeChanged) normalizedCode,
      if (n != null) n,
      oldCode,
    ];
    await _db.execute(
      'UPDATE BASE_ADMIN_DIVISIONS SET ${sets.join(', ')} WHERE CODE = ?',
      params,
    );
    return AdminDivision(
      code: codeChanged ? normalizedCode : old.code,
      name: n ?? old.name,
      parentCode: old.parentCode,
    );
  }

  /// 统计子树规模（含自身），供删除前确认提示。
  Future<int> subtreeCount(String code) async {
    await getByCode(code);
    return (await _collectSubtreeCodes(code)).length;
  }

  /// 级联删除行政区划及其全部下级，返回删除行数。
  ///
  /// 先逐层收集子树全部 CODE，再分批 DELETE IN；删除不存在的行无副作用，
  /// 中断后重试幂等。
  Future<int> deleteSubtree(String code) async {
    await getByCode(code);
    final codes = await _collectSubtreeCodes(code);
    var deleted = 0;
    for (var i = 0; i < codes.length; i += _batchSize) {
      final batch = codes.skip(i).take(_batchSize).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');
      deleted += await _db.execute(
        'DELETE FROM BASE_ADMIN_DIVISIONS WHERE CODE IN ($placeholders)',
        batch,
      );
    }
    return deleted;
  }

  /// 自顶向下逐层收集子树全部 CODE（含根），每层按批 IN 查询子级。
  Future<List<String>> _collectSubtreeCodes(String rootCode) async {
    final codes = <String>[rootCode];
    var start = 0;
    while (start < codes.length) {
      final batch = codes.skip(start).take(_batchSize).toList();
      start += batch.length;
      final placeholders = List.filled(batch.length, '?').join(', ');
      final result = await _db.query(
        'SELECT CODE FROM BASE_ADMIN_DIVISIONS WHERE PARENT_CODE IN ($placeholders) '
        'ORDER BY CODE',
        batch,
      );
      codes.addAll(result.rows.map((row) => row[0]!));
    }
    return codes;
  }

  /// 从数据库行解析（HAS_CHILDREN 仅列表查询携带，缺省视为无下级）。
  AdminDivision _fromRow(Map<String, String?> row) => AdminDivision(
    code: row['CODE'] ?? '',
    name: row['NAME'] ?? '',
    parentCode: row['PARENT_CODE'],
    hasChildren: row['HAS_CHILDREN'] == '1',
  );
}
