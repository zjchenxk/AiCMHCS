import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/database_gateway.dart';
import 'package:server/utils/field_cipher.dart';

/// 儿童建档业务异常：httpStatus / code / message 直接映射到 HTTP 响应
/// （模式同 DictException / UserException）。
final class ChildException implements Exception {
  /// 构造函数：注入 HTTP 状态码、业务错误码、错误信息。
  const ChildException(this.httpStatus, this.code, this.message);

  /// HTTP 状态码（400 等）。
  final int httpStatus;

  /// 业务错误码（40001 / 40002 等）。
  final int code;

  /// 错误信息（可直接返回给前端）。
  final String message;

  @override
  String toString() => 'ChildException($httpStatus, $code): $message';
}

/// 儿童整档：基本信息 + 扩展信息（可空）+ 监护人列表。
typedef ChildArchive = (ChildInfo, ChildExtInfo?, List<ChildGuardianInfo>);

/// 儿童建档服务：儿童档案的检索、整档装载、新增、修改与删除。
///
/// 经 DatabaseGateway 访问 CHILD_INFO / CHILD_EXT_INFO /
/// CHILD_GUARDIAN_INFO 三表，按医院隔离（HOSP_ID 匹配登录用户所属
/// 医院，由路由层从令牌会话推导后传入，不信任客户端上报；名称含中文
/// 时由达梦网关参数改写自动内联，业务层直接写参数化 SQL）。敏感个人
/// 信息列（姓名/证件号码/联系电话/电子健康卡ID/居住地址详细/出生证号/
/// 监护人姓名证件电话）经 FieldCipher 加密存储并配套 *_HMAC 盲索引列，
/// 写入 seal+mac 成对、读取 open 解密（日志与异常信息不得输出解密后
/// 明文）。CHILD_INFO 的 ID 为自增主键，两库网关无 last-insert-id
/// 通道，新增后按「HOSP_ID+NAME_HMAC+BIRTH_DATE+CREATE_TIME」自然键
/// 回读新行 ID。扩展信息与监护人随整档保存：先删后插全量覆盖（网关
/// 无事务通道、每条语句自动提交，清插非原子——保存中断后重新保存即
/// 自愈，与 SYS_USER_ROLE 全量覆盖同策略）。PATIENT_ID 为 HIS 系统回
/// 写字段，仅新增时可写入、修改时不更新。删除儿童档案时按监护人 →
/// 扩展信息 → 基本信息顺序连带删除。时间列统一 Dart 侧 formatTimestamp
/// 生成后绑定。
class ChildService {
  /// 构造函数：注入数据库网关与字段加密工具。
  ChildService(this._db, this._cipher);

  final DatabaseGateway _db;

  final FieldCipher _cipher;

  /// 新增串行锁尾（进程内排队）：INSERT 与自然键回读之间可能被并发的
  /// 其他新增交错——同院同名同生日同秒建档时回读键完全相同，串行化后
  /// 「回读取最大自增 ID」才能唯一命中刚插入的行（HTTP 事件循环单线程，
  /// 排队仅让新增成对原子，无跨进程需求）。
  Future<void>? _createTail;

  /// 检索结果上限（防止无条件大结果集，页面查询区下拉展示用）。
  static const int searchLimit = 20;

  /// 各字段长度上限（与表列宽对齐）。
  static const int _cardNoMaxLength = 100;
  static const int _patientIdMaxLength = 20;
  static const int _plainPhoneMaxLength = 24;
  static const int _plainCertMaxLength = 24;
  static const int _plainNameMaxLength = 57;
  static const int _healthNoMaxLength = 20;
  static const int _addressPlainMaxLength = 100;
  static const int _addressCodeMaxLength = 20;
  static const int _provinceMaxLength = 50;
  static const int _hospitalMaxLength = 100;
  static const int _creatorNameMaxLength = 30;
  static const int _dictValueMaxLength = 50;
  static const int _defectMaxLength = 500;
  static const int _otherTextMaxLength = 100;
  static const int _deathCauseMaxLength = 200;
  static const int _severityMaxLength = 20;
  static const int _birthHospitalMaxLength = 100;
  static const int _maternalNoMaxLength = 20;
  static const int _guardianRelationMaxLength = 30;
  static const int _employerMaxLength = 100;

  /// 0/1 布尔列合法取值。
  static const Set<String> _flagValues = {'0', '1'};

  /// 过敏史取值（0-无，1-有，2-不详）。
  static const Set<String> _allergyFlagValues = {'0', '1', '2'};

  /// 贫血程度取值（1/2/3，null-不详）。
  static const Set<String> _anemiaSeverityValues = {'1', '2', '3'};

  // ---------------- 查询 ----------------

  /// 多条件精确检索本院儿童档案。
  ///
  /// 至少提供一个查询条件；姓名/证件号码/联系电话经 HMAC 盲索引等值
  /// 匹配（写入与检索同为 trim 后口径，保证可命中），就诊卡号/保健号
  /// 为明文等值匹配，条件之间为「或」关系（主界面搜索框将同一关键词
  /// 同时投给多个条件，命中任一即返回）；单个条件超长时静默跳过（全局
  /// 搜索框场景下不因个别字段超限而整体失败）；按创建时间倒序取前
  /// [searchLimit] 条。
  Future<List<ChildInfo>> search({required String hospId, String? name, String? visitCardNo, String? healthNo, String? certificateNo, String? phone}) async {
    final scope = hospId.trim();
    if (scope.isEmpty) {
      return const [];
    }
    final namePlain = _searchCond(name, _plainNameMaxLength);
    final cardNo = _searchCond(visitCardNo, _cardNoMaxLength);
    final health = _searchCond(healthNo, _healthNoMaxLength);
    final certPlain = _searchCond(certificateNo, _plainCertMaxLength);
    final phonePlain = _searchCond(phone, _plainPhoneMaxLength);
    if (namePlain == null && cardNo == null && health == null && certPlain == null && phonePlain == null) {
      throw const ChildException(400, 40002, '请至少输入姓名、就诊卡号、保健号、证件号码或联系电话中的一个查询条件');
    }

    final conditions = <String>[];
    final params = <Object?>[_toInt(scope, '医院ID')];
    if (namePlain != null) {
      conditions.add('NAME_HMAC = ?');
      params.add(await _cipher.mac(FieldCipher.childNamePurpose, namePlain));
    }
    if (cardNo != null) {
      conditions.add('VISIT_CARD_NO = ?');
      params.add(cardNo);
    }
    if (health != null) {
      conditions.add('HEALTH_NO = ?');
      params.add(health);
    }
    if (certPlain != null) {
      conditions.add('CERTIFICATE_NO_HMAC = ?');
      params.add(await _cipher.mac(FieldCipher.certificateNoPurpose, certPlain));
    }
    if (phonePlain != null) {
      conditions.add('PHONE_HMAC = ?');
      params.add(await _cipher.mac(FieldCipher.childPhonePurpose, phonePlain));
    }

    final result = await _db.query(
      'SELECT ${_childColumns.join(', ')} FROM CHILD_INFO '
      'WHERE HOSP_ID = ? AND (${conditions.join(' OR ')}) '
      'ORDER BY CREATE_TIME DESC, ID DESC',
      params,
    );
    final rows = result.rowsAsMaps;
    final children = <ChildInfo>[];
    for (final row in rows) {
      if (children.length >= searchLimit) break;
      children.add(await _childFromRow(row));
    }
    return children;
  }

