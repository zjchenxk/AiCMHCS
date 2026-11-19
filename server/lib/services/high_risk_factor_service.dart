import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/utils/uuid_util.dart';

/// 高危因素类业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 DictException / MenuException）。
final class HighRiskFactorException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const HighRiskFactorException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'HighRiskFactorException($httpStatus, $code): $message';
}

/// 高危因素字典管理服务：按医院隔离的列表、详情与增删改。
///
/// 经 DatabaseGateway 访问 BASE_HIGH_RISK_FACTOR。医院与创建人冗余
/// 列由路由层从令牌会话推导后传入（不信任客户端上报），名称含中文时
/// 由达梦网关参数改写自动内联，业务层直接写参数化 SQL。主键为应用侧
/// 生成的 UUID v7（CHAR(36)，见 newUuid），INSERT 前置生成、无自增回读
/// 环节。RISK_FACTOR_CODE 同医院内唯一由服务层 COUNT 校验（表上不建
/// 唯一约束，与 BASE_DICT 的 DICT_CODE 同策略）；RISK_COLOR 限中文
/// 五色（绿色/黄色/橙色/红色/紫色），RISK_SCORE 限 0-127（TINYINT
/// 非负段，PostgreSQL 方言用 SMALLINT 承载）。时间列统一 Dart 侧
/// formatTimestamp 生成后绑定。
class HighRiskFactorService {
  /// 构造函数：注入数据库网关。
  HighRiskFactorService(this._db);

  final DatabaseGateway _db;

  /// 合法高危颜色（共享常量，见 BaseHighRiskFactor.riskColors）。
  static const List<String> riskColors = BaseHighRiskFactor.riskColors;

  /// 各字段长度上限（与表列宽对齐）。
  static const int _categoryMaxLength = 50;
  static const int _subcategoryMaxLength = 50;
  static const int _codeMaxLength = 20;
  static const int _nameMaxLength = 200;
  static const int _colorMaxLength = 10;
  static const int _levelMaxLength = 10;
  static const int _hospNameMaxLength = 100;
  static const int _creatorNameMaxLength = 30;

  /// 高危分值取值范围（共享常量，见 BaseHighRiskFactor）。
  static const int _scoreMinValue = BaseHighRiskFactor.riskScoreMin;
  static const int _scoreMaxValue = BaseHighRiskFactor.riskScoreMax;

  /// 可经 update 修改的字段（创建人、医院与时间列不可改）。
  static const Set<String> _editableFields = {
    'riskFactorCategory',
    'riskFactorSubcategory',
    'riskFactorCode',
    'riskFactorName',
    'riskColor',
    'riskLevel',
    'riskScore',
  };

