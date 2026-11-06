import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 医院类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 AuthException / AdminDivisionException）。
final class HospitalException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const HospitalException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'HospitalException($httpStatus, $code): $message';
}

/// 医院管理服务：全量列表、详情、新增、修改、子树统计与级联删除。
///
/// 经 DatabaseGateway 访问 SYS_HOSPITAL（医联体树形，PARENT_ID 自关联）。
/// 医院规模有限（百级以内），列表接口整表返回、由前端建树；名称含中文
/// 时由达梦网关参数改写自动内联，业务层直接写参数化 SQL。ID 为自增主键，
/// 两库网关无 last-insert-id 通道，新增后按唯一 CODE 回读确定新行 ID
/// （并发下不受会话级自增值串扰）。
class HospitalService {
  /// 构造函数：注入数据库网关。
  HospitalService(this._db);

  final DatabaseGateway _db;

  /// 各字段长度上限（与表列宽对齐）。
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 100;
  static const int _addressPartMaxLength = 50;
  static const int _addressMaxLength = 100;
  static const int _telMaxLength = 20;

  /// IN 批量查询/删除的单批参数上限（与行政区划服务一致）。
  static const int _batchSize = 500;

  /// 查询全部医院（扁平列表，按创建顺序），供前端构建医联体树。
  ///
  /// hasChildren 经 EXISTS 子查询带出，供树形 UI 决定是否显示展开箭头。
  Future<List<Hospital>> listAll() async {
    final result = await _db.query(
      'SELECT H.ID, H.PARENT_ID, H.CODE, H.NAME, H.NAME_EN, H.PROVINCE, '
      'H.CITY, H.COUNTY, H.TOWN, H.ADDRESS, H.TEL, H.LOGO_IMAGE, '
      'H.SEAL_IMAGE, H.WATERMARK_IMAGE, '
      'CASE WHEN EXISTS (SELECT 1 FROM SYS_HOSPITAL H2 '
      'WHERE H2.PARENT_ID = H.ID) THEN 1 ELSE 0 END AS HAS_CHILDREN '
      'FROM SYS_HOSPITAL H ORDER BY H.ID',
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个医院，不存在时抛业务异常。
  Future<Hospital> getById(String id) async {
    final result = await _db.query(_detailSql + ' WHERE H.ID = ?', [_toInt(id)]);
    if (result.rows.isEmpty) {
      throw HospitalException(400, 40001, '医院不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增医院（parentId 为空表示顶级），返回新增后的对象。
  ///
  /// 校验：CODE 必填且不与现有重复（回读新行 ID 的自然键）、名称/省/市/
  /// 详细地址必填、各字段不超长、上级医院必须存在。
  Future<Hospital> create({
    String? parentId,
    required String code,
    required String name,
    String? nameEn,
    required String province,
    required String city,
    String? county,
    String? town,
    required String address,
    String? tel,
    String? logoBase64,
    String? sealBase64,
    String? watermarkBase64,
  }) async {
    final c = _required(code, '组织机构代码', _codeMaxLength);
    final n = _required(name, '医院名称', _nameMaxLength);
    final p = _required(province, '省份', _addressPartMaxLength);
    final cityV = _required(city, '城市', _addressPartMaxLength);
    final addr = _required(address, '详细地址', _addressMaxLength);

    int? parentValue;
    final parent = parentId?.trim();
    if (parent != null && parent.isNotEmpty) {
      await getById(parent);
      parentValue = _toInt(parent);
    }
    final dup = await _db.query(
      'SELECT COUNT(*) AS CNT FROM SYS_HOSPITAL WHERE CODE = ?',
      [c],
    );
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw HospitalException(400, 40001, '组织机构代码已存在：$c');
    }

    await _db.execute(
      'INSERT INTO SYS_HOSPITAL (PARENT_ID, CODE, NAME, NAME_EN, PROVINCE, '
      'CITY, COUNTY, TOWN, ADDRESS, TEL, LOGO_IMAGE, SEAL_IMAGE, '
      'WATERMARK_IMAGE, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        parentValue,
        c,
        n,
        _optional(nameEn, '医院英文名称', _nameMaxLength),
        p,
        cityV,
        _optional(county, '区县', _addressPartMaxLength),
        _optional(town, '乡镇/街道', _addressPartMaxLength),
        addr,
        _optional(tel, '联系电话', _telMaxLength),
        logoBase64,
        sealBase64,
        watermarkBase64,
        formatTimestamp(DateTime.now()),
      ],
    );
    // 自增 ID 经唯一 CODE 回读（网关无 last-insert-id 通道）
    final row = await _db.query(
      'SELECT ID FROM SYS_HOSPITAL WHERE CODE = ?',
      [c],
    );
    if (row.rows.isEmpty) {
      throw const HospitalException(500, 50000, '新增医院后回读失败');
    }
    return getById(row.rows.first[0]!);
  }

  /// 修改医院（changes 为本次要更新的字段集合，键与 JSON 契约一致；
  /// 值为 null 表示清空该列——仅可空列允许）。上级医院、ID 不允许经此
  /// 接口调整（树形结构调整走增删），CREATE_TIME 不可改，UPDATE_TIME
  /// 由本方法统一写入。
  Future<Hospital> update(String id, Map<String, Object?> changes) async {
    await getById(id);

    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'code':
          final v = _required(value?.toString(), '组织机构代码', _codeMaxLength);
          final dup = await _db.query(
            'SELECT COUNT(*) AS CNT FROM SYS_HOSPITAL WHERE CODE = ? AND ID <> ?',
            [v, _toInt(id)],
          );
          if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
            throw HospitalException(400, 40001, '组织机构代码已存在：$v');
          }
          setters.add('CODE = ?');
          params.add(v);
        case 'name':
          setters.add('NAME = ?');
          params.add(_required(value?.toString(), '医院名称', _nameMaxLength));
        case 'nameEn':
          setters.add('NAME_EN = ?');
          params.add(_optional(value?.toString(), '医院英文名称', _nameMaxLength));
        case 'province':
          setters.add('PROVINCE = ?');
          params.add(_required(value?.toString(), '省份', _addressPartMaxLength));
        case 'city':
          setters.add('CITY = ?');
          params.add(_required(value?.toString(), '城市', _addressPartMaxLength));
        case 'county':
          setters.add('COUNTY = ?');
          params.add(_optional(value?.toString(), '区县', _addressPartMaxLength));
        case 'town':
          setters.add('TOWN = ?');
          params.add(_optional(value?.toString(), '乡镇/街道', _addressPartMaxLength));
        case 'address':
          setters.add('ADDRESS = ?');
          params.add(_required(value?.toString(), '详细地址', _addressMaxLength));
        case 'tel':
          setters.add('TEL = ?');
          params.add(_optional(value?.toString(), '联系电话', _telMaxLength));
        case 'logoBase64':
          setters.add('LOGO_IMAGE = ?');
          params.add(value?.toString());
        case 'sealBase64':
          setters.add('SEAL_IMAGE = ?');
          params.add(value?.toString());
        case 'watermarkBase64':
          setters.add('WATERMARK_IMAGE = ?');
          params.add(value?.toString());
        default:
          throw HospitalException(400, 40002, '不支持的修改字段：${entry.key}');
      }
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(_toInt(id));
    await _db.execute(
      'UPDATE SYS_HOSPITAL SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 统计子树规模（含自身），供删除前确认提示。
  Future<int> subtreeCount(String id) async {
    await getById(id);
    return (await _collectSubtreeIds(id)).length;
  }

  /// 统计子树各医院下的院区总数（SYS_CAMPUS，HOSP_ID 关联），
  /// 供删除前确认提示与前置阻止校验。
  Future<int> subtreeCampusCount(String id) async {
    await getById(id);
    final ids = await _collectSubtreeIds(id);
    var count = 0;
    for (var i = 0; i < ids.length; i += _batchSize) {
      final batch = ids.skip(i).take(_batchSize).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');
      final result = await _db.query(
        'SELECT COUNT(*) AS CNT FROM SYS_CAMPUS WHERE HOSP_ID IN ($placeholders)',
        batch,
      );
      count += int.parse(result.rowsAsMaps.first['CNT'] ?? '0');
    }
    return count;
  }

  /// 级联删除医院及其全部下级，返回删除行数。中断后重试幂等。
  ///
  /// 子树内任一医院下存在院区（SYS_CAMPUS）时阻止删除——须先在院区
  /// 管理中删除对应院区，防止院区沦为孤儿数据。
  Future<int> deleteSubtree(String id) async {
    await getById(id);
    final campusCount = await subtreeCampusCount(id);
    if (campusCount > 0) {
      throw const HospitalException(400, 40001, '请先删除院区后，再删除医院');
    }
    final ids = await _collectSubtreeIds(id);
    var deleted = 0;
    for (var i = 0; i < ids.length; i += _batchSize) {
      final batch = ids.skip(i).take(_batchSize).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');
      deleted += await _db.execute(
        'DELETE FROM SYS_HOSPITAL WHERE ID IN ($placeholders)',
        batch,
      );
    }
    return deleted;
  }

  /// 详情查询 SQL 前缀（含 HAS_CHILDREN，与 listAll 列序一致）。
  static const String _detailSql =
      'SELECT H.ID, H.PARENT_ID, H.CODE, H.NAME, H.NAME_EN, H.PROVINCE, '
      'H.CITY, H.COUNTY, H.TOWN, H.ADDRESS, H.TEL, H.LOGO_IMAGE, '
      'H.SEAL_IMAGE, H.WATERMARK_IMAGE, '
      'CASE WHEN EXISTS (SELECT 1 FROM SYS_HOSPITAL H2 '
      'WHERE H2.PARENT_ID = H.ID) THEN 1 ELSE 0 END AS HAS_CHILDREN '
      'FROM SYS_HOSPITAL H';

  /// 自顶向下逐层收集子树全部 ID（含根），每层按批 IN 查询子级。
  Future<List<int>> _collectSubtreeIds(String rootId) async {
    final ids = <int>[_toInt(rootId)];
    var start = 0;
    while (start < ids.length) {
      final batch = ids.skip(start).take(_batchSize).toList();
      start += batch.length;
      final placeholders = List.filled(batch.length, '?').join(', ');
      final result = await _db.query(
        'SELECT ID FROM SYS_HOSPITAL WHERE PARENT_ID IN ($placeholders) ORDER BY ID',
        batch,
      );
      ids.addAll(result.rows.map((row) => int.parse(row[0]!)));
    }
    return ids;
  }

  /// 从数据库行解析（HAS_CHILDREN 仅查询携带，缺省视为无下级）。
  Hospital _fromRow(Map<String, String?> row) => Hospital(
    id: row['ID'] ?? '',
    parentId: row['PARENT_ID'],
    code: row['CODE'],
    name: row['NAME'] ?? '',
    nameEn: row['NAME_EN'],
    province: row['PROVINCE'] ?? '',
    city: row['CITY'] ?? '',
    county: row['COUNTY'],
    town: row['TOWN'],
    address: row['ADDRESS'] ?? '',
    tel: row['TEL'],
    logoBase64: row['LOGO_IMAGE'],
    sealBase64: row['SEAL_IMAGE'],
    watermarkBase64: row['WATERMARK_IMAGE'],
    hasChildren: row['HAS_CHILDREN'] == '1',
  );

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw HospitalException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw HospitalException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw HospitalException(400, 40002, '医院ID格式不正确：$id');
    }
    return v;
  }
}
