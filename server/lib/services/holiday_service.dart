import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';

/// 法定节假日业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 HighRiskFactorExclusionException）。
final class HolidayException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const HolidayException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'HolidayException($httpStatus, $code): $message';
}

/// 国家法定节假日管理服务：按医院隔离的列表、详情与增删改。
///
/// 经 DatabaseGateway 访问 BASE_HOLIDAY。一行表示一个法定节假日的
/// 放假区间（START_DATE ~ END_DATE 闭区间），HOLIDAY_TYPE 为 1-8 的
/// 节假日类型（标签见 BaseHoliday.holidayTypeLabels）。医院与创建人
/// 冗余列由路由层从令牌会话推导后传入（不信任客户端上报），修改不
/// 更新创建人。主键为数据库自增 BIGINT（非应用侧生成），新增后不回读
/// 主键——客户端整表重拉即可。时间列统一 Dart 侧 formatTimestamp
/// 生成后绑定。
class HolidayService {
  /// 构造函数：注入数据库网关。
  HolidayService(this._db);

  final DatabaseGateway _db;

  /// 可经 update 修改的字段（创建人、医院与时间列不可改）。
  static const Set<String> _editableFields = {'startDate', 'endDate', 'holidayType'};

  /// 查询指定医院的全部法定节假日（按起始日期倒序，最新维护的年份在前）。
  ///
  /// hospId 为空（用户未归属医院）时返回空列表。
  Future<List<BaseHoliday>> listByHospital(String hospId) async {
    final scope = hospId.trim();
    if (scope.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, START_DATE, END_DATE, HOLIDAY_TYPE, CREATOR_ID, '
      'CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM BASE_HOLIDAY WHERE HOSP_ID = ? '
      'ORDER BY START_DATE DESC, ID DESC',
      [scope],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 按 ID 查询单条法定节假日，不存在时抛业务异常。
  Future<BaseHoliday> getById(String id) async {
    final result = await _db.query(
      'SELECT ID, START_DATE, END_DATE, HOLIDAY_TYPE, CREATOR_ID, '
      'CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM BASE_HOLIDAY WHERE ID = ?',
      [_id(id, '节假日ID')],
    );
    if (result.rows.isEmpty) {
      throw HolidayException(400, 40001, '法定节假日不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 新增法定节假日（自增主键由数据库生成，不回读，客户端整表重拉）。
  ///
  /// 起止日期必填且为 yyyy-MM-dd、起始不得晚于截止；类型须为 1-8。
  /// hospId/hospName/creatorId/creatorName 由路由层从登录会话推导传入。
  Future<void> create({
    required String startDate,
    required String endDate,
    required int holidayType,
    required String hospId,
    required String hospName,
    required String creatorId,
    required String creatorName,
  }) async {
    final start = _requiredDate(startDate, '起始日期');
    final end = _requiredDate(endDate, '截止日期');
    _ensureStartNotAfterEnd(start, end);
    final type = _holidayType(holidayType);
    final hospIdValue = _id(hospId, '医院ID');
    final hosp = _required(hospName, '医院名称', 100);
    final creatorIdValue = _id(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', 30);

    await _db.execute(
      'INSERT INTO BASE_HOLIDAY (START_DATE, END_DATE, HOLIDAY_TYPE, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        start,
        end,
        type,
        creatorIdValue,
        creator,
        hospIdValue,
        hosp,
        formatTimestamp(DateTime.now()),
      ],
    );
  }

  /// 修改法定节假日（changes 为本次要更新的字段集合，键与 JSON 契约
  /// 一致：startDate / endDate / holidayType；未传的字段沿用当前值）。
  ///
  /// 修改后同样校验日期格式与先后顺序、类型取值范围；创建人与医院
  /// 冗余列不变，仅刷新 UPDATE_TIME。返回修改后的对象。
  Future<BaseHoliday> update(String id, Map<String, Object?> changes) async {
    for (final key in changes.keys) {
      if (!_editableFields.contains(key)) {
        throw HolidayException(400, 40002, '不支持的修改字段：$key');
      }
    }
    final current = await getById(id);
    final idValue = _id(id, '节假日ID');

    // 先解析目标值（未传的字段沿用当前值），整行校验通过后再落库
    final start = changes.containsKey('startDate') ? _requiredDate(changes['startDate']?.toString() ?? '', '起始日期') : current.startDate;
    final end = changes.containsKey('endDate') ? _requiredDate(changes['endDate']?.toString() ?? '', '截止日期') : current.endDate;
    _ensureStartNotAfterEnd(start, end);
    final type = changes.containsKey('holidayType') ? _holidayType(_parseType(changes['holidayType']) ?? 0) : current.holidayType;

    final setters = <String>[];
    final params = <Object?>[];
    if (changes.containsKey('startDate')) {
      setters.add('START_DATE = ?');
      params.add(start);
    }
    if (changes.containsKey('endDate')) {
      setters.add('END_DATE = ?');
      params.add(end);
    }
    if (changes.containsKey('holidayType')) {
      setters.add('HOLIDAY_TYPE = ?');
      params.add(type);
    }

    if (setters.isEmpty) return getById(id);

    setters.add('UPDATE_TIME = ?');
    params
      ..add(formatTimestamp(DateTime.now()))
      ..add(idValue);
    await _db.execute(
      'UPDATE BASE_HOLIDAY SET ${setters.join(', ')} WHERE ID = ?',
      params,
    );
    return getById(id);
  }

  /// 删除法定节假日，返回删除行数（0 或 1）。
  Future<int> delete(String id) async {
    await getById(id);
    return _db.execute('DELETE FROM BASE_HOLIDAY WHERE ID = ?', [
      _id(id, '节假日ID'),
    ]);
  }

  // ---------------- 内部辅助 ----------------

  /// 从数据库行解析法定节假日（自增主键经网关以字符串返回）。
  BaseHoliday _fromRow(Map<String, String?> row) => BaseHoliday(
    id: row['ID'] ?? '',
    startDate: row['START_DATE'] ?? '',
    endDate: row['END_DATE'] ?? '',
    holidayType: int.tryParse(row['HOLIDAY_TYPE'] ?? '') ?? 0,
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 必填日期校验（yyyy-MM-dd 且可解析为有效日期）。
  String _requiredDate(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw HolidayException(400, 40002, '$label不能为空');
    }
    final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) && DateTime.tryParse(v) != null;
    if (!ok) {
      throw HolidayException(400, 40002, '$label格式应为 yyyy-MM-dd：$value');
    }
    return v;
  }

  /// 起始日期不得晚于截止日期（闭区间须为正区间）。
  void _ensureStartNotAfterEnd(String start, String end) {
    if (DateTime.tryParse(start)!.isAfter(DateTime.tryParse(end)!)) {
      throw const HolidayException(400, 40002, '起始日期不能晚于截止日期');
    }
  }

  /// 类型原始值归一为 int（JSON 直接给 int，或字符串数字兜底）。
  int? _parseType(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  /// 节假日类型校验（1-8，标签见 BaseHoliday.holidayTypeLabels）。
  int _holidayType(int type) {
    if (type < 1 || type > BaseHoliday.holidayTypeLabels.length) {
      throw HolidayException(400, 40002, '节假日类型取值须为 1-${BaseHoliday.holidayTypeLabels.length}：$type');
    }
    return type;
  }

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw HolidayException(400, 40002, '$label不能为空');
    }
    if (v.length > maxLength) {
      throw HolidayException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 必填 ID 校验：自增/UUID 主键经网关以字符串取回，仅需去空格、非空。
  String _id(String id, String label) {
    final v = id.trim();
    if (v.isEmpty) {
      throw HolidayException(400, 40002, '$label不能为空');
    }
    return v;
  }
}
