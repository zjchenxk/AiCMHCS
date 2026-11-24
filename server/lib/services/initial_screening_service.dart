import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/utils/uuid_util.dart';

/// 孤独症初筛业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 ChildException / DictException）。
final class AsdException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const AsdException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'AsdException($httpStatus, $code): $message';
}

/// 检查医生候选（同科室 USER_TYPE=DOCTOR 的启用用户）。
typedef DoctorOption = ({String id, String userCode, String userName});

/// 孤独症初筛记录服务：按儿童装载初筛记录、预警征象条目查询、检查
/// 医生候选、记录新增/修改（同一儿童同一检查时段至多一条，服务层查重
/// 后走 INSERT 或 UPDATE）与删除。
///
/// 经 DatabaseGateway 访问 ASD_INITIAL_SCREENING / SCALE_WSCMBD /
/// SYS_USER 三表。初筛记录按医院隔离（HOSP_ID 匹配登录用户所属医院，
/// 由路由层从令牌会话推导后传入，不信任客户端上报；名称含中文时由
/// 达梦网关参数改写自动内联，业务层直接写参数化 SQL）。主键为应用侧
/// 生成的 UUID v7（CHAR(36)，见 newUuid），INSERT 前置生成、无自增回读
/// 环节。SCALE_WSCMBD 为全局基础数据表（不按医院隔离、无管理界面），
/// 基础条目由运维侧自行录入。科室/院区归属随创建人上下文由路由层从
/// 令牌会话推导传入，新增时写入、修改时不更新。时间列统一 Dart 侧
/// formatTimestamp 生成后绑定。
class InitialScreeningService {
  /// 构造函数：注入数据库网关。
  InitialScreeningService(this._db);

  final DatabaseGateway _db;

  /// 合法检查时段（CHECK_MONTH：3/6/8/12/18/24/30/36 月龄与 48/60/72=4/5/6 岁）。
  static const Set<int> checkMonths = {3, 6, 8, 12, 18, 24, 30, 36, 48, 60, 72};

  /// 初筛结果：未见异常。
  static const String checkResultNormal = '未见异常';

  /// 初筛结果：异常。
  static const String checkResultAbnormal = '异常';

  /// 有无转诊取值（0-无/1-有）。
  static const Set<String> referralFlags = {'0', '1'};

  /// 无转诊时转诊医院名称的占位文本（REFERRAL_HOSP_NAME 列 NOT NULL，
  /// 达梦把空串按 NULL 处理，不可用空串占位）。
  static const String noReferralText = '无';

  /// 各字段长度上限（与表列宽对齐；WARNING_SIGN_RESULT/LANGUAGE_... 为
  /// 中文条目名称顿号连接，达梦 VARCHAR 按字节计，按 UTF-8 字节数校验）。
  static const int _warningSignMaxBytes = 200;
  static const int _languageSocialMaxBytes = 100;
  static const int _checkResultMaxLength = 20;
  static const int _referralHospMaxLength = 100;
  static const int _referralDeptMaxLength = 50;
  static const int _doctorNameMaxLength = 30;

  /// 年龄分段合法取值上限（TINYINT 列，0-127）。
  static const int _ageMaxValue = 127;

  // ---------------- 查询 ----------------

  /// 装载当前儿童全部初筛记录（按检查时段升序，TAB 页红点与逐月龄
  /// 浏览共用一次请求）。
  Future<List<InitialScreening>> listByChild(String childId, String hospId) async {
    final scope = hospId.trim();
    if (scope.isEmpty || childId.trim().isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, CHILD_ID, CHECK_DATE, AGE_YEAR, AGE_MONTH, AGE_DAY, '
      'CORRECTED_AGE_YEAR, CORRECTED_AGE_MONTH, CORRECTED_AGE_DAY, '
      'CHECK_MONTH, WARNING_SIGN_RESULT, LANGUAGE_SOCIAL_COMMUNICATION_RESULT, '
      'CHECK_RESULT, HAS_REFERRAL, REFERRAL_HOSP_ID, REFERRAL_HOSP_NAME, '
      'REFERRAL_DEPT_ID, REFERRAL_DEPT_NAME, DOCTOR_ID, DOCTOR_NAME, '
      'CREATOR_ID, CREATOR_NAME, DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, '
      'HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM ASD_INITIAL_SCREENING WHERE CHILD_ID = ? AND HOSP_ID = ? '
      'ORDER BY CHECK_MONTH',
      [childId.trim(), scope],
    );
    return result.rowsAsMaps.map(_fromRow).toList(growable: false);
  }