  /// 检索条件归一：空值或超长（对密文列即明文字节超限，该字段不可能
  /// 命中）时返回 null 并跳过该条件，不抛错（多条件组合检索容错）。
  String? _searchCond(String? value, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty || utf8.encode(v).length > maxBytes) {
      return null;
    }
    return v;
  }

  /// 装载儿童整档（基本信息 + 扩展信息 + 监护人列表），不存在或非本院
  /// 档案时抛业务异常。
  Future<ChildArchive> load(String id, String hospId) async {
    final child = await _requireChild(id, hospId);
    final idValue = _toInt(id, '儿童ID');
    final ext = await _loadExt(idValue);
    final guardians = await _loadGuardians(idValue);
    return (child, ext, guardians);
  }

  // ---------------- 新增 / 修改 / 删除 ----------------

  /// 新增儿童档案（基本信息 + 可选扩展信息 + 监护人列表），返回整档。
  ///
  /// 归属医院与创建人由路由层从令牌会话推导传入；CHECK_TIME/NAME/SEX/
  /// BIRTH_DATE/三级居住地址/详细地址为必填；敏感字段服务端加密；新增
  /// 后按自然键回读新行 ID，再写入扩展信息与监护人。全程进程内串行
  /// （见 [_createTail]），保证同键并发建档的回读唯一命中刚插入行。
  Future<ChildArchive> create({required ChildInfo child, required String creatorId, required String creatorName, required String hospId, required String hospName, ChildExtInfo? ext, List<ChildGuardianInfo> guardians = const []}) {
    final run =
        _createTail?.then((_) => _create(child: child, ext: ext, guardians: guardians, creatorId: creatorId, creatorName: creatorName, hospId: hospId, hospName: hospName)) ??
        _create(child: child, ext: ext, guardians: guardians, creatorId: creatorId, creatorName: creatorName, hospId: hospId, hospName: hospName);
    _createTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// 新增执行体（经 [create] 串行调度）。
  Future<ChildArchive> _create({required ChildInfo child, required String creatorId, required String creatorName, required String hospId, required String hospName, ChildExtInfo? ext, List<ChildGuardianInfo> guardians = const []}) async {
    final scope = _toInt(hospId, '医院ID');
    final hosp = _required(hospName, '医院名称', _hospitalMaxLength);
    final creatorIdValue = _toInt(creatorId, '创建人ID');
    final creator = _required(creatorName, '创建人姓名', _creatorNameMaxLength);
    final now = formatTimestamp(DateTime.now());

    // 敏感字段先算明文校验值，再加密成对写入
    final namePlain = _requiredEnc(child.name, '姓名', _plainNameMaxLength);
    final ecardPlain = _optionalEnc(child.ecardId, '电子健康卡ID', 124);
    final certPlain = _optionalEnc(child.certificateNo, '证件号码', _plainCertMaxLength);
    final addressPlain = _requiredEnc(child.addressDetails, '居住地址详细', _addressPlainMaxLength);
    final phonePlain = _optionalEnc(child.phone, '联系电话', _plainPhoneMaxLength);

    await _db.execute(
      'INSERT INTO CHILD_INFO (CHECK_TIME, VISIT_CARD_NO, PATIENT_ID, '
      'ECARD_ID, ECARD_ID_HMAC, NAME, NAME_HMAC, SEX, BIRTH_DATE, BIRTH_TIME, '
      'COUNTRY, NATION, CERTIFICATE_TYPE, CERTIFICATE_NO, CERTIFICATE_NO_HMAC, '
      'HEALTH_NO, MCHIS_HEALTH_NO, ADDRESS_PROVINCE, ADDRESS_CITY, '
      'ADDRESS_COUNTY, ADDRESS_TOWN, ADDRESS_VILLAGE, ADDRESS_DETAILS, '
      'ADDRESS_CODE, PHONE, PHONE_HMAC, CREATOR_ID, CREATOR_NAME, HOSP_ID, '
      'HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _requiredDate(child.checkTime, '建档时间'),
        _optional(child.visitCardNo, '就诊卡号', _cardNoMaxLength),
        _optional(child.patientId, '病人ID', _patientIdMaxLength),
        await _cipher.seal(FieldCipher.ecardIdPurpose, ecardPlain),
        await _cipher.mac(FieldCipher.ecardIdPurpose, ecardPlain),
        await _cipher.seal(FieldCipher.childNamePurpose, namePlain),
        await _cipher.mac(FieldCipher.childNamePurpose, namePlain),
        _requiredSex(child.sex),
        _requiredDate(child.birthDate, '出生日期'),
        _optionalTime(child.birthTime, '出生时间'),
        _optional(child.country, '国籍', _dictValueMaxLength),
        _optional(child.nation, '民族', _dictValueMaxLength),
        _optional(child.certificateType, '证件类型', _dictValueMaxLength),
        await _cipher.seal(FieldCipher.certificateNoPurpose, certPlain),
        await _cipher.mac(FieldCipher.certificateNoPurpose, certPlain),
        _optional(child.healthNo, '保健号', _healthNoMaxLength),
        _optional(child.mchisHealthNo, '区域妇幼保健号', _healthNoMaxLength),
        _required(child.addressProvince, '居住地址-省', _provinceMaxLength),
        _required(child.addressCity, '居住地址-市', _provinceMaxLength),
        _required(child.addressCounty, '居住地址-县', _provinceMaxLength),
        _optional(child.addressTown, '居住地址-乡镇街道', _provinceMaxLength),
        _optional(child.addressVillage, '居住地址-村居委会', _provinceMaxLength),
        await _cipher.seal(FieldCipher.addressDetailsPurpose, addressPlain),
        _optional(child.addressCode, '居住地址编码', _addressCodeMaxLength),
        await _cipher.seal(FieldCipher.childPhonePurpose, phonePlain),
        await _cipher.mac(FieldCipher.childPhonePurpose, phonePlain),
        creatorIdValue,
        creator,
        scope,
        hosp,
        now,
      ],
    );
    // 自增 ID 经「医院ID+姓名盲索引+出生日期+创建时间」自然键回读
    // （网关无 last-insert-id 通道）；同秒内同键建档时多行命中，取
    // 最大自增 ID 即本次插入行（配合 [_createTail] 串行保证）。
    final row = await _db.query(
      'SELECT ID FROM CHILD_INFO WHERE HOSP_ID = ? AND NAME_HMAC = ? '
      'AND BIRTH_DATE = ? AND CREATE_TIME = ?',
      [
        scope,
        await _cipher.mac(FieldCipher.childNamePurpose, namePlain),
        _requiredDate(child.birthDate, '出生日期'),
        now,
      ],
    );
    if (row.rows.isEmpty) {
      throw const ChildException(500, 50000, '新增儿童档案后回读失败');
    }
    final ids = row.rows.map((r) => int.parse(r[0]!)).toList()..sort();
    final newIdValue = ids.last;
    await _saveExt(newIdValue, ext, creatorIdValue, creator, scope, hosp);
    await _saveGuardians(newIdValue, guardians, creatorIdValue, creator, scope, hosp);
    return load('$newIdValue', hospId);
  }

  /// 修改儿童档案（整档保存），返回整档。
  ///
  /// 基本信息按入参全量更新（PATIENT_ID 为 HIS 回写字段不可改；归属
  /// 医院/创建人/创建时间不可改，UPDATE_TIME 由本方法统一写入）；扩展
  /// 信息与监护人先删后插全量覆盖（ext 为 null 表示清空扩展信息）。
  Future<ChildArchive> update({required String id, required ChildInfo child, required String hospId, ChildExtInfo? ext, List<ChildGuardianInfo> guardians = const []}) async {
    final current = await _requireChild(id, hospId);
    final idValue = _toInt(id, '儿童ID');
    final scope = _toInt(hospId, '医院ID');
    final creatorIdValue = _toInt(current.creatorId, '创建人ID');
    final creator = _required(current.creatorName, '创建人姓名', _creatorNameMaxLength);
    final hosp = _required(current.hospName, '医院名称', _hospitalMaxLength);

    final namePlain = _requiredEnc(child.name, '姓名', _plainNameMaxLength);
    final ecardPlain = _optionalEnc(child.ecardId, '电子健康卡ID', 124);
    final certPlain = _optionalEnc(child.certificateNo, '证件号码', _plainCertMaxLength);
    final addressPlain = _requiredEnc(child.addressDetails, '居住地址详细', _addressPlainMaxLength);
    final phonePlain = _optionalEnc(child.phone, '联系电话', _plainPhoneMaxLength);

    await _db.execute(
      'UPDATE CHILD_INFO SET CHECK_TIME = ?, VISIT_CARD_NO = ?, '
      'ECARD_ID = ?, ECARD_ID_HMAC = ?, NAME = ?, NAME_HMAC = ?, SEX = ?, '
      'BIRTH_DATE = ?, BIRTH_TIME = ?, COUNTRY = ?, NATION = ?, '
      'CERTIFICATE_TYPE = ?, CERTIFICATE_NO = ?, CERTIFICATE_NO_HMAC = ?, '
      'HEALTH_NO = ?, MCHIS_HEALTH_NO = ?, ADDRESS_PROVINCE = ?, '
      'ADDRESS_CITY = ?, ADDRESS_COUNTY = ?, ADDRESS_TOWN = ?, '
      'ADDRESS_VILLAGE = ?, ADDRESS_DETAILS = ?, ADDRESS_CODE = ?, '
      'PHONE = ?, PHONE_HMAC = ?, UPDATE_TIME = ? '
      'WHERE ID = ? AND HOSP_ID = ?',
      [
        _requiredDate(child.checkTime, '建档时间'),
        _optional(child.visitCardNo, '就诊卡号', _cardNoMaxLength),
        await _cipher.seal(FieldCipher.ecardIdPurpose, ecardPlain),
        await _cipher.mac(FieldCipher.ecardIdPurpose, ecardPlain),
        await _cipher.seal(FieldCipher.childNamePurpose, namePlain),
        await _cipher.mac(FieldCipher.childNamePurpose, namePlain),
        _requiredSex(child.sex),
        _requiredDate(child.birthDate, '出生日期'),
        _optionalTime(child.birthTime, '出生时间'),
        _optional(child.country, '国籍', _dictValueMaxLength),
        _optional(child.nation, '民族', _dictValueMaxLength),
        _optional(child.certificateType, '证件类型', _dictValueMaxLength),
        await _cipher.seal(FieldCipher.certificateNoPurpose, certPlain),
        await _cipher.mac(FieldCipher.certificateNoPurpose, certPlain),
        _optional(child.healthNo, '保健号', _healthNoMaxLength),
        _optional(child.mchisHealthNo, '区域妇幼保健号', _healthNoMaxLength),
        _required(child.addressProvince, '居住地址-省', _provinceMaxLength),
        _required(child.addressCity, '居住地址-市', _provinceMaxLength),
        _required(child.addressCounty, '居住地址-县', _provinceMaxLength),
        _optional(child.addressTown, '居住地址-乡镇街道', _provinceMaxLength),
        _optional(child.addressVillage, '居住地址-村居委会', _provinceMaxLength),
        await _cipher.seal(FieldCipher.addressDetailsPurpose, addressPlain),
        _optional(child.addressCode, '居住地址编码', _addressCodeMaxLength),
        await _cipher.seal(FieldCipher.childPhonePurpose, phonePlain),
        await _cipher.mac(FieldCipher.childPhonePurpose, phonePlain),
        formatTimestamp(DateTime.now()),
        idValue,
        scope,
      ],
    );
    // 扩展信息 / 监护人全量覆盖（先删后插，非原子、中断重保存自愈）
    await _db.execute('DELETE FROM CHILD_GUARDIAN_INFO WHERE CHILD_ID = ?', [idValue]);
    await _db.execute('DELETE FROM CHILD_EXT_INFO WHERE CHILD_ID = ?', [idValue]);
    if (ext != null) {
      await _saveExt(idValue, ext, creatorIdValue, creator, scope, hosp);
    }
    await _saveGuardians(idValue, guardians, creatorIdValue, creator, scope, hosp);
    return load(id, hospId);
  }

  /// 删除儿童档案（连带删除扩展信息与监护人），返回删除行数（0 或 1）。
  Future<int> delete(String id, String hospId) async {
    await _requireChild(id, hospId);
    final idValue = _toInt(id, '儿童ID');
    final scope = _toInt(hospId, '医院ID');
    await _db.execute('DELETE FROM CHILD_GUARDIAN_INFO WHERE CHILD_ID = ?', [idValue]);
    await _db.execute('DELETE FROM CHILD_EXT_INFO WHERE CHILD_ID = ?', [idValue]);
    return _db.execute('DELETE FROM CHILD_INFO WHERE ID = ? AND HOSP_ID = ?', [idValue, scope]);
  }

  // ---------------- 内部辅助 ----------------

  /// CHILD_INFO 查询列清单。
  static const List<String> _childColumns = [
    'ID',
    'CHECK_TIME',
    'VISIT_CARD_NO',
    'PATIENT_ID',
    'ECARD_ID',
    'ECARD_ID_HMAC',
    'NAME',
    'NAME_HMAC',
    'SEX',
    'BIRTH_DATE',
    'BIRTH_TIME',
    'COUNTRY',
    'NATION',
    'CERTIFICATE_TYPE',
    'CERTIFICATE_NO',
    'CERTIFICATE_NO_HMAC',
    'HEALTH_NO',
    'MCHIS_HEALTH_NO',
    'ADDRESS_PROVINCE',
    'ADDRESS_CITY',
    'ADDRESS_COUNTY',
    'ADDRESS_TOWN',
    'ADDRESS_VILLAGE',
    'ADDRESS_DETAILS',
    'ADDRESS_CODE',
    'PHONE',
    'PHONE_HMAC',
    'CREATOR_ID',
    'CREATOR_NAME',
    'HOSP_ID',
    'HOSP_NAME',
    'CREATE_TIME',
    'UPDATE_TIME',
  ];

  /// CHILD_EXT_INFO 查询列清单（业务列顺序与模型字段一一对应）。
  static const List<String> _extColumns = [
    'CHILD_ID',
    'GESTATIONAL_WEEK',
    'GESTATIONAL_DAY',
    'BIRTH_WEIGHT',
    'BIRTH_LENGTH',
    'BIRTH_HEAD_CIRC',
    'GRAVIDITY',
    'PARITY',
    'FETUS_COUNT',
    'BIRTH_ORDER',
    'DELIVERY_METHOD',
    'BIRTH_HOSPITAL',
    'BIRTH_CERTIFICATE_NO',
    'BIRTH_CERTIFICATE_NO_HMAC',
    'APGAR_1',
    'APGAR_5',
    'APGAR_10',
    'HAS_BIRTH_ASPHYXIA',
    'BIRTH_ASPHYXIA_SEVERITY',
    'HAS_INJURY',
    'HAS_INTRACRANIAL_HEMORRHAGE',
    'INTRACRANIAL_HEMORRHAGE_LEVEL',
    'HAS_BIRTH_DEFECT_0_6D',
    'BIRTH_DEFECT_0_6D',
    'OTHER_BIRTH_DEFECT_0_6D',
    'HAS_BIRTH_DEFECT_7_28D',
    'BIRTH_DEFECT_7_28D',
    'OTHER_BIRTH_DEFECT_7_28D',
    'HAS_ALLERGY_HISTORY',
    'ALLERGEN',
    'OTHER_ALLERGEN',
    'IS_SGA',
    'SGA_TYPE',
    'IS_DEAD',
    'DEATH_DATE',
    'DEATH_CAUSE',
    'HAS_SPONTANEOUS_ABORTION_HISTORY',
    'SPONTANEOUS_ABORTION_COUNT',
    'HAS_INDUCED_ABORTION_HISTORY',
    'INDUCED_ABORTION_COUNT',
    'HAS_RECURRENT_ABORTION_HISTORY',
    'RECURRENT_ABORTION_COUNT',
    'HAS_PRETERM_BIRTH_HISTORY',
    'PRETERM_BIRTH_COUNT',
    'HAS_FETAL_DEAD_HISTORY',
    'FETAL_DEAD_COUNT',
    'HAS_STILLBIRTH_HISTORY',
    'STILLBIRTH_COUNT',
    'HAS_FETAL_MALFORMATION_HISTORY',
    'FETAL_MALFORMATION_COUNT',
    'FETAL_MALFORMATION_INFO',
    'OTHER_PREGNANCY_HISTORY',
    'CONCEPTION_METHOD',
    'EXPECTED_DELIVERY_DATE',
    'HAS_ABNORMAL_HBA1C',
    'HAS_HBA1C_GE_5_5',
    'HAS_HBA1C_GE_6_5',
    'HAS_DIABETES',
    'HAS_DIABETES_MEDICATION',
    'HAS_GESTATIONAL_HYPERTENSION',
    'HAS_ANEMIA',
    'ANEMIA_SEVERITY',
    'HAS_CMV_INFECTION',
    'HAS_RUBELLA_INFECTION',
    'HAS_MACROSOMIA',
    'HAS_POLYHYDRAMNIOS',
    'HAS_OLIGOHYDRAMNIOS',
    'HAS_HYPERTHYROIDISM_IN_PREGNANCY',
    'HAS_HYPOTHYROIDISM_IN_PREGNANCY',
    'HAS_PREECLAMPSIA',
    'HAS_ECLAMPSIA',
    'HAS_HIV_INFECTION',
    'HAS_SYPHILIS_INFECTION',
    'OTHER_DISEASES_IN_PREGNANCY',
    'HAS_PARENTAL_MENTAL_ILLNESS_HISTORY',
    'HAS_PARENTAL_DRUG_ABUSE_HISTORY',
    'HAS_FAMILY_HEARING_LOSS_HISTORY',
    'HAS_PARENTAL_CONSANGUINEOUS_MARRIAGE',
    'OTHER_FAMILY_HISTORY',
    'MATERNAL_INPATIENT_NO',
    'MATERNAL_AGE_AT_DELIVERY',
    'CREATOR_ID',
    'CREATOR_NAME',
    'HOSP_ID',
    'HOSP_NAME',
    'CREATE_TIME',
    'UPDATE_TIME',
  ];

  /// CHILD_GUARDIAN_INFO 查询列清单。
  static const List<String> _guardianColumns = [
    'ID',
    'CHILD_ID',
    'NAME',
    'NAME_HMAC',
    'BIRTH_DATE',
    'CERTIFICATE_TYPE',
    'CERTIFICATE_NO',
    'CERTIFICATE_NO_HMAC',
    'COUNTRY',
    'NATION',
    'EDUCATION_LEVEL',
    'OCCUPATION',
    'PHONE',
    'PHONE_HMAC',
    'HEIGHT',
    'WEIGHT',
    'EMPLOYER',
    'GUARDIAN_RELATIONSHIP',
    'GUARDIAN_ORDER',
    'CREATOR_ID',
    'CREATOR_NAME',
    'HOSP_ID',
    'HOSP_NAME',
    'CREATE_TIME',
    'UPDATE_TIME',
  ];

  /// 按本院范围查儿童基本信息行，不存在时抛业务异常。
  Future<ChildInfo> _requireChild(String id, String hospId) async {
    final result = await _db.query(
      'SELECT ${_childColumns.join(', ')} FROM CHILD_INFO WHERE ID = ? AND HOSP_ID = ?',
      [_toInt(id, '儿童ID'), _toInt(hospId, '医院ID')],
    );
    if (result.rows.isEmpty) {
      throw ChildException(400, 40001, '儿童档案不存在：$id');
    }
    return _childFromRow(result.rowsAsMaps.first);
  }

  /// 装载扩展信息（无行返回 null）。
  Future<ChildExtInfo?> _loadExt(int childId) async {
    final result = await _db.query(
      'SELECT ${_extColumns.join(', ')} FROM CHILD_EXT_INFO WHERE CHILD_ID = ?',
      [childId],
    );
    if (result.rows.isEmpty) {
      return null;
    }
    final row = result.rowsAsMaps.first;
    final birthCertPlain = await _cipher.open(FieldCipher.birthCertificateNoPurpose, row['BIRTH_CERTIFICATE_NO']);
    return _extFromRow(row, birthCertPlain);
  }

  /// 装载监护人列表（按创建顺序）。
  Future<List<ChildGuardianInfo>> _loadGuardians(int childId) async {
    final result = await _db.query(
      'SELECT ${_guardianColumns.join(', ')} FROM CHILD_GUARDIAN_INFO WHERE CHILD_ID = ? ORDER BY ID',
      [childId],
    );
    final guardians = <ChildGuardianInfo>[];
    for (final row in result.rowsAsMaps) {
      final namePlain = await _cipher.open(FieldCipher.guardianNamePurpose, row['NAME']);
      final certPlain = await _cipher.open(FieldCipher.guardianCertificateNoPurpose, row['CERTIFICATE_NO']);
      final phonePlain = await _cipher.open(FieldCipher.guardianPhonePurpose, row['PHONE']);
      guardians.add(_guardianFromRow(row, namePlain, certPlain, phonePlain));
    }
    return guardians;
  }

  /// 覆盖保存扩展信息（INSERT；调用方负责先删旧行）。
  Future<void> _saveExt(int childId, ChildExtInfo? ext, int creatorId, String creator, int hospId, String hospName) async {
    if (ext == null) {
      return;
    }
    final birthCertPlain = _optionalEnc(ext.birthCertificateNo, '出生证号', _plainCertMaxLength);
    await _db.execute(
      'INSERT INTO CHILD_EXT_INFO (CHILD_ID, GESTATIONAL_WEEK, '
      'GESTATIONAL_DAY, BIRTH_WEIGHT, BIRTH_LENGTH, BIRTH_HEAD_CIRC, '
      'GRAVIDITY, PARITY, FETUS_COUNT, BIRTH_ORDER, DELIVERY_METHOD, '
      'BIRTH_HOSPITAL, BIRTH_CERTIFICATE_NO, BIRTH_CERTIFICATE_NO_HMAC, '
      'APGAR_1, APGAR_5, APGAR_10, HAS_BIRTH_ASPHYXIA, '
      'BIRTH_ASPHYXIA_SEVERITY, HAS_INJURY, HAS_INTRACRANIAL_HEMORRHAGE, '
      'INTRACRANIAL_HEMORRHAGE_LEVEL, HAS_BIRTH_DEFECT_0_6D, '
      'BIRTH_DEFECT_0_6D, OTHER_BIRTH_DEFECT_0_6D, HAS_BIRTH_DEFECT_7_28D, '
      'BIRTH_DEFECT_7_28D, OTHER_BIRTH_DEFECT_7_28D, HAS_ALLERGY_HISTORY, '
      'ALLERGEN, OTHER_ALLERGEN, IS_SGA, SGA_TYPE, IS_DEAD, DEATH_DATE, '
      'DEATH_CAUSE, HAS_SPONTANEOUS_ABORTION_HISTORY, '
      'SPONTANEOUS_ABORTION_COUNT, HAS_INDUCED_ABORTION_HISTORY, '
      'INDUCED_ABORTION_COUNT, HAS_RECURRENT_ABORTION_HISTORY, '
      'RECURRENT_ABORTION_COUNT, HAS_PRETERM_BIRTH_HISTORY, '
      'PRETERM_BIRTH_COUNT, HAS_FETAL_DEAD_HISTORY, FETAL_DEAD_COUNT, '
      'HAS_STILLBIRTH_HISTORY, STILLBIRTH_COUNT, '
      'HAS_FETAL_MALFORMATION_HISTORY, FETAL_MALFORMATION_COUNT, '
      'FETAL_MALFORMATION_INFO, OTHER_PREGNANCY_HISTORY, CONCEPTION_METHOD, '
      'EXPECTED_DELIVERY_DATE, HAS_ABNORMAL_HBA1C, HAS_HBA1C_GE_5_5, '
      'HAS_HBA1C_GE_6_5, HAS_DIABETES, HAS_DIABETES_MEDICATION, '
      'HAS_GESTATIONAL_HYPERTENSION, HAS_ANEMIA, ANEMIA_SEVERITY, '
      'HAS_CMV_INFECTION, HAS_RUBELLA_INFECTION, HAS_MACROSOMIA, '
      'HAS_POLYHYDRAMNIOS, HAS_OLIGOHYDRAMNIOS, '
      'HAS_HYPERTHYROIDISM_IN_PREGNANCY, HAS_HYPOTHYROIDISM_IN_PREGNANCY, '
      'HAS_PREECLAMPSIA, HAS_ECLAMPSIA, HAS_HIV_INFECTION, '
      'HAS_SYPHILIS_INFECTION, OTHER_DISEASES_IN_PREGNANCY, '
      'HAS_PARENTAL_MENTAL_ILLNESS_HISTORY, HAS_PARENTAL_DRUG_ABUSE_HISTORY, '
      'HAS_FAMILY_HEARING_LOSS_HISTORY, HAS_PARENTAL_CONSANGUINEOUS_MARRIAGE, '
      'OTHER_FAMILY_HISTORY, MATERNAL_INPATIENT_NO, MATERNAL_AGE_AT_DELIVERY, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (${List.filled(86, '?').join(', ')})',
      [
        childId,
        _optionalSmall(ext.gestationalWeek, '出生孕周'),
        _optionalSmall(ext.gestationalDay, '出生孕天'),
        _optionalSmall(ext.birthWeight, '出生体重'),
        _optionalDecimal(ext.birthLength, '出生身长'),
        _optionalDecimal(ext.birthHeadCirc, '出生头围'),
        _optionalSmall(ext.gravidity, '孕次'),
        _optionalSmall(ext.parity, '产次'),
        _optionalSmall(ext.fetusCount, '胎数'),
        _optionalSmall(ext.birthOrder, '出生顺序'),
        _optional(ext.deliveryMethod, '分娩方式', _dictValueMaxLength),
        _optional(ext.birthHospital, '出生医院', _birthHospitalMaxLength),
        await _cipher.seal(FieldCipher.birthCertificateNoPurpose, birthCertPlain),
        await _cipher.mac(FieldCipher.birthCertificateNoPurpose, birthCertPlain),
        _optionalApgar(ext.apgar1, 'Apgar评分-1分钟'),
        _optionalApgar(ext.apgar5, 'Apgar评分-5分钟'),
        _optionalApgar(ext.apgar10, 'Apgar评分-10分钟'),
        _optionalFlag(ext.hasBirthAsphyxia, '有无出生窒息', _flagValues),
        _optional(ext.birthAsphyxiaSeverity, '出生窒息程度', _severityMaxLength),
        _optionalFlag(ext.hasInjury, '有无产伤', _flagValues),
        _optionalFlag(ext.hasIntracranialHemorrhage, '有无颅内出血', _flagValues),
        _optional(ext.intracranialHemorrhageLevel, '颅内出血级别', _severityMaxLength),
        _optionalFlag(ext.hasBirthDefect06d, '0-6天内是否有出生缺陷', _flagValues),
        _optional(ext.birthDefect06d, '0-6天内出生缺陷', _defectMaxLength),
        _optional(ext.otherBirthDefect06d, '0-6天内其他出生缺陷', _otherTextMaxLength),
        _optionalFlag(ext.hasBirthDefect728d, '7-28天内是否有出生缺陷', _flagValues),
        _optional(ext.birthDefect728d, '7-28天内出生缺陷', _defectMaxLength),
        _optional(ext.otherBirthDefect728d, '7-28天内其他出生缺陷', _otherTextMaxLength),
        _optionalFlag(ext.hasAllergyHistory, '有无过敏史', _allergyFlagValues),
        _optional(ext.allergen, '过敏原', _defectMaxLength),
        _optional(ext.otherAllergen, '其他过敏原', _otherTextMaxLength),
        _optionalFlag(ext.isSga, '是否小于胎龄儿', _flagValues),
        _optional(ext.sgaType, 'SGA分型', _severityMaxLength),
        _optionalFlag(ext.isDead, '是否死亡', _flagValues),
        _optionalDate(ext.deathDate, '儿童死亡日期'),
        _optional(ext.deathCause, '儿童死亡原因', _deathCauseMaxLength),
        _optionalFlag(ext.hasSpontaneousAbortionHistory, '有无自然流产', _flagValues),
        _optionalSmall(ext.spontaneousAbortionCount, '自然流产次数'),
        _optionalFlag(ext.hasInducedAbortionHistory, '有无人工流产', _flagValues),
        _optionalSmall(ext.inducedAbortionCount, '人工流产次数'),
        _optionalFlag(ext.hasRecurrentAbortionHistory, '有无习惯性流产', _flagValues),
        _optionalSmall(ext.recurrentAbortionCount, '习惯性流产次数'),
        _optionalFlag(ext.hasPretermBirthHistory, '有无早产', _flagValues),
        _optionalSmall(ext.pretermBirthCount, '早产次数'),
        _optionalFlag(ext.hasFetalDeadHistory, '有无死胎', _flagValues),
        _optionalSmall(ext.fetalDeadCount, '死胎次数'),
        _optionalFlag(ext.hasStillbirthHistory, '有无死产', _flagValues),
        _optionalSmall(ext.stillbirthCount, '死产次数'),
        _optionalFlag(ext.hasFetalMalformationHistory, '有无胎儿畸形', _flagValues),
        _optionalSmall(ext.fetalMalformationCount, '胎儿畸形次数'),
        _optional(ext.fetalMalformationInfo, '胎儿畸形情况', _otherTextMaxLength),
        _optional(ext.otherPregnancyHistory, '母亲孕产史-其他情况', _defectMaxLength),
        _optional(ext.conceptionMethod, '受孕方式', _dictValueMaxLength),
        _optionalDate(ext.expectedDeliveryDate, '预产期'),
        _optionalFlag(ext.hasAbnormalHba1c, '糖化血红蛋白有无异常', _flagValues),
        _optionalFlag(ext.hasHba1cGe55, '糖化血红蛋白有无＞5.5%', _flagValues),
        _optionalFlag(ext.hasHba1cGe65, '糖化血红蛋白有无＞6.5%', _flagValues),
        _optionalFlag(ext.hasDiabetes, '有无糖尿病', _flagValues),
        _optionalFlag(ext.hasDiabetesMedication, '糖尿病是否需要药物治疗', _flagValues),
        _optionalFlag(ext.hasGestationalHypertension, '有无妊娠期高血压', _flagValues),
        _optionalFlag(ext.hasAnemia, '有无贫血', _flagValues),
        _optionalFlag(ext.anemiaSeverity, '贫血程度', _anemiaSeverityValues),
        _optionalFlag(ext.hasCmvInfection, '有无巨细胞病毒感染', _flagValues),
        _optionalFlag(ext.hasRubellaInfection, '有无风疹病毒感染', _flagValues),
        _optionalFlag(ext.hasMacrosomia, '有无巨大儿', _flagValues),
        _optionalFlag(ext.hasPolyhydramnios, '有无羊水过多', _flagValues),
        _optionalFlag(ext.hasOligohydramnios, '有无羊水过少', _flagValues),
        _optionalFlag(ext.hasHyperthyroidismInPregnancy, '有无妊娠合并甲亢', _flagValues),
        _optionalFlag(ext.hasHypothyroidismInPregnancy, '有无妊娠合并甲减', _flagValues),
        _optionalFlag(ext.hasPreeclampsia, '有无子痫前期', _flagValues),
        _optionalFlag(ext.hasEclampsia, '有无子痫', _flagValues),
        _optionalFlag(ext.hasHivInfection, '有无HIV感染', _flagValues),
        _optionalFlag(ext.hasSyphilisInfection, '有无梅毒感染', _flagValues),
        _optional(ext.otherDiseasesInPregnancy, '母亲孕期情况-其他疾病', _defectMaxLength),
        _optionalFlag(ext.hasParentalMentalIllnessHistory, '父母亲有无精神病史', _flagValues),
        _optionalFlag(ext.hasParentalDrugAbuseHistory, '父母亲有无吸毒史', _flagValues),
        _optionalFlag(ext.hasFamilyHearingLossHistory, '父母及同胞有无耳聋及听力损失史', _flagValues),
        _optionalFlag(ext.hasParentalConsanguineousMarriage, '父母亲是否近亲结婚', _flagValues),
        _optional(ext.otherFamilyHistory, '家族史-其他情况', _defectMaxLength),
        _optional(ext.maternalInpatientNo, '母亲住院号', _maternalNoMaxLength),
        _optionalSmall(ext.maternalAgeAtDelivery, '母亲生育年龄'),
        creatorId,
        creator,
        hospId,
        hospName,
        formatTimestamp(DateTime.now()),
      ],
    );
  }

  /// 全量覆盖保存监护人列表（INSERT 逐条；调用方负责先删旧行）。
  Future<void> _saveGuardians(int childId, List<ChildGuardianInfo> guardians, int creatorId, String creator, int hospId, String hospName) async {
    for (final guardian in guardians) {
      final namePlain = _requiredEnc(guardian.name, '监护人姓名', _plainNameMaxLength);
      final certPlain = _optionalEnc(guardian.certificateNo, '监护人证件号码', _plainCertMaxLength);
      final phonePlain = _optionalEnc(guardian.phone, '监护人联系电话', _plainPhoneMaxLength);
      await _db.execute(
        'INSERT INTO CHILD_GUARDIAN_INFO (CHILD_ID, NAME, NAME_HMAC, '
        'BIRTH_DATE, CERTIFICATE_TYPE, CERTIFICATE_NO, CERTIFICATE_NO_HMAC, '
        'COUNTRY, NATION, EDUCATION_LEVEL, OCCUPATION, PHONE, PHONE_HMAC, '
        'HEIGHT, WEIGHT, EMPLOYER, GUARDIAN_RELATIONSHIP, GUARDIAN_ORDER, '
        'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          childId,
          await _cipher.seal(FieldCipher.guardianNamePurpose, namePlain),
          await _cipher.mac(FieldCipher.guardianNamePurpose, namePlain),
          _optionalDate(guardian.birthDate, '监护人出生日期'),
          _optional(guardian.certificateType, '监护人证件类型', _dictValueMaxLength),
          await _cipher.seal(FieldCipher.guardianCertificateNoPurpose, certPlain),
          await _cipher.mac(FieldCipher.guardianCertificateNoPurpose, certPlain),
          _optional(guardian.country, '监护人国籍', _dictValueMaxLength),
          _optional(guardian.nation, '监护人民族', _dictValueMaxLength),
          _optional(guardian.educationLevel, '文化程度', _dictValueMaxLength),
          _optional(guardian.occupation, '职业', _dictValueMaxLength),
          await _cipher.seal(FieldCipher.guardianPhonePurpose, phonePlain),
          await _cipher.mac(FieldCipher.guardianPhonePurpose, phonePlain),
          _optionalDecimal(guardian.height, '监护人身高'),
          _optionalDecimal(guardian.weight, '监护人体重'),
          _optional(guardian.employer, '工作单位', _employerMaxLength),
          _required(guardian.guardianRelationship, '监护人与儿童关系', _guardianRelationMaxLength),
          _optionalGuardianOrder(guardian.guardianOrder),
          creatorId,
          creator,
          hospId,
          hospName,
          formatTimestamp(DateTime.now()),
        ],
      );
    }
  }

  /// 从数据库行解析儿童基本信息（敏感列解密为明文，仅用于协议下发）。
  Future<ChildInfo> _childFromRow(Map<String, String?> row) async {
    final namePlain = await _cipher.open(FieldCipher.childNamePurpose, row['NAME']);
    final ecardPlain = await _cipher.open(FieldCipher.ecardIdPurpose, row['ECARD_ID']);
    final certPlain = await _cipher.open(FieldCipher.certificateNoPurpose, row['CERTIFICATE_NO']);
    final addressPlain = await _cipher.open(FieldCipher.addressDetailsPurpose, row['ADDRESS_DETAILS']);
    final phonePlain = await _cipher.open(FieldCipher.childPhonePurpose, row['PHONE']);
    return ChildInfo(
      id: row['ID'] ?? '',
      checkTime: row['CHECK_TIME'] ?? '',
      visitCardNo: row['VISIT_CARD_NO'],
      patientId: row['PATIENT_ID'],
      ecardId: ecardPlain,
      name: namePlain ?? '',
      sex: row['SEX'] ?? '',
      birthDate: row['BIRTH_DATE'] ?? '',
      birthTime: row['BIRTH_TIME'],
      country: row['COUNTRY'],
      nation: row['NATION'],
      certificateType: row['CERTIFICATE_TYPE'],
      certificateNo: certPlain,
      healthNo: row['HEALTH_NO'],
      mchisHealthNo: row['MCHIS_HEALTH_NO'],
      addressProvince: row['ADDRESS_PROVINCE'] ?? '',
      addressCity: row['ADDRESS_CITY'] ?? '',
      addressCounty: row['ADDRESS_COUNTY'] ?? '',
      addressTown: row['ADDRESS_TOWN'],
      addressVillage: row['ADDRESS_VILLAGE'],
      addressDetails: addressPlain ?? '',
      addressCode: row['ADDRESS_CODE'],
      phone: phonePlain,
      creatorId: row['CREATOR_ID'] ?? '',
      creatorName: row['CREATOR_NAME'] ?? '',
      hospId: row['HOSP_ID'] ?? '',
      hospName: row['HOSP_NAME'] ?? '',
      createTime: row['CREATE_TIME'],
      updateTime: row['UPDATE_TIME'],
    );
  }

  /// 从数据库行解析扩展信息（birthCertificatePlain 为调用方解密后的明文）。
  ChildExtInfo _extFromRow(Map<String, String?> row, String? birthCertificatePlain) => ChildExtInfo(
    childId: row['CHILD_ID'] ?? '',
    gestationalWeek: row['GESTATIONAL_WEEK'],
    gestationalDay: row['GESTATIONAL_DAY'],
    birthWeight: row['BIRTH_WEIGHT'],
    birthLength: row['BIRTH_LENGTH'],
    birthHeadCirc: row['BIRTH_HEAD_CIRC'],
    gravidity: row['GRAVIDITY'],
    parity: row['PARITY'],
    fetusCount: row['FETUS_COUNT'],
    birthOrder: row['BIRTH_ORDER'],
    deliveryMethod: row['DELIVERY_METHOD'],
    birthHospital: row['BIRTH_HOSPITAL'],
    birthCertificateNo: birthCertificatePlain,
    apgar1: row['APGAR_1'],
    apgar5: row['APGAR_5'],
    apgar10: row['APGAR_10'],
    hasBirthAsphyxia: row['HAS_BIRTH_ASPHYXIA'],
    birthAsphyxiaSeverity: row['BIRTH_ASPHYXIA_SEVERITY'],
    hasInjury: row['HAS_INJURY'],
    hasIntracranialHemorrhage: row['HAS_INTRACRANIAL_HEMORRHAGE'],
    intracranialHemorrhageLevel: row['INTRACRANIAL_HEMORRHAGE_LEVEL'],
    hasBirthDefect06d: row['HAS_BIRTH_DEFECT_0_6D'],
    birthDefect06d: row['BIRTH_DEFECT_0_6D'],
    otherBirthDefect06d: row['OTHER_BIRTH_DEFECT_0_6D'],
    hasBirthDefect728d: row['HAS_BIRTH_DEFECT_7_28D'],
    birthDefect728d: row['BIRTH_DEFECT_7_28D'],
    otherBirthDefect728d: row['OTHER_BIRTH_DEFECT_7_28D'],
    hasAllergyHistory: row['HAS_ALLERGY_HISTORY'],
    allergen: row['ALLERGEN'],
    otherAllergen: row['OTHER_ALLERGEN'],
    isSga: row['IS_SGA'],
    sgaType: row['SGA_TYPE'],
    isDead: row['IS_DEAD'],
    deathDate: row['DEATH_DATE'],
    deathCause: row['DEATH_CAUSE'],
    hasSpontaneousAbortionHistory: row['HAS_SPONTANEOUS_ABORTION_HISTORY'],
    spontaneousAbortionCount: row['SPONTANEOUS_ABORTION_COUNT'],
    hasInducedAbortionHistory: row['HAS_INDUCED_ABORTION_HISTORY'],
    inducedAbortionCount: row['INDUCED_ABORTION_COUNT'],
    hasRecurrentAbortionHistory: row['HAS_RECURRENT_ABORTION_HISTORY'],
    recurrentAbortionCount: row['RECURRENT_ABORTION_COUNT'],
    hasPretermBirthHistory: row['HAS_PRETERM_BIRTH_HISTORY'],
    pretermBirthCount: row['PRETERM_BIRTH_COUNT'],
    hasFetalDeadHistory: row['HAS_FETAL_DEAD_HISTORY'],
    fetalDeadCount: row['FETAL_DEAD_COUNT'],
    hasStillbirthHistory: row['HAS_STILLBIRTH_HISTORY'],
    stillbirthCount: row['STILLBIRTH_COUNT'],
    hasFetalMalformationHistory: row['HAS_FETAL_MALFORMATION_HISTORY'],
    fetalMalformationCount: row['FETAL_MALFORMATION_COUNT'],
    fetalMalformationInfo: row['FETAL_MALFORMATION_INFO'],
    otherPregnancyHistory: row['OTHER_PREGNANCY_HISTORY'],
    conceptionMethod: row['CONCEPTION_METHOD'],
    expectedDeliveryDate: row['EXPECTED_DELIVERY_DATE'],
    hasAbnormalHba1c: row['HAS_ABNORMAL_HBA1C'],
    hasHba1cGe55: row['HAS_HBA1C_GE_5_5'],
    hasHba1cGe65: row['HAS_HBA1C_GE_6_5'],
    hasDiabetes: row['HAS_DIABETES'],
    hasDiabetesMedication: row['HAS_DIABETES_MEDICATION'],
    hasGestationalHypertension: row['HAS_GESTATIONAL_HYPERTENSION'],
    hasAnemia: row['HAS_ANEMIA'],
    anemiaSeverity: row['ANEMIA_SEVERITY'],
    hasCmvInfection: row['HAS_CMV_INFECTION'],
    hasRubellaInfection: row['HAS_RUBELLA_INFECTION'],
    hasMacrosomia: row['HAS_MACROSOMIA'],
    hasPolyhydramnios: row['HAS_POLYHYDRAMNIOS'],
    hasOligohydramnios: row['HAS_OLIGOHYDRAMNIOS'],
    hasHyperthyroidismInPregnancy: row['HAS_HYPERTHYROIDISM_IN_PREGNANCY'],
    hasHypothyroidismInPregnancy: row['HAS_HYPOTHYROIDISM_IN_PREGNANCY'],
    hasPreeclampsia: row['HAS_PREECLAMPSIA'],
    hasEclampsia: row['HAS_ECLAMPSIA'],
    hasHivInfection: row['HAS_HIV_INFECTION'],
    hasSyphilisInfection: row['HAS_SYPHILIS_INFECTION'],
    otherDiseasesInPregnancy: row['OTHER_DISEASES_IN_PREGNANCY'],
    hasParentalMentalIllnessHistory: row['HAS_PARENTAL_MENTAL_ILLNESS_HISTORY'],
    hasParentalDrugAbuseHistory: row['HAS_PARENTAL_DRUG_ABUSE_HISTORY'],
    hasFamilyHearingLossHistory: row['HAS_FAMILY_HEARING_LOSS_HISTORY'],
    hasParentalConsanguineousMarriage: row['HAS_PARENTAL_CONSANGUINEOUS_MARRIAGE'],
    otherFamilyHistory: row['OTHER_FAMILY_HISTORY'],
    maternalInpatientNo: row['MATERNAL_INPATIENT_NO'],
    maternalAgeAtDelivery: row['MATERNAL_AGE_AT_DELIVERY'],
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 从数据库行解析监护人（姓名/证件/电话为调用方解密后的明文）。
  ChildGuardianInfo _guardianFromRow(Map<String, String?> row, String? namePlain, String? certPlain, String? phonePlain) => ChildGuardianInfo(
    id: row['ID'],
    childId: row['CHILD_ID'] ?? '',
    name: namePlain ?? '',
    birthDate: row['BIRTH_DATE'],
    certificateType: row['CERTIFICATE_TYPE'],
    certificateNo: certPlain,
    country: row['COUNTRY'],
    nation: row['NATION'],
    educationLevel: row['EDUCATION_LEVEL'],
    occupation: row['OCCUPATION'],
    phone: phonePlain,
    height: row['HEIGHT'],
    weight: row['WEIGHT'],
    employer: row['EMPLOYER'],
    guardianRelationship: row['GUARDIAN_RELATIONSHIP'] ?? '',
    guardianOrder: row['GUARDIAN_ORDER'],
    creatorId: row['CREATOR_ID'] ?? '',
    creatorName: row['CREATOR_NAME'] ?? '',
    hospId: row['HOSP_ID'] ?? '',
    hospName: row['HOSP_NAME'] ?? '',
    createTime: row['CREATE_TIME'],
    updateTime: row['UPDATE_TIME'],
  );

  /// 必填字符串校验：去空格、非空、不超长。
  String _required(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw ChildException(400, 40002, '$label不能为空');
    }
    return _optional(v, label, maxLength)!;
  }

  /// 可空字符串校验：空值归一为 null，非空时不超长。
  String? _optional(String? value, String label, int maxLength) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > maxLength) {
      throw ChildException(400, 40002, '$label不能超过 $maxLength 个字符');
    }
    return v;
  }

  /// 必填密文列明文校验：去空格、非空、UTF-8 字节数不超上限
  /// （密文列宽 = 明文最大字节数 × 1.5 + 64，按字节校验与列宽对齐）。
  String _requiredEnc(String? value, String label, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw ChildException(400, 40002, '$label不能为空');
    }
    return _optionalEnc(v, label, maxBytes)!;
  }

  /// 可空密文列明文校验：空值归一为 null，非空时 UTF-8 字节数不超上限。
  String? _optionalEnc(String? value, String label, int maxBytes) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (utf8.encode(v).length > maxBytes) {
      throw ChildException(400, 40002, '$label超出长度限制（$maxBytes 字节）');
    }
    return v;
  }

  /// 必填性别校验：限 1-男、2-女。
  String _requiredSex(String? value) {
    final v = value?.trim() ?? '';
    if (v != '1' && v != '2') {
      throw ChildException(400, 40002, '性别应为 1-男、2-女：$value');
    }
    return v;
  }

  /// 0/1 布尔列取值校验（allowed 传入合法集）。
  String? _optionalFlag(String? value, String label, Set<String> allowed) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!allowed.contains(v)) {
      throw ChildException(400, 40002, '$label取值不合法：$value');
    }
    return v;
  }

  /// 可空日期校验：空值归一为 null，非空时须为可解析的 yyyy-MM-dd。
  String? _optionalDate(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) || DateTime.tryParse(v) == null) {
      throw ChildException(400, 40002, '$label格式应为 yyyy-MM-dd：$value');
    }
    return v;
  }

  /// 必填日期/时间校验（CHECK_TIME 等 DATETIME 列，接受
  /// yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss）。
  String _requiredDate(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      throw ChildException(400, 40002, '$label不能为空');
    }
    final ok = RegExp(r'^\d{4}-\d{2}-\d{2}( \d{2}:\d{2}(:\d{2})?)?$').hasMatch(v) && DateTime.tryParse(v) != null;
    if (!ok) {
      throw ChildException(400, 40002, '$label格式不正确：$value');
    }
    return v;
  }

  /// 可空出生时间校验：限 HH:mm 或 HH:mm:ss。
  String? _optionalTime(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(v)) {
      throw ChildException(400, 40002, '$label格式应为 HH:mm：$value');
    }
    return v;
  }

  /// 可空小整数校验（SMALLINT 列，0-32767）。
  String? _optionalSmall(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 0 || n > 32767) {
      throw ChildException(400, 40002, '$label应为 0-32767 的整数：$value');
    }
    return v;
  }

  /// 可空小数校验（DECIMAL(5,1) 列，0-9999.9），字符串原样绑定。
  String? _optionalDecimal(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = double.tryParse(v);
    if (n == null || n < 0 || n > 9999.9) {
      throw ChildException(400, 40002, '$label应为 0-9999.9 的数值：$value');
    }
    return v;
  }

  /// 可空 Apgar 评分校验（0-10 的整数）。
  String? _optionalApgar(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 0 || n > 10) {
      throw ChildException(400, 40002, '$label应为 0-10 的整数：$value');
    }
    return v;
  }

  /// 可空监护人顺序校验：限 1-第一监护人、2-第二监护人。
  String? _optionalGuardianOrder(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v != '1' && v != '2') {
      throw ChildException(400, 40002, '监护人顺序应为 1-第一监护人、2-第二监护人：$value');
    }
    return v;
  }

  /// 数字 ID 字符串转 int（网关列值均为字符串，绑定 int 避免两库隐式
  /// 转换差异）。
  int _toInt(String id, String label) {
    final v = int.tryParse(id.trim());
    if (v == null) {
      throw ChildException(400, 40002, '$label格式不正确：$id');
    }
    return v;
  }
}