  /// 查询指定医院的全部高危因素（按创建顺序），供前端按颜色/大类组树。
  ///
  /// hospId 为空（用户未归属医院）时返回空列表。
  Future<List<BaseHighRiskFactor>> listByHospital(String hospId) async {
    final scope = hospId.trim();
    if (scope.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, RISK_FACTOR_CATEGORY, RISK_FACTOR_SUBCATEGORY, '
      'RISK_FACTOR_CODE, RISK_FACTOR_NAME, RISK_COLOR, RISK_LEVEL, '
      'RISK_SCORE, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, '
      'CREATE_TIME, UPDATE_TIME FROM BASE_HIGH_RISK_FACTOR '
      'WHERE HOSP_ID = ? ORDER BY ID',
      [scope],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单个高危因素，不存在时抛业务异常。
  Future<BaseHighRiskFactor> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, RISK_FACTOR_CATEGORY, RISK_FACTOR_SUBCATEGORY, '
      'RISK_FACTOR_CODE, RISK_FACTOR_NAME, RISK_COLOR, RISK_LEVEL, '
      'RISK_SCORE, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, '
      'CREATE_TIME, UPDATE_TIME FROM BASE_HIGH_RISK_FACTOR WHERE ID = ?',
      [_id(id, '高危因素ID')],
    );
    if (result.rows.isEmpty) {
      throw HighRiskFactorException(400, 40001, '高危因素不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增高危因素，返回新增后的对象。
  ///
  /// 编码/名称必填，大类/小类/颜色/等级/分值可选；编码同医院内唯一。
  /// hospId/hospName/creatorId/creatorName 由路由层从登录会话推导传入。
  Future<BaseHighRiskFactor> create({
    required String riskFactorCode,
    required String riskFactorName,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
    String? riskFactorCategory,
    String? riskFactorSubcategory,
    String? riskColor,
    String? riskLevel,
    String? riskScore,
  }) async {
    final code = _required(riskFactorCode, '高危因素编码', _codeMaxLength);
    final name = _required(riskFactorName, '高危因素名称', _nameMaxLength);
    final category = _optional(riskFactorCategory, '大类', _categoryMaxLength);
    final subcategory = _optional(riskFactorSubcategory, '小类', _subcategoryMaxLength);
    final color = _optionalColor(riskColor);
    final level = _optional(riskLevel, '高危等级', _levelMaxLength);
    final score = _optionalScore(riskScore);
    final hospIdValue = _id(hospId, '医院ID');
    final hosp = _required(hospName, '医院名称', _hospNameMaxLength);
    final creatorIdValue = _id(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', _creatorNameMaxLength);

    await _ensureCodeUnique(hospIdValue, code);

    final newId = newUuid();
    await _db.execute(
      'INSERT INTO BASE_HIGH_RISK_FACTOR (ID, RISK_FACTOR_CATEGORY, '
      'RISK_FACTOR_SUBCATEGORY, RISK_FACTOR_CODE, RISK_FACTOR_NAME, '
      'RISK_COLOR, RISK_LEVEL, RISK_SCORE, CREATOR_ID, CREATOR_NAME, '
      'HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        newId,
        category,
        subcategory,
        code,
        name,
        color,
        level,
        score,
        creatorIdValue,
        creator,
        hospIdValue,
        hosp,
        formatTimestamp(DateTime.now()),
      ],
    );
    return getById(newId);
  }

  /// 快速新增高危因素（儿童建档页高危因素 TAB 的「新增高危因素」场景）。
  ///
  /// 与 [create] 的差异：大类固定「其它」、编码按高危颜色默认映射
  /// （黄色 02990000 / 橙色 03990000 / 红色 04990000 / 紫色 05990000）、
  /// 等级与分值为空，且**不走编码同医院唯一性校验**（需求明确允许默认
  /// 编码重复，同一默认编码可多次新增）。hospId/hospName/creatorId/
  /// creatorName 由路由层从登录会话推导传入。
  Future<BaseHighRiskFactor> quickCreate({
    required String riskColor,
    required String riskFactorName,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
  }) async {
    const fallbackCodes = {
      '黄色': '02990000',
      '橙色': '03990000',
      '红色': '04990000',
      '紫色': '05990000',
    };
    final color = _optionalColor(riskColor);
    final code = fallbackCodes[color];
    if (code == null) {
      throw HighRiskFactorException(400, 40002, '高危颜色应为黄色/橙色/红色/紫色：$riskColor');
    }
    final name = _required(riskFactorName, '高危因素名称', _nameMaxLength);
    final hospIdValue = _id(hospId, '医院ID');
    final hosp = _required(hospName, '医院名称', _hospNameMaxLength);
    final creatorIdValue = _id(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', _creatorNameMaxLength);

    final newId = newUuid();
    await _db.execute(
      'INSERT INTO BASE_HIGH_RISK_FACTOR (ID, RISK_FACTOR_CATEGORY, '
      'RISK_FACTOR_SUBCATEGORY, RISK_FACTOR_CODE, RISK_FACTOR_NAME, '
      'RISK_COLOR, RISK_LEVEL, RISK_SCORE, CREATOR_ID, CREATOR_NAME, '
      'HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        newId,
        '其它',
        code,
        name,
        color,
        null,
        null,
        creatorIdValue,
        creator,
        hospIdValue,
        hosp,
        formatTimestamp(DateTime.now()),
      ],
    );
    return getById(newId);
  }

  /// 修改高危因素（changes 为本次要更新的字段集合，键与 JSON 契约
  /// 一致；值为 null 表示清空该列——仅可空列允许）。编码同医院内唯一。
  Future<BaseHighRiskFactor> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!_editableFields.contains(key)) {
        throw HighRiskFactorException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _id(id, '高危因素ID');

    // 先解析目标值并完成唯一性校验（必填字段必须非空、可空字段 null 清空）
    final category = changes.containsKey('riskFactorCategory') ? _optional(changes['riskFactorCategory']?.toString(), '大类', _categoryMaxLength) : null;
    final subcategory = changes.containsKey('riskFactorSubcategory') ? _optional(changes['riskFactorSubcategory']?.toString(), '小类', _subcategoryMaxLength) : null;
    final code = changes.containsKey('riskFactorCode') ? _required(changes['riskFactorCode']?.toString(), '高危因素编码', _codeMaxLength) : null;
    if (code != null) {
      await _ensureCodeUnique(current.hospId, code, excludeId: idValue);
    }
    final name = changes.containsKey('riskFactorName') ? _required(changes['riskFactorName']?.toString(), '高危因素名称', _nameMaxLength) : null;
    final color = changes.containsKey('riskColor') ? _optionalColor(changes['riskColor']?.toString()) : null;
    final level = changes.containsKey('riskLevel') ? _optional(changes['riskLevel']?.toString(), '高危等级', _levelMaxLength) : null;
    final score = changes.containsKey('riskScore') ? _optionalScore(changes['riskScore']?.toString()) : null;

    // 构建更新语句（键序即 changes 传入序）
    final setters = <String>[];
    final params = <Object?>[];
    for (final entry in changes.entries) {
      switch (entry.key) {
        case 'riskFactorCategory':
          setters.add('RISK_FACTOR_CATEGORY = ?');
          params.add(category);
        case 'riskFactorSubcategory':
          setters.add('RISK_FACTOR_SUBCATEGORY = ?');
          params.add(subcategory);
        case 'riskFactorCode':
          setters.add('RISK_FACTOR_CODE = ?');
          params.add(code);
        case 'riskFactorName':
          setters.add('RISK_FACTOR_NAME = ?');
          params.add(name);
        case 'riskColor':
          setters.add('RISK_COLOR = ?');
          params.add(color);
        case 'riskLevel':
          setters.add('RISK_LEVEL = ?');
          params.add(level);
        case 'riskScore':
          setters.add('RISK_SCORE = ?');
          params.add(score);
      }
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE BASE_HIGH_RISK_FACTOR SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除高危因素，返回删除行数（0 或 1）。
  Future<int> delete(String id) async {
    await getById(id);
    return _db.execute('DELETE FROM BASE_HIGH_RISK_FACTOR WHERE ID = ?', [
      _id(id, '高危因素ID'),
    ]);
  }

  // ---------------- 内部辅助 ----------------

  /// 从数据库行解析高危因素。
  BaseHighRiskFactor _fromRow(Map<String, String?> row) => BaseHighRiskFactor(
    id: row['ID'] ?? '',
    riskFactorCategory: row['RISK_FACTOR_CATEGORY'],
    riskFactorSubcategory: row['RISK_FACTOR_SUBCATEGORY'],
    riskFactorCode: row['RISK_FACTOR_CODE'] ?? '',
    riskFactorName: row['RISK_FACTOR_NAME'] ?? '',
    riskColor: row['RISK_COLOR'],
    riskLevel: row['RISK_LEVEL'],
    riskScore: row['RISK_SCORE'],
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 校验高危因素编码同医院内唯一（excludeId 用于修改时排除自身）。
  Future<void> _ensureCodeUnique(String hospId, String code, {String? excludeId}) async {
    final sql = excludeId == null ? 'SELECT COUNT(*) AS CNT FROM BASE_HIGH_RISK_FACTOR WHERE HOSP_ID = ? AND RISK_FACTOR_CODE = ?' : 'SELECT COUNT(*) AS CNT FROM BASE_HIGH_RISK_FACTOR WHERE HOSP_ID = ? AND RISK_FACTOR_CODE = ? AND ID <> ?';
    final params = excludeId == null ? <Object?>[hospId, code] : <Object?>[hospId, code, excludeId];
    final dup = await _db.query(sql, params);
    if (int.parse(dup.rowsAsMaps.first['CNT'] ?? '0') > 0) {
      throw HighRiskFactorException(400, 40001, '该医院下高危因素编码已存在：$code');
    }
  }

  /// 高危颜色校验：空值归一为 null，非空时限中文五色之一。
  String? _optionalColor(String? value) {
    final v = _optional(value, '高危颜色', _colorMaxLength);
    if (v == null) return null;
    if (!riskColors.contains(v)) {
      throw HighRiskFactorException(400, 40002, '高危颜色应为：${riskColors.join('/')}：$value');
    }
    return v;
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw HighRiskFactorException(400, 40002, '$label不能为空');
    }
    // 走到此处 v 非空，_optional 必返回非 null
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw HighRiskFactorException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 可空高危分值校验：空值归一为 null，非空时须为 0-127 的整数
  /// （TINYINT 非负段；网关列值均为字符串）。
  int? _optionalScore(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < _scoreMinValue || n > _scoreMaxValue) {
      throw HighRiskFactorException(
        400,
        40002,
        '高危分值应为 $_scoreMinValue-$_scoreMaxValue 的整数：$value',
      );
    }
    return n;
  }

  /// 必填 ID 校验：UUID 主键经网关以字符串取回，仅需去空格、非空。
  String _id(String id, String label) {
    final v = id.trim();
    if (v.isEmpty) {
      throw HighRiskFactorException(400, 40002, '$label不能为空');
    }
    return v;
  }
}