  /// 查询指定月龄的预警征象条目（按条目序号升序；基础数据由运维侧
  /// 录入，无条目时返回空列表，界面提示字典未配置）。
  Future<List<WscmbdItem>> wscmbdItems(int month) async {
    final result = await _db.query(
      'SELECT ID, MONTH, ITEM_NAME, ITEM_TYPE, ITEM_ORDER, ITEM_DESC '
      'FROM SCALE_WSCMBD WHERE MONTH = ? ORDER BY ITEM_ORDER, ID',
      [month],
    );
    return result.rowsAsMaps.map(_itemFromRow).toList(growable: false);
  }

  /// 查询指定科室的检查医生候选（同科室、USER_TYPE=DOCTOR、未停用的
  /// 用户，按登录账号排序；deptId 为空返回空列表）。
  Future<List<DoctorOption>> listDoctors(String deptId) async {
    final dept = deptId.trim();
    if (dept.isEmpty) {
      return const [];
    }
    final result = await _db.query(
      'SELECT ID, USER_CODE, USER_NAME FROM SYS_USER '
      'WHERE DEPT_ID = ? AND USER_TYPE = ? AND (STATUS IS NULL OR STATUS <> ?) '
      'ORDER BY USER_CODE',
      [dept, 'DOCTOR', '0'],
    );
    return [
      for (final row in result.rowsAsMaps)
        (
          id: row['ID'] ?? '',
          userCode: row['USER_CODE'] ?? '',
          userName: row['USER_NAME'] ?? '',
        ),
    ];
  }

  // ---------------- 新增 / 修改 / 删除 ----------------

