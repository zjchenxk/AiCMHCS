import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/child_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

/// 36 位标准 UUID v7 断言（时间位版本 7、合法变体位）。
Matcher matchesRegexpUuid() => matches(
  RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
);

/// 儿童建档服务集成测试（SQLite :memory:）：新增整档（敏感字段加密落库
/// + 应用侧 UUID v7 主键前置生成）、整档装载解密、姓名盲索引/就诊卡号/保健号检索、
/// 医院隔离、修改（病人ID不可改、扩展信息与监护人全量覆盖）、删除级联
/// 与必填/格式校验。
void main() {
  late SqliteGateway db;
  late ChildService service;

  // 测试密钥固定 32 字节（与迁移 dataFix 测试同口径），保证可复现解密。
  final cipher = FieldCipher.fromMasterKeyBase64(base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')));

  ChildInfo buildChild({
    String name = '王小明',
    String? visitCardNo = 'JZK202601001',
    String? patientId,
    String? ecardId = 'EC123456',
    String sex = '1',
    String? certificateNo = '110101202601011234',
    String? phone = '13800138000',
    String? healthNo = 'H0001',
    String addressDetails = '景山前街4号',
    String checkTime = '2026-11-14',
    String birthDate = '2026-01-01',
  }) => ChildInfo(
    id: '',
    checkTime: checkTime,
    visitCardNo: visitCardNo,
    patientId: patientId,
    ecardId: ecardId,
    name: name,
    sex: sex,
    birthDate: birthDate,
    birthTime: '08:30',
    country: '中国',
    nation: '汉族',
    certificateType: '居民身份证',
    certificateNo: certificateNo,
    healthNo: healthNo,
    addressProvince: '北京市',
    addressCity: '北京市',
    addressCounty: '东城区',
    addressTown: '景山街道',
    addressVillage: '景山社区',
    addressDetails: addressDetails,
    addressCode: '110101',
    phone: phone,
    creatorId: '',
    creatorName: '',
    hospId: '',
    hospName: '',
  );

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    // 建表语句与 v15/v17 迁移 SQLite 段一致（TEXT 主键 + 科室/院区
    // 归属列，测试只建所需最小结构）。
    await db.executeDirect('''
CREATE TABLE CHILD_INFO (
  ID TEXT PRIMARY KEY NOT NULL,
  CHECK_TIME TEXT NOT NULL,
  VISIT_CARD_NO TEXT,
  PATIENT_ID TEXT,
  ECARD_ID TEXT,
  ECARD_ID_HMAC TEXT,
  NAME TEXT NOT NULL,
  NAME_HMAC TEXT NOT NULL,
  SEX TEXT NOT NULL,
  BIRTH_DATE TEXT NOT NULL,
  BIRTH_TIME TEXT,
  COUNTRY TEXT,
  NATION TEXT,
  CERTIFICATE_TYPE TEXT,
  CERTIFICATE_NO TEXT,
  CERTIFICATE_NO_HMAC TEXT,
  HEALTH_NO TEXT,
  MCHIS_HEALTH_NO TEXT,
  ADDRESS_PROVINCE TEXT NOT NULL,
  ADDRESS_CITY TEXT NOT NULL,
  ADDRESS_COUNTY TEXT NOT NULL,
  ADDRESS_TOWN TEXT,
  ADDRESS_VILLAGE TEXT,
  ADDRESS_DETAILS TEXT NOT NULL,
  ADDRESS_CODE TEXT,
  PHONE TEXT,
  PHONE_HMAC TEXT,
  CREATOR_ID TEXT NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  DEPT_ID TEXT,
  DEPT_NAME TEXT,
  CAMPUS_ID TEXT,
  CAMPUS_NAME TEXT,
  HOSP_ID TEXT NOT NULL,
  HOSP_NAME TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    await db.executeDirect('''
CREATE TABLE CHILD_EXT_INFO (
  CHILD_ID TEXT NOT NULL PRIMARY KEY,
  GESTATIONAL_WEEK INTEGER,
  GESTATIONAL_DAY INTEGER,
  BIRTH_WEIGHT INTEGER,
  BIRTH_LENGTH NUMERIC(5,1),
  BIRTH_HEAD_CIRC NUMERIC(5,1),
  GRAVIDITY INTEGER,
  PARITY INTEGER,
  FETUS_COUNT INTEGER,
  BIRTH_ORDER INTEGER,
  DELIVERY_METHOD TEXT,
  BIRTH_HOSPITAL TEXT,
  BIRTH_CERTIFICATE_NO TEXT,
  BIRTH_CERTIFICATE_NO_HMAC TEXT,
  APGAR_1 INTEGER,
  APGAR_5 INTEGER,
  APGAR_10 INTEGER,
  HAS_BIRTH_ASPHYXIA TEXT,
  BIRTH_ASPHYXIA_SEVERITY TEXT,
  HAS_INJURY TEXT,
  HAS_INTRACRANIAL_HEMORRHAGE TEXT,
  INTRACRANIAL_HEMORRHAGE_LEVEL TEXT,
  HAS_BIRTH_DEFECT_0_6D TEXT,
  BIRTH_DEFECT_0_6D TEXT,
  OTHER_BIRTH_DEFECT_0_6D TEXT,
  HAS_BIRTH_DEFECT_7_28D TEXT,
  BIRTH_DEFECT_7_28D TEXT,
  OTHER_BIRTH_DEFECT_7_28D TEXT,
  HAS_ALLERGY_HISTORY TEXT,
  ALLERGEN TEXT,
  OTHER_ALLERGEN TEXT,
  IS_SGA TEXT,
  SGA_TYPE TEXT,
  IS_DEAD TEXT,
  DEATH_DATE TEXT,
  DEATH_CAUSE TEXT,
  HAS_SPONTANEOUS_ABORTION_HISTORY TEXT,
  SPONTANEOUS_ABORTION_COUNT INTEGER,
  HAS_INDUCED_ABORTION_HISTORY TEXT,
  INDUCED_ABORTION_COUNT INTEGER,
  HAS_RECURRENT_ABORTION_HISTORY TEXT,
  RECURRENT_ABORTION_COUNT INTEGER,
  HAS_PRETERM_BIRTH_HISTORY TEXT,
  PRETERM_BIRTH_COUNT INTEGER,
  HAS_FETAL_DEAD_HISTORY TEXT,
  FETAL_DEAD_COUNT INTEGER,
  HAS_STILLBIRTH_HISTORY TEXT,
  STILLBIRTH_COUNT INTEGER,
  HAS_FETAL_MALFORMATION_HISTORY TEXT,
  FETAL_MALFORMATION_COUNT INTEGER,
  FETAL_MALFORMATION_INFO TEXT,
  OTHER_PREGNANCY_HISTORY TEXT,
  CONCEPTION_METHOD TEXT,
  EXPECTED_DELIVERY_DATE TEXT,
  HAS_ABNORMAL_HBA1C TEXT,
  HAS_HBA1C_GE_5_5 TEXT,
  HAS_HBA1C_GE_6_5 TEXT,
  HAS_DIABETES TEXT,
  HAS_DIABETES_MEDICATION TEXT,
  HAS_GESTATIONAL_HYPERTENSION TEXT,
  HAS_ANEMIA TEXT,
  ANEMIA_SEVERITY TEXT,
  HAS_CMV_INFECTION TEXT,
  HAS_RUBELLA_INFECTION TEXT,
  HAS_MACROSOMIA TEXT,
  HAS_POLYHYDRAMNIOS TEXT,
  HAS_OLIGOHYDRAMNIOS TEXT,
  HAS_HYPERTHYROIDISM_IN_PREGNANCY TEXT,
  HAS_HYPOTHYROIDISM_IN_PREGNANCY TEXT,
  HAS_PREECLAMPSIA TEXT,
  HAS_ECLAMPSIA TEXT,
  HAS_HIV_INFECTION TEXT,
  HAS_SYPHILIS_INFECTION TEXT,
  OTHER_DISEASES_IN_PREGNANCY TEXT,
  HAS_PARENTAL_MENTAL_ILLNESS_HISTORY TEXT,
  HAS_PARENTAL_DRUG_ABUSE_HISTORY TEXT,
  HAS_FAMILY_HEARING_LOSS_HISTORY TEXT,
  HAS_PARENTAL_CONSANGUINEOUS_MARRIAGE TEXT,
  OTHER_FAMILY_HISTORY TEXT,
  MATERNAL_INPATIENT_NO TEXT,
  MATERNAL_AGE_AT_DELIVERY INTEGER,
  CREATOR_ID TEXT NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  DEPT_ID TEXT,
  DEPT_NAME TEXT,
  CAMPUS_ID TEXT,
  CAMPUS_NAME TEXT,
  HOSP_ID TEXT NOT NULL,
  HOSP_NAME TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    await db.executeDirect('''
CREATE TABLE CHILD_GUARDIAN_INFO (
  ID TEXT PRIMARY KEY NOT NULL,
  CHILD_ID TEXT NOT NULL,
  NAME TEXT NOT NULL,
  NAME_HMAC TEXT NOT NULL,
  BIRTH_DATE TEXT,
  CERTIFICATE_TYPE TEXT,
  CERTIFICATE_NO TEXT,
  CERTIFICATE_NO_HMAC TEXT,
  COUNTRY TEXT,
  NATION TEXT,
  EDUCATION_LEVEL TEXT,
  OCCUPATION TEXT,
  PHONE TEXT,
  PHONE_HMAC TEXT,
  HEIGHT NUMERIC(5,1),
  WEIGHT NUMERIC(5,1),
  EMPLOYER TEXT,
  GUARDIAN_RELATIONSHIP TEXT NOT NULL,
  GUARDIAN_ORDER INTEGER,
  CREATOR_ID TEXT NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  DEPT_ID TEXT,
  DEPT_NAME TEXT,
  CAMPUS_ID TEXT,
  CAMPUS_NAME TEXT,
  HOSP_ID TEXT NOT NULL,
  HOSP_NAME TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    await db.executeDirect('''
CREATE TABLE CHILD_PHOTO (
  ID TEXT PRIMARY KEY NOT NULL,
  CHILD_ID TEXT NOT NULL,
  PHOTO TEXT NOT NULL,
  AVATAR TEXT NOT NULL,
  CREATOR_ID TEXT NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  DEPT_ID TEXT,
  DEPT_NAME TEXT,
  CAMPUS_ID TEXT,
  CAMPUS_NAME TEXT,
  HOSP_ID TEXT NOT NULL,
  HOSP_NAME TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    service = ChildService(db, cipher);
  });

  tearDown(() {
    db.close();
  });

  ChildGuardianInfo buildGuardian({String name = '王大壮', String relationship = '父亲', String? order = '1'}) => ChildGuardianInfo(
    childId: '',
    name: name,
    birthDate: '1990-05-01',
    certificateType: '居民身份证',
    certificateNo: '110101199005011234',
    country: '中国',
    nation: '汉族',
    educationLevel: '本科',
    occupation: '工程师',
    phone: '13900139000',
    height: '175.5',
    weight: '70.0',
    employer: '示例科技公司',
    guardianRelationship: relationship,
    guardianOrder: order,
    creatorId: '',
    creatorName: '',
    hospId: '',
    hospName: '',
  );

  ChildExtInfo buildExt({String apgar1 = '8', String gestationalWeek = '38', String birthWeight = '3200'}) => ChildExtInfo(
    childId: '',
    creatorId: '',
    creatorName: '',
    hospId: '',
    hospName: '',
    gestationalWeek: gestationalWeek,
    gestationalDay: '2',
    birthWeight: birthWeight,
    birthLength: '50.5',
    birthHeadCirc: '34.5',
    gravidity: '1',
    parity: '1',
    fetusCount: '1',
    birthOrder: '1',
    deliveryMethod: '自然分娩',
    birthHospital: '示例人民医院',
    birthCertificateNo: 'J2601001',
    apgar1: apgar1,
    apgar5: '9',
    apgar10: '10',
    hasBirthAsphyxia: '0',
    hasInjury: '0',
    hasAllergyHistory: '0',
    isDead: '0',
    conceptionMethod: '自然受孕',
    hasAbnormalHba1c: '0',
    hasDiabetes: '0',
    hasAnemia: '0',
    maternalInpatientNo: 'ZY2026001',
    maternalAgeAtDelivery: '28',
  );

  test('create + load：整档入库，敏感字段密文落库、读出解密还原', () async {
    final (child, ext, guardians) = await service.create(
      child: buildChild(),
      ext: buildExt(),
      guardians: [buildGuardian()],
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    // 主键为应用侧 UUID v7（36 位标准格式），INSERT 前置生成
    expect(child.id, matchesRegexpUuid());
    expect(child.name, '王小明');
    expect(child.ecardId, 'EC123456');
    expect(child.certificateNo, '110101202601011234');
    expect(child.addressDetails, '景山前街4号');
    expect(child.phone, '13800138000');
    expect(child.addressCode, '110101');
    expect(child.creatorName, '张医生');
    expect(child.hospId, '1');
    expect(child.hospName, '示例人民医院');

    expect(ext, isNotNull);
    expect(ext!.gestationalWeek, '38');
    expect(ext.birthLength, '50.5');
    expect(ext.birthCertificateNo, 'J2601001', reason: '出生证号解密还原');
    expect(ext.apgar10, '10');
    expect(ext.createTime, isNotNull);

    expect(guardians, hasLength(1));
    expect(guardians.first.name, '王大壮');
    expect(guardians.first.certificateNo, '110101199005011234');
    expect(guardians.first.phone, '13900139000');
    expect(guardians.first.height, '175.5');

    // 直查数据库：敏感列均为密文（v1: 前缀）且盲索引列为 64 位十六进制
    final raw = (await db.query('SELECT NAME, NAME_HMAC, PHONE, ADDRESS_DETAILS FROM CHILD_INFO WHERE ID = ?', [child.id])).rowsAsMaps.first;
    expect(raw['NAME'], startsWith('v1:'));
    expect(raw['NAME'], isNot(contains('王小明')));
    expect(raw['ADDRESS_DETAILS'], startsWith('v1:'));
    final nameHmac = raw['NAME_HMAC']!;
    expect(nameHmac.length, 64);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(nameHmac), isTrue, reason: '盲索引列为十六进制');

    // 复建同名同生日档案 → 各自独立主键（UUID 无自然键冲突概念）
    final second = await service.create(
      child: buildChild(),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    expect(second.$1.id, matchesRegexpUuid());
    expect(second.$1.id, isNot(child.id));
  });

  test('search：姓名盲索引精确匹配、就诊卡号、保健号或条件检索并解密', () async {
    await service.create(child: buildChild(), creatorId: '9', creatorName: '张医生', hospId: '1', hospName: '示例人民医院');
    await service.create(
      child: buildChild(name: '李小红', visitCardNo: 'JZK202601002', certificateNo: null, phone: null, healthNo: null),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );

    final byName = await service.search(hospId: '1', name: '王小明');
    expect(byName.map((c) => c.name), ['王小明']);

    final byCard = await service.search(hospId: '1', visitCardNo: 'JZK202601002');
    expect(byCard.map((c) => c.name), ['李小红']);

    final byHealth = await service.search(hospId: '1', healthNo: 'H0001');
    expect(byHealth, hasLength(1));
    expect(byHealth.first.name, '王小明');

    // 证件号码/联系电话走盲索引精确匹配
    final byCert = await service.search(hospId: '1', certificateNo: '110101202601011234');
    expect(byCert.map((c) => c.name), ['王小明']);
    final byPhone = await service.search(hospId: '1', phone: '13800138000');
    expect(byPhone.map((c) => c.name), ['王小明']);

    // 超长条件静默跳过：仅剩合法条件仍可命中（全局搜索框容错）
    final overlong = '一' * 30; // 90 字节 > 联系电话上限 24
    final byLenient = await service.search(hospId: '1', phone: overlong, certificateNo: '110101202601011234');
    expect(byLenient.map((c) => c.name), ['王小明']);

    // 空条件 → 报错；跨医院不可见
    await expectLater(
      service.search(hospId: '1'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('至少输入'))),
    );
    expect(await service.search(hospId: '2', name: '王小明'), isEmpty);
  });

  test('update：整档更新、病人ID不可改、扩展信息与监护人全量覆盖', () async {
    final first = await service.create(
      child: buildChild(patientId: 'P0001'),
      ext: buildExt(),
      guardians: [buildGuardian()],
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final id = first.$1.id;

    final (child, ext, guardians) = await service.update(
      id: id,
      child: buildChild(visitCardNo: 'JZK-NEW', phone: null),
      guardians: [buildGuardian(name: '赵丽', relationship: '母亲', order: '2')],
      hospId: '1',
    );
    expect(child.visitCardNo, 'JZK-NEW');
    expect(child.patientId, 'P0001', reason: '病人ID为 HIS 回写字段，修改时保持原值');
    expect(child.phone, isNull, reason: '空值清空联系电话');
    expect(child.updateTime, isNotNull);
    expect(ext, isNull, reason: 'ext 缺省即清空扩展信息');
    expect(guardians.map((g) => g.name), ['赵丽'], reason: '监护人先删后插全量覆盖');
    expect(guardians.first.guardianRelationship, '母亲');

    // 带扩展信息保存 → 重新落库并可读出
    final again = await service.update(id: id, child: child, ext: buildExt(), guardians: guardians, hospId: '1');
    expect(again.$2, isNotNull);
    expect(again.$2!.birthCertificateNo, 'J2601001');
  });

  test('delete：连带删除扩展信息与监护人；跨医院与不存在均拒绝', () async {
    final created = await service.create(
      child: buildChild(),
      ext: buildExt(),
      guardians: [buildGuardian()],
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final id = created.$1.id;

    // 医院 2 视角不可见
    await expectLater(
      service.delete(id, '2'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('不存在'))),
    );

    expect(await service.delete(id, '1'), 1);
    expect((await db.query('SELECT COUNT(*) AS CNT FROM CHILD_INFO')).rowsAsMaps.first['CNT'], '0');
    expect((await db.query('SELECT COUNT(*) AS CNT FROM CHILD_EXT_INFO')).rowsAsMaps.first['CNT'], '0');
    expect((await db.query('SELECT COUNT(*) AS CNT FROM CHILD_GUARDIAN_INFO')).rowsAsMaps.first['CNT'], '0');

    await expectLater(
      service.delete(id, '1'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('校验：必填缺失、性别/评分/布尔标记非法、密文列超字节上限均报错', () async {
    // 姓名必填
    await expectLater(
      service.create(
        child: buildChild(name: '  '),
        creatorId: '9',
        creatorName: '张医生',
        hospId: '1',
        hospName: '示例人民医院',
      ),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('姓名不能为空'))),
    );
    // 性别非法
    await expectLater(
      service.create(
        child: buildChild(sex: '3'),
        creatorId: '9',
        creatorName: '张医生',
        hospId: '1',
        hospName: '示例人民医院',
      ),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('性别应为'))),
    );
    // 密文列明文超字节上限（20 个汉字 = 60 字节 > 57）
    await expectLater(
      service.create(
        child: buildChild(name: '王' * 20),
        creatorId: '9',
        creatorName: '张医生',
        hospId: '1',
        hospName: '示例人民医院',
      ),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('超出长度限制'))),
    );
    // Apgar 评分越界
    await expectLater(
      service.create(
        child: buildChild(),
        ext: buildExt(apgar1: '99'),
        creatorId: '9',
        creatorName: '张医生',
        hospId: '1',
        hospName: '示例人民医院',
      ),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('Apgar评分-1分钟应为'))),
    );
    // 详细地址密文列（v16 扩容至 VARCHAR(214)）：明文上限 100 字节，
    // 33 汉字 99 字节可存，超过 100 字节报错
    final longAddress = await service.create(
      child: buildChild(addressDetails: '详' * 33),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    expect(longAddress.$1.addressDetails, '详' * 33);
    await expectLater(
      service.create(
        child: buildChild(addressDetails: '详' * 34),
        creatorId: '9',
        creatorName: '张医生',
        hospId: '1',
        hospName: '示例人民医院',
      ),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('居住地址详细超出长度限制'))),
    );
  });

  test('照片：保存历史取最近、移除当天、跨医院隔离与限长校验', () async {
    final created = await service.create(
      child: buildChild(),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final childId = created.$1.id;

    // 无记录 → null
    expect(await service.latestPhoto(childId, '1'), isNull);

    // 保存两次（历史保留），最近一条生效
    await service.savePhoto(
      childId: childId,
      photoBase64: 'PHOTO-1',
      avatarBase64: 'AVATAR-1',
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    await service.savePhoto(
      childId: childId,
      photoBase64: 'PHOTO-2',
      avatarBase64: 'AVATAR-2',
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final latest = await service.latestPhoto(childId, '1');
    expect(latest?.avatarBase64, 'AVATAR-2', reason: '按创建时间/ID 倒序取最近一条');
    expect(latest?.photoBase64, isNull, reason: '最近记录查询不含 PHOTO 大图');
    expect(latest?.creatorName, '张医生');
    expect(latest?.hospName, '示例人民医院');

    // 跨医院不可见
    expect(await service.latestPhoto(childId, '2'), isNull);
    await expectLater(
      service.savePhoto(
        childId: childId,
        photoBase64: 'P',
        avatarBase64: 'A',
        creatorId: '9',
        creatorName: '张医生',
        hospId: '2',
        hospName: '示例儿童医院',
      ),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('不存在'))),
    );

    // 限长校验：空值与超 1MB 拒绝
    await expectLater(
      service.savePhoto(childId: childId, photoBase64: '  ', avatarBase64: 'A', creatorId: '9', creatorName: '张医生', hospId: '1', hospName: '示例人民医院'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('照片不能为空'))),
    );
    await expectLater(
      service.savePhoto(childId: childId, photoBase64: 'P', avatarBase64: 'A' * (1024 * 1024 + 1), creatorId: '9', creatorName: '张医生', hospId: '1', hospName: '示例人民医院'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('头像超出长度限制'))),
    );

    // 移除当天：两条均为今天创建 → 全部删除
    expect(await service.removeTodayPhotos(childId, '1'), 2);
    expect(await service.latestPhoto(childId, '1'), isNull);

    // 跨医院移除：儿童不属于该院 → 拒绝
    await expectLater(
      service.removeTodayPhotos(childId, '2'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('照片：随档案保存一并入库（add/update 携带 photo）', () async {
    // 新增带照片 → 插入一条拍照记录
    final created = await service.create(
      child: buildChild(),
      photoBase64: 'PHOTO-NEW',
      avatarBase64: 'AVATAR-NEW',
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final latest = await service.latestPhoto(created.$1.id, '1');
    expect(latest?.avatarBase64, 'AVATAR-NEW');

    // 修改再带新照片 → 追加新记录取最近
    await service.update(
      id: created.$1.id,
      child: buildChild(),
      photoBase64: 'PHOTO-EDIT',
      avatarBase64: 'AVATAR-EDIT',
      hospId: '1',
    );
    final afterEdit = await service.latestPhoto(created.$1.id, '1');
    expect(afterEdit?.avatarBase64, 'AVATAR-EDIT');

    // 删除档案 → 拍照记录连带删除
    expect(await service.delete(created.$1.id, '1'), 1);
    expect(await service.latestPhoto(created.$1.id, '1'), isNull);
  });

  test('findDuplicates：姓名+性别+出生日期三键 AND 查重、excludeId 排除自身、跨院隔离', () async {
    // 同名同性别同生日两条（医院 1）
    final first = await service.create(
      child: buildChild(),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    final second = await service.create(
      child: buildChild(visitCardNo: 'JZK202601002'),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );

    // 三键全中 → 命中两条（按创建时间倒序，后者在前）
    final both = await service.findDuplicates(hospId: '1', name: '王小明', sex: '1', birthDate: '2026-01-01');
    expect(both, hasLength(2));
    expect(both.map((c) => c.id), [second.$1.id, first.$1.id]);
    expect(both.first.phone, '13800138000', reason: '返回解密后的完整档案供对话框展示');

    // excludeId 排除自身（修改态保存）
    final excludingSelf = await service.findDuplicates(hospId: '1', name: '王小明', sex: '1', birthDate: '2026-01-01', excludeId: second.$1.id);
    expect(excludingSelf.map((c) => c.id), [first.$1.id]);

    // 性别/出生日期不同 → 不命中
    expect(await service.findDuplicates(hospId: '1', name: '王小明', sex: '2', birthDate: '2026-01-01'), isEmpty);
    expect(await service.findDuplicates(hospId: '1', name: '王小明', sex: '1', birthDate: '2026-02-01'), isEmpty);

    // 跨医院不可见
    expect(await service.findDuplicates(hospId: '2', name: '王小明', sex: '1', birthDate: '2026-01-01'), isEmpty);

    // 校验：非法性别/日期报错
    await expectLater(
      service.findDuplicates(hospId: '1', name: '王小明', sex: '3', birthDate: '2026-01-01'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('性别应为'))),
    );
    await expectLater(
      service.findDuplicates(hospId: '1', name: '王小明', sex: '1', birthDate: '20260101'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('出生日期'))),
    );
  });

  // 高级组合查询测试数据：医院 1 依次建档 王小明（38 周/3200g，监护人
  // 王大壮）→ 李小红（40 周/2800g，女，无证件/电话）→ 张小刚（无扩展
  // 信息无监护人、无证件/电话，保证盲索引条件各自唯一命中），医院 2
  // 一条同名档案用于隔离断言。列表查询按「CREATE_TIME DESC, ID DESC」
  // 排序（UUID v7 单调递增），即建档顺序的倒序：张小刚 → 李小红 → 王小明。
  Future<void> seedAdvanced() async {
    Future<ChildInfo> save(ChildInfo child, {ChildExtInfo? ext, List<ChildGuardianInfo> guardians = const [], String hospId = '1'}) async {
      final created = await service.create(
        child: child,
        ext: ext,
        guardians: guardians,
        creatorId: '9',
        creatorName: '张医生',
        hospId: hospId,
        hospName: hospId == '1' ? '示例人民医院' : '示例二院',
      );
      return created.$1;
    }

    await save(buildChild(), ext: buildExt(), guardians: [buildGuardian()]);
    await save(
      buildChild(
        name: '李小红',
        sex: '2',
        visitCardNo: 'JZK202601002',
        certificateNo: null,
        phone: null,
        healthNo: null,
        checkTime: '2026-10-01',
        birthDate: '2025-06-15',
      ),
      ext: buildExt(gestationalWeek: '40', birthWeight: '2800'),
    );
    await save(
      buildChild(name: '张小刚', visitCardNo: 'JZK202601003', certificateNo: null, phone: null, checkTime: '2026-11-01', birthDate: '2026-03-20'),
    );
    await save(buildChild(visitCardNo: 'JZK-OUT'), hospId: '2');
  }

  test('advancedQuery：全空条件分页浏览，页切片与 total 一致、越界与夹取', () async {
    await seedAdvanced();
    final page1 = await service.advancedQuery(hospId: '1', pageSize: 2);
    expect(page1.$2, 3);
    expect(page1.$3, 1);
    expect(page1.$4, 2);
    expect(page1.$1.map((c) => c.name), ['张小刚', '李小红'], reason: '按创建时间倒序（新建在前），每页 2 条');

    final page2 = await service.advancedQuery(hospId: '1', page: 2, pageSize: 2);
    expect(page2.$2, 3);
    expect(page2.$3, 2);
    expect(page2.$1.map((c) => c.name), ['王小明']);
    expect(page2.$1.single.phone, '13800138000', reason: '当前页行解密下发');

    // 页码越界 → 空页但 total 不变
    final pageOver = await service.advancedQuery(hospId: '1', page: 9, pageSize: 2);
    expect(pageOver.$1, isEmpty);
    expect(pageOver.$2, 3);

    // page/pageSize 非法值静默夹取（page ≥ 1、pageSize 1-100）
    final clamped = await service.advancedQuery(hospId: '1', page: 0, pageSize: 500);
    expect(clamped.$3, 1);
    expect(clamped.$4, 100);
  });

  test('advancedQuery：文本条件 AND 组合、盲索引与监护人姓名 EXISTS', () async {
    await seedAdvanced();
    // 姓名 + 性别 AND 组合
    final combo = await service.advancedQuery(hospId: '1', name: '王小明', sex: '1');
    expect(combo.$2, 1);
    expect(combo.$1.single.name, '王小明');
    // 同名异性别 → AND 语义不命中
    final mismatch = await service.advancedQuery(hospId: '1', name: '王小明', sex: '2');
    expect(mismatch.$1, isEmpty);
    expect(mismatch.$2, 0);

    // 证件号码/联系电话盲索引等值、就诊卡号明文等值
    expect((await service.advancedQuery(hospId: '1', certificateNo: '110101202601011234')).$1.single.name, '王小明');
    expect((await service.advancedQuery(hospId: '1', phone: '13800138000')).$1.single.name, '王小明');
    expect((await service.advancedQuery(hospId: '1', visitCardNo: 'JZK202601002')).$1.single.name, '李小红');

    // 监护人姓名走 CHILD_GUARDIAN_INFO EXISTS + 盲索引
    final byGuardian = await service.advancedQuery(hospId: '1', guardianName: '王大壮');
    expect(byGuardian.$2, 1);
    expect(byGuardian.$1.single.name, '王小明');
    final guardianMiss = await service.advancedQuery(hospId: '1', guardianName: '不存在的监护人');
    expect(guardianMiss.$1, isEmpty);
    expect(guardianMiss.$2, 0);
  });

  test('advancedQuery：建档/出生日期区间比较，起止端点均含', () async {
    await seedAdvanced();
    // 建档日期区间 2026-11-01 ~ 2026-11-30 → 王小明(11-14) + 张小刚(11-01)
    final nov = await service.advancedQuery(hospId: '1', checkTimeFrom: '2026-11-01', checkTimeTo: '2026-11-30');
    expect(nov.$1.map((c) => c.name), ['张小刚', '王小明']);
    // 端点单日：恰为张小刚建档日（含端点）
    final exact = await service.advancedQuery(hospId: '1', checkTimeFrom: '2026-11-01', checkTimeTo: '2026-11-01');
    expect(exact.$1.map((c) => c.name), ['张小刚']);
    // 出生日期区间 → 仅李小红（2025-06-15）
    final birth = await service.advancedQuery(hospId: '1', birthDateFrom: '2025-01-01', birthDateTo: '2025-12-31');
    expect(birth.$1.map((c) => c.name), ['李小红']);
    // 起止倒挂 → 空结果（客户端已前置校验，服务端不再纠正）
    final inverted = await service.advancedQuery(hospId: '1', checkTimeFrom: '2026-12-01', checkTimeTo: '2026-01-01');
    expect(inverted.$1, isEmpty);
  });

  test('advancedQuery：孕周/体重区间经 CHILD_EXT_INFO EXISTS 过滤', () async {
    await seedAdvanced();
    // 孕周下限 39 → 仅李小红（40 周）；无扩展信息的张小刚不命中
    final weekFrom = await service.advancedQuery(hospId: '1', gestationalWeekFrom: 39);
    expect(weekFrom.$1.map((c) => c.name), ['李小红']);
    // 孕周区间 38-40 → 王小明 + 李小红
    final weekRange = await service.advancedQuery(hospId: '1', gestationalWeekFrom: 38, gestationalWeekTo: 40);
    expect(weekRange.$1.map((c) => c.name), ['李小红', '王小明']);
    // 体重下限 3000 → 仅王小明（3200g）
    final weightFrom = await service.advancedQuery(hospId: '1', birthWeightFrom: 3000);
    expect(weightFrom.$1.map((c) => c.name), ['王小明']);
    // 体重上限 2900 → 仅李小红（2800g）
    final weightTo = await service.advancedQuery(hospId: '1', birthWeightTo: 2900);
    expect(weightTo.$1.map((c) => c.name), ['李小红']);
  });

  test('advancedQuery：跨医院隔离与非法参数校验', () async {
    await seedAdvanced();
    // 医院 2 仅可见自己的档案
    final other = await service.advancedQuery(hospId: '2');
    expect(other.$2, 1);
    expect(other.$1.single.name, '王小明');
    expect(other.$1.single.visitCardNo, 'JZK-OUT');
    // 空 hospId → 空结果
    final noScope = await service.advancedQuery(hospId: '');
    expect(noScope.$1, isEmpty);
    expect(noScope.$2, 0);

    // 非法日期格式 / 性别 / 数值区间端点 → 40002
    await expectLater(
      service.advancedQuery(hospId: '1', checkTimeFrom: '2026/01/01'),
      throwsA(isA<ChildException>().having((e) => e.code, 'code', 40002)),
    );
    await expectLater(
      service.advancedQuery(hospId: '1', sex: '3'),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('性别'))),
    );
    await expectLater(
      service.advancedQuery(hospId: '1', gestationalWeekFrom: 40000),
      throwsA(isA<ChildException>().having((e) => e.message, 'message', contains('出生孕周'))),
    );
  });
}
