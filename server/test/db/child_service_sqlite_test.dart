import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/child_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

/// 儿童建档服务集成测试（SQLite :memory:）：新增整档（敏感字段加密落库
/// + 自然键回读自增 ID）、整档装载解密、姓名盲索引/就诊卡号/保健号检索、
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
  }) => ChildInfo(
    id: '',
    checkTime: '2026-11-14 09:30:00',
    visitCardNo: visitCardNo,
    patientId: patientId,
    ecardId: ecardId,
    name: name,
    sex: sex,
    birthDate: '2026-01-01',
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
    addressDetails: '景山前街4号',
    addressCode: '110101',
    phone: phone,
    creatorId: '',
    creatorName: '',
    hospId: '',
    hospName: '',
  );

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    // 建表语句与 v15 迁移 SQLite 段一致（测试只建所需最小结构）。
    await db.executeDirect('''
CREATE TABLE CHILD_INFO (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
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
  CREATOR_ID INTEGER NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  HOSP_ID INTEGER NOT NULL,
  HOSP_NAME TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    await db.executeDirect('''
CREATE TABLE CHILD_EXT_INFO (
  CHILD_ID INTEGER NOT NULL PRIMARY KEY,
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
  CREATOR_ID INTEGER NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  HOSP_ID INTEGER NOT NULL,
  HOSP_NAME TEXT NOT NULL,
  CREATE_TIME TEXT NOT NULL,
  UPDATE_TIME TEXT
)''');
    await db.executeDirect('''
CREATE TABLE CHILD_GUARDIAN_INFO (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  CHILD_ID INTEGER NOT NULL,
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
  CREATOR_ID INTEGER NOT NULL,
  CREATOR_NAME TEXT NOT NULL,
  HOSP_ID INTEGER NOT NULL,
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

  ChildExtInfo buildExt({String apgar1 = '8'}) => ChildExtInfo(
    childId: '',
    creatorId: '',
    creatorName: '',
    hospId: '',
    hospName: '',
    gestationalWeek: '38',
    gestationalDay: '2',
    birthWeight: '3200',
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
    expect(child.id, '1');
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
    final raw = (await db.query('SELECT NAME, NAME_HMAC, PHONE, ADDRESS_DETAILS FROM CHILD_INFO WHERE ID = 1')).rowsAsMaps.first;
    expect(raw['NAME'], startsWith('v1:'));
    expect(raw['NAME'], isNot(contains('王小明')));
    expect(raw['ADDRESS_DETAILS'], startsWith('v1:'));
    final nameHmac = raw['NAME_HMAC']!;
    expect(nameHmac.length, 64);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(nameHmac), isTrue, reason: '盲索引列为十六进制');

    // 复建同名同生日档案（不同秒创建）→ 自然键回读各归各行
    final second = await service.create(
      child: buildChild(),
      creatorId: '9',
      creatorName: '张医生',
      hospId: '1',
      hospName: '示例人民医院',
    );
    expect(second.$1.id, '2');
  });

  test('search：姓名盲索引精确匹配、就诊卡号、保健号或条件检索并解密', () async {
    await service.create(child: buildChild(), creatorId: '9', creatorName: '张医生', hospId: '1', hospName: '示例人民医院');
    await service.create(
      child: buildChild(name: '李小红', visitCardNo: 'JZK202601002', certificateNo: null, healthNo: null),
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
  });
}