  /// 保存初筛记录（同一儿童同一检查时段至多一条：已存在则整体更新，
  /// 否则新增），返回保存后的记录。
  ///
  /// 儿童必须存在且属本院；归属医院/创建人与科室/院区上下文由路由层
  /// 从令牌会话推导传入（新增写入、修改沿用原值）；检查医生必须为本院
  /// 同科室的启用医生（防越科室/越院乱挂）。hasReferral='0'（无转诊）
  /// 时转诊医院名称统一落「无」、转诊科室清空；'1' 时转诊医院名称必填。
  Future<InitialScreening> save({
    required InitialScreening record,
    required String operatorId,
    required String operatorName,
    required String hospId,
    required String hospName,
    String? deptId,
    String? deptName,
    String? campusId,
    String? campusName,
  }) async {
    final scope = hospId.trim();
    final childIdValue = _required(record.childId, '儿童ID', 36);
    final month = record.checkMonth;
    if (!checkMonths.contains(month)) {
      throw const AsdException(400, 40002, '检查时段取值不合法');
    }
    await _requireChild(childIdValue, scope);

    final doctor = await _requireDoctor(record.doctorId, record.doctorName, scope, deptId?.trim() ?? '');
    final hasReferral = _optionalFlag(record.hasReferral);
    final referralHospName = hasReferral == '1' ? _required(record.referralHospName, '转诊医院名称', _referralHospMaxLength) : noReferralText;
    final referralDeptName = hasReferral == '1' ? _optional(record.referralDeptName, '转诊科室名称', _referralDeptMaxLength) : null;
    final referralHospId = hasReferral == '1' ? _optionalId(record.referralHospId) : null;
    final referralDeptId = hasReferral == '1' ? _optionalId(record.referralDeptId) : null;

    final warning = _requiredEnc(record.warningSignResult, '预警征象筛查结果', _warningSignMaxBytes);
    final languageSocial = _requiredEnc(
      record.languageSocialCommunicationResult,
      '语言功能和社会交往能力询问结果',
      _languageSocialMaxBytes,
    );
    final checkResult = record.checkResult.trim();
    if (checkResult.isEmpty || checkResult.length > _checkResultMaxLength) {
      throw const AsdException(400, 40002, '初筛结果不能为空且不能超过 $_checkResultMaxLength 个字符');
    }
    final checkDate = _requiredDate(record.checkDate);

    // 同一儿童同一时段查重：已存在则更新（沿用原归属/创建人），否则新增
    final existing = await _db.query(
      'SELECT ID FROM ASD_INITIAL_SCREENING '
      'WHERE CHILD_ID = ? AND CHECK_MONTH = ? AND HOSP_ID = ?',
      [childIdValue, month, scope],
    );
    if (existing.rows.isNotEmpty) {
      final id = existing.rowsAsMaps.first['ID'] ?? '';
      await _db.execute(
        'UPDATE ASD_INITIAL_SCREENING SET CHECK_DATE = ?, AGE_YEAR = ?, '
        'AGE_MONTH = ?, AGE_DAY = ?, CORRECTED_AGE_YEAR = ?, '
        'CORRECTED_AGE_MONTH = ?, CORRECTED_AGE_DAY = ?, '
        'WARNING_SIGN_RESULT = ?, LANGUAGE_SOCIAL_COMMUNICATION_RESULT = ?, '
        'CHECK_RESULT = ?, HAS_REFERRAL = ?, REFERRAL_HOSP_ID = ?, '
        'REFERRAL_HOSP_NAME = ?, REFERRAL_DEPT_ID = ?, REFERRAL_DEPT_NAME = ?, '
        'DOCTOR_ID = ?, DOCTOR_NAME = ?, UPDATE_TIME = ? '
        'WHERE ID = ? AND HOSP_ID = ?',
        [
          checkDate,
          _agePart(record.ageYear, '实足年龄-岁'),
          _agePart(record.ageMonth, '实足年龄-月'),
          _agePart(record.ageDay, '实足年龄-天'),
          _optionalAgePart(record.correctedAgeYear, '纠正年龄-岁'),
          _optionalAgePart(record.correctedAgeMonth, '纠正年龄-月'),
          _optionalAgePart(record.correctedAgeDay, '纠正年龄-天'),
          warning,
          languageSocial,
          checkResult,
          hasReferral,
          referralHospId,
          referralHospName,
          referralDeptId,
          referralDeptName,
          doctor.id,
          doctor.name,
          formatTimestamp(DateTime.now()),
          id,
          scope,
        ],
      );
      return _getById(id, scope);
    }

    final newId = newUuid();
    await _db.execute(
      'INSERT INTO ASD_INITIAL_SCREENING (ID, CHILD_ID, CHECK_DATE, '
      'AGE_YEAR, AGE_MONTH, AGE_DAY, CORRECTED_AGE_YEAR, CORRECTED_AGE_MONTH, '
      'CORRECTED_AGE_DAY, CHECK_MONTH, WARNING_SIGN_RESULT, '
      'LANGUAGE_SOCIAL_COMMUNICATION_RESULT, CHECK_RESULT, HAS_REFERRAL, '
      'REFERRAL_HOSP_ID, REFERRAL_HOSP_NAME, REFERRAL_DEPT_ID, '
      'REFERRAL_DEPT_NAME, DOCTOR_ID, DOCTOR_NAME, CREATOR_ID, CREATOR_NAME, '
      'DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, HOSP_ID, HOSP_NAME, '
      'CREATE_TIME) '
      'VALUES (${List.filled(29, '?').join(', ')})',
      [
        newId,
        childIdValue,
        checkDate,
        _agePart(record.ageYear, '实足年龄-岁'),
        _agePart(record.ageMonth, '实足年龄-月'),
        _agePart(record.ageDay, '实足年龄-天'),
        _optionalAgePart(record.correctedAgeYear, '纠正年龄-岁'),
        _optionalAgePart(record.correctedAgeMonth, '纠正年龄-月'),
        _optionalAgePart(record.correctedAgeDay, '纠正年龄-天'),
        month,
        warning,
        languageSocial,
        checkResult,
        hasReferral,
        referralHospId,
        referralHospName,
        referralDeptId,
        referralDeptName,
        doctor.id,
        doctor.name,
        _required(operatorId, '创建人ID', 36),
        _required(operatorName, '创建人姓名', _doctorNameMaxLength),
        _optionalId(deptId),
        _optional(deptName, '科室名称', _referralDeptMaxLength),
        _optionalId(campusId),
        _optional(campusName, '院区名称', _referralDeptMaxLength),
        scope,
        _required(hospName, '医院名称', _referralHospMaxLength),
        formatTimestamp(DateTime.now()),
      ],
    );
    return _getById(newId, scope);
  }

  /// 删除初筛记录（按 ID；跨院 ID 删不到，返回 0），返回删除行数（0 或 1）。
  Future<int> delete(String id, String hospId) async {
    final idValue = id.trim();
    if (idValue.isEmpty) {
      throw const AsdException(400, 40002, '初筛记录ID不能为空');
    }
    return _db.execute('DELETE FROM ASD_INITIAL_SCREENING WHERE ID = ? AND HOSP_ID = ?', [idValue, hospId.trim()]);
  }

  // ---------------- 内部辅助 ----------------

  /// 按本院范围取初筛记录行，不存在时抛业务异常。
  Future<InitialScreening> _getById(String id, String hospId) async {
    final result = await _db.query(
      'SELECT ID, CHILD_ID, CHECK_DATE, AGE_YEAR, AGE_MONTH, AGE_DAY, '
      'CORRECTED_AGE_YEAR, CORRECTED_AGE_MONTH, CORRECTED_AGE_DAY, '
      'CHECK_MONTH, WARNING_SIGN_RESULT, LANGUAGE_SOCIAL_COMMUNICATION_RESULT, '
      'CHECK_RESULT, HAS_REFERRAL, REFERRAL_HOSP_ID, REFERRAL_HOSP_NAME, '
      'REFERRAL_DEPT_ID, REFERRAL_DEPT_NAME, DOCTOR_ID, DOCTOR_NAME, '
      'CREATOR_ID, CREATOR_NAME, DEPT_ID, DEPT_NAME, CAMPUS_ID, CAMPUS_NAME, '
      'HOSP_ID, HOSP_NAME, CREATE_TIME, UPDATE_TIME '
      'FROM ASD_INITIAL_SCREENING WHERE ID = ? AND HOSP_ID = ?',
      [id, hospId],
    );
    if (result.rows.isEmpty) {
      throw AsdException(400, 40001, '初筛记录不存在：$id');
    }
    return _fromRow(result.rowsAsMaps.first);
  }

  /// 校验儿童档案存在且属本院（初筛记录挂靠本院儿童）。
  Future<void> _requireChild(String childId, String hospId) async {
    final result = await _db.query('SELECT ID FROM CHILD_INFO WHERE ID = ? AND HOSP_ID = ?', [childId, hospId]);
    if (result.rows.isEmpty) {
      throw AsdException(400, 40001, '儿童档案不存在：$childId');
    }
  }

  /// 校验检查医生：存在、未停用、USER_TYPE=DOCTOR 且属记录科室（登录
  /// 用户未挂科室时仅校验前项），返回（医生ID, 姓名）。
  Future<({String id, String name})> _requireDoctor(String doctorId, String doctorName, String hospId, String deptId) async {
    final idValue = _required(doctorId, '检查医生', 36);
    final result = await _db.query(
      'SELECT ID, USER_NAME, DEPT_ID FROM SYS_USER '
      'WHERE ID = ? AND HOSP_ID = ? AND USER_TYPE = ? AND (STATUS IS NULL OR STATUS <> ?)',
      [idValue, hospId, 'DOCTOR', '0'],
    );
    if (result.rows.isEmpty) {
      throw const AsdException(400, 40001, '检查医生不存在或不可用');
    }
    final row = result.rowsAsMaps.first;
    final doctorDept = row['DEPT_ID']?.trim() ?? '';
    if (doctorDept.isEmpty || doctorDept != deptId) {
      throw const AsdException(400, 40001, '检查医生与当前科室不符');
    }
    final name = _required(doctorName, '检查医生姓名', _doctorNameMaxLength);
    return (id: idValue, name: name);
  }

  /// 从数据库行解析初筛记录（数值列按需转换）。
  InitialScreening _fromRow(Map<String, String?> row) => InitialScreening(
    id: row['ID'],
    childId: row['CHILD_ID'] ?? '',
    checkDate: row['CHECK_DATE'] ?? '',
    ageYear: int.tryParse(row['AGE_YEAR'] ?? '') ?? 0,
    ageMonth: int.tryParse(row['AGE_MONTH'] ?? '') ?? 0,
    ageDay: int.tryParse(row['AGE_DAY'] ?? '') ?? 0,
    correctedAgeYear: int.tryParse(row['CORRECTED_AGE_YEAR'] ?? ''),
    correctedAgeMonth: int.tryParse(row['CORRECTED_AGE_MONTH'] ?? ''),
    correctedAgeDay: int.tryParse(row['CORRECTED_AGE_DAY'] ?? ''),
    checkMonth: int.tryParse(row['CHECK_MONTH'] ?? '') ?? 0,
    warningSignResult: row['WARNING_SIGN_RESULT'] ?? '',
    languageSocialCommunicationResult: row['LANGUAGE_SOCIAL_COMMUNICATION_RESULT'] ?? '',
    checkResult: row['CHECK_RESULT'] ?? '',
    hasReferral: row['HAS_REFERRAL'] ?? '0',
    referralHospId: row['REFERRAL_HOSP_ID'],
    referralHospName: row['REFERRAL_HOSP_NAME'] ?? '',
    referralDeptId: row['REFERRAL_DEPT_ID'],
    referralDeptName: row['REFERRAL_DEPT_NAME'],
    doctorId: row['DOCTOR_ID'] ?? '',
    doctorName: row['DOCTOR_NAME'] ?? '',
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    deptId: row['DEPT_ID'],
    deptName: row['DEPT_NAME'],
    campusId: row['CAMPUS_ID'],
    campusName: row['CAMPUS_NAME'],
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 从数据库行解析预警征象条目。
  WscmbdItem _itemFromRow(Map<String, String?> row) => WscmbdItem(
    id: int.tryParse(row['ID'] ?? '') ?? 0,
    month: int.tryParse(row['MONTH'] ?? '') ?? 0,
    itemName: row['ITEM_NAME'] ?? '',
    itemType: int.tryParse(row['ITEM_TYPE'] ?? '') ?? 0,
    itemOrder: int.tryParse(row['ITEM_ORDER'] ?? '') ?? 0,
    itemDesc: row['ITEM_DESC'],
  );

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw AsdException(400, 40002, '$label不能为空');
    }
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw AsdException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 必填文本校验（按 UTF-8 字节数校验，与达梦 VARCHAR 按字节计列宽
  /// 精确对齐；中文条目名称 3 字节/字）。
  String _requiredEnc(String? value, String label, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw AsdException(400, 40002, '$label不能为空');
    }
    if (utf8.encode(v).length > maxBytes) {
      throw AsdException(400, 40002, '$label超出长度限制（$maxBytes 字节）');
    }
    return v;
  }

  /// 0/1 布尔列取值校验。
  String _optionalFlag(String? value) {
    final v = value?.trim() ?? '';
    if (!referralFlags.contains(v)) {
      throw AsdException(400, 40002, '有无转诊取值应为 0-无或 1-有：$value');
    }
    return v;
  }

  /// 年龄分段校验（0-127 的整数）。
  int _agePart(int? value, String label) {
    final v = value ?? -1;
    if (v < 0 || v > _ageMaxValue) {
      throw AsdException(400, 40002, '$label应为 0-$_ageMaxValue 的整数');
    }
    return v;
  }

  /// 可空年龄分段校验（纠正年龄三段，超窗口为 null）。
  int? _optionalAgePart(int? value, String label) {
    if (value == null) return null;
    return _agePart(value, label);
  }

  /// 必填日期校验（CHECK_DATE，须为 yyyy-MM-dd）。
  String _requiredDate(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw const AsdException(400, 40002, '检查日期不能为空');
    }
    final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) && DateTime.tryParse(v) != null;
    if (!ok) {
      throw AsdException(400, 40002, '检查日期格式应为 yyyy-MM-dd：$value');
    }
    return v;
  }

  /// 可空 ID 校验：空值归一为 null。
  String? _optionalId(String? id) {
    final v = id?.trim() ?? '';
    if (v.isEmpty) return null;
    return v;
  }
}
