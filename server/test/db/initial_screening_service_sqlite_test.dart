import 'dart:convert';

import 'package:common/model.dart';
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/initial_screening_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（固定值便于跨行引用）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 示例儿童医院
const child1Id = 'c0000000-0000-0000-0000-000000000001'; // 医院 1 儿童
const child2Id = 'c0000000-0000-0000-0000-000000000002'; // 医院 2 儿童
const dept1Id = 'd0000000-0000-0000-0000-000000000001'; // 医院 1 儿保科
const dept2Id = 'd0000000-0000-0000-0000-000000000002'; // 医院 1 心理科
const dept3Id = 'd0000000-0000-0000-0000-000000000003'; // 医院 2 科室
const doctor1Id = 'e0000000-0000-0000-0000-000000000001'; // 医院 1 儿保科医生
const doctor2Id = 'e0000000-0000-0000-0000-000000000002'; // 医院 1 心理科医生
const doctor3Id = 'e0000000-0000-0000-0000-000000000003'; // 医院 1 儿保科护士（非医生）
const doctor4Id = 'e0000000-0000-0000-0000-000000000004'; // 医院 1 儿保科停用医生
const doctor5Id = 'e0000000-0000-0000-0000-000000000005'; // 医院 2 医生
const operator1Id = 'f0000000-0000-0000-0000-000000000001'; // 医院 1 操作员

/// 孤独症初筛记录服务单元测试（SQLite :memory:）：按儿童装载与医院
/// 隔离、预警征象条目按序号排序、检查医生候选过滤、新增/修改查重、
/// 字段校验（时段/日期/结果匹配 12.1-12.4/转诊/医生）、转诊联动
/// （REFL_* + DATA_SRC 键 upsert）、预约与检查汇总同步（下次日期空删
/// 预约）、删除与跨院隔离。
void main() {
  late SqliteGateway db;
  late InitialScreeningService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE ASD_INITIAL_SCREENING (
  ID TEXT PRIMARY KEY NOT NULL,
  CHILD_ID TEXT NOT NULL,
  CHECK_DATE TEXT NOT NULL,
  AGE_YEAR INTEGER NOT NULL,
  AGE_MONTH INTEGER NOT NULL,
  AGE_DAY INTEGER NOT NULL,
  CORRECTED_AGE_YEAR INTEGER,
  CORRECTED_AGE_MONTH INTEGER,
  CORRECTED_AGE_DAY INTEGER,
  CHECK_MONTH INTEGER NOT NULL,
  WARNING_SIGN_RESULT TEXT NOT NULL,
  LANGUAGE_SOCIAL_COMMUNICATION_RESULT TEXT NOT NULL,
  CHECK_RESULT TEXT NOT NULL,
  GUIDANCE TEXT,
  HAS_REFERRAL TEXT NOT NULL,
  REFERRAL_HOSP_ID TEXT,
  REFERRAL_HOSP_NAME TEXT NOT NULL,
  REFERRAL_DEPT_ID TEXT,
  REFERRAL_DEPT_NAME TEXT,
  NEXT_CHECK_DATE TEXT,
  DOCTOR_ID TEXT NOT NULL,
  DOCTOR_NAME TEXT NOT NULL,
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
CREATE TABLE SCALE_WSCMBD (
  ID INTEGER PRIMARY KEY AUTOINCREMENT,
  MONTH INTEGER NOT NULL,
  ITEM_NAME TEXT NOT NULL,
  ITEM_TYPE INTEGER NOT NULL,
  ITEM_ORDER INTEGER NOT NULL,
  ITEM_DESC TEXT
)''');
    await db.executeDirect('CREATE TABLE CHILD_INFO (ID TEXT PRIMARY KEY NOT NULL, HOSP_ID TEXT NOT NULL)');
    await db.executeDirect('''
CREATE TABLE CHILD_REFERRAL (
  ID TEXT PRIMARY KEY NOT NULL,
  CHILD_ID TEXT NOT NULL,
  REFL_DATE TEXT NOT NULL,
  REFL_TYPE INTEGER NOT NULL,
  REFL_REASON TEXT NOT NULL,
  REFL_HOSP_NAME TEXT NOT NULL,
  REFL_DEPT_NAME TEXT,
  CONSULT_DATE TEXT,
  CONSULT_DESC TEXT,
  DATA_SRC_NAME TEXT NOT NULL,
  DATA_SRC_ID TEXT NOT NULL,
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
CREATE TABLE CHILD_APPOINTMENT (
  ID TEXT PRIMARY KEY NOT NULL,
  CHILD_ID TEXT NOT NULL,
  APPT_DATE TEXT NOT NULL,
  APPT_CHECK_TYPE TEXT NOT NULL,
  APPT_DOCTOR_ID TEXT,
  APPT_DOCTOR_NAME TEXT,
  APPT_DEPT_ID TEXT,
  APPT_DEPT_NAME TEXT,
  APPT_CAMPUS_ID TEXT,
  APPT_CAMPUS_NAME TEXT,
  DATA_SRC_NAME TEXT NOT NULL,
  DATA_SRC_ID TEXT NOT NULL,
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
CREATE TABLE CHILD_CHECK_RECORD (
  ID TEXT PRIMARY KEY NOT NULL,
  CHILD_ID TEXT NOT NULL,
  CHECK_DATE TEXT NOT NULL,
  AGE_YEAR INTEGER NOT NULL,
  AGE_MONTH INTEGER NOT NULL,
  AGE_DAY INTEGER NOT NULL,
  CHECK_TYPE TEXT NOT NULL,
  CHECK_FINDINGS TEXT,
  CHECK_RESULT TEXT,
  DATA_SRC_NAME TEXT NOT NULL,
  DATA_SRC_ID TEXT NOT NULL,
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
CREATE TABLE SYS_USER (
  ID TEXT PRIMARY KEY NOT NULL,
  USER_CODE TEXT,
  USER_NAME TEXT,
  USER_TYPE TEXT,
  DEPT_ID TEXT,
  HOSP_ID TEXT,
  STATUS TEXT
)''');

    await db.execute('INSERT INTO CHILD_INFO (ID, HOSP_ID) VALUES (?, ?)', [child1Id, hosp1Id]);
    await db.execute('INSERT INTO CHILD_INFO (ID, HOSP_ID) VALUES (?, ?)', [child2Id, hosp2Id]);

    Future<void> seedUser(String id, String code, String name, String type, String deptId, String hospId, {String? status}) async {
      await db.execute(
        'INSERT INTO SYS_USER (ID, USER_CODE, USER_NAME, USER_TYPE, DEPT_ID, HOSP_ID, STATUS) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, code, name, type, deptId, hospId, status ?? '1'],
      );
    }

    await seedUser(doctor1Id, 'D001', '王心怡', 'DOCTOR', dept1Id, hosp1Id);
    await seedUser(doctor2Id, 'D002', '李医生', 'DOCTOR', dept2Id, hosp1Id);
    await seedUser(doctor3Id, 'D003', '陈护士', 'NURSE', dept1Id, hosp1Id);
    await seedUser(doctor4Id, 'D004', '赵医生', 'DOCTOR', dept1Id, hosp1Id, status: '0');
    await seedUser(doctor5Id, 'D005', '钱医生', 'DOCTOR', dept3Id, hosp2Id);

    // 预警征象条目：月龄 12 乱序三条 + 月龄 8 一条（验证过滤与排序）
    await db.execute(
      'INSERT INTO SCALE_WSCMBD (MONTH, ITEM_NAME, ITEM_TYPE, ITEM_ORDER) VALUES (?, ?, ?, ?)',
      [12, '不会用拇食指对捏小物', 3, 3],
    );
    await db.execute(
      'INSERT INTO SCALE_WSCMBD (MONTH, ITEM_NAME, ITEM_TYPE, ITEM_ORDER) VALUES (?, ?, ?, ?)',
      [12, '不会挥手表示“再见”或拍手表示“欢迎”', 1, 1],
    );
    await db.execute(
      'INSERT INTO SCALE_WSCMBD (MONTH, ITEM_NAME, ITEM_TYPE, ITEM_ORDER) VALUES (?, ?, ?, ?)',
      [12, '不会扶物站立', 4, 4],
    );
    await db.execute(
      'INSERT INTO SCALE_WSCMBD (MONTH, ITEM_NAME, ITEM_TYPE, ITEM_ORDER) VALUES (?, ?, ?, ?)',
      [8, '不会独坐', 4, 1],
    );

    service = InitialScreeningService(db);
  });

  tearDown(() {
    db.close();
  });

  /// 构造一条合法初筛记录草稿（医院 1 儿童 1、12 月龄、未见异常、无转诊）。
  InitialScreening draft({
    String childId = child1Id,
    int checkMonth = 12,
    String doctorId = doctor1Id,
    String doctorName = '王心怡',
    String warning = '未见异常',
    String languageSocial = '未见异常',
    String checkResult = InitialScreeningService.checkResultNormal,
    String hasReferral = '0',
    String referralHospName = '',
    String? referralHospId,
    String? referralDeptName,
    String? referralDeptId,
    int? correctedYear,
    int? correctedMonth,
    int? correctedDay,
    String? guidance,
    String? nextCheckDate,
  }) => InitialScreening(
    childId: childId,
    checkDate: '2026-11-23',
    ageYear: 1,
    ageMonth: 0,
    ageDay: 5,
    correctedAgeYear: correctedYear,
    correctedAgeMonth: correctedMonth,
    correctedAgeDay: correctedDay,
    checkMonth: checkMonth,
    warningSignResult: warning,
    languageSocialCommunicationResult: languageSocial,
    checkResult: checkResult,
    guidance: guidance,
    hasReferral: hasReferral,
    referralHospId: referralHospId,
    referralHospName: referralHospName,
    referralDeptId: referralDeptId,
    referralDeptName: referralDeptName,
    nextCheckDate: nextCheckDate,
    doctorId: doctorId,
    doctorName: doctorName,
    creatorId: operator1Id,
    creatorName: '测试员',
    hospId: hosp1Id,
    hospName: '示例人民医院',
  );

  /// 保存草稿（医院 1、儿保科上下文）。
  Future<InitialScreening> saveDraft([InitialScreening? record]) => service.save(
    record: record ?? draft(),
    operatorId: operator1Id,
    operatorName: '测试员',
    hospId: hosp1Id,
    hospName: '示例人民医院',
    deptId: dept1Id,
    deptName: '儿童保健科',
  );

  test('save：无转诊新增成功，无转诊医院名称落「无」、科室清空，归属随会话', () async {
    final saved = await saveDraft();
    expect(saved.id, isNotNull);
    expect(saved.childId, child1Id);
    expect(saved.checkMonth, 12);
    expect(saved.checkDate, '2026-11-23');
    expect(saved.hasReferral, '0');
    expect(saved.referralHospName, '无');
    expect(saved.referralDeptName, isNull);
    expect(saved.referralHospId, isNull);
    expect(saved.deptId, dept1Id);
    expect(saved.deptName, '儿童保健科');
    expect(saved.hospId, hosp1Id);
    expect(saved.creatorId, operator1Id);
    expect(saved.createTime, isNotNull);
    expect(saved.updateTime, isNull);
    expect(saved.guidance, isNull);
    expect(saved.nextCheckDate, isNull);
  });

  test('save：指导建议与下次检查日期随入参落库并回读', () async {
    final saved = await saveDraft(draft(guidance: '请定期复查，注意目光交流训练', nextCheckDate: '2027-03-22'));
    expect(saved.guidance, '请定期复查，注意目光交流训练');
    expect(saved.nextCheckDate, '2027-03-22');
    final list = await service.listByChild(child1Id, hosp1Id);
    expect(list.single.guidance, '请定期复查，注意目光交流训练');
    expect(list.single.nextCheckDate, '2027-03-22');
  });

  test('save：有转诊时医院名称必填、ID/科室随入参落库', () async {
    final saved = await saveDraft(
      draft(
        hasReferral: '1',
        checkResult: InitialScreeningService.checkResultAbnormal,
        warning: '不会挥手表示“再见”或拍手表示“欢迎”',
        languageSocial: '语言功能障碍或倒退',
        referralHospName: '市儿童医院',
        referralHospId: 'g0000000-0000-0000-0000-000000000001',
        referralDeptName: '儿童保健科',
        referralDeptId: 'g0000000-0000-0000-0000-000000000002',
      ),
    );
    expect(saved.hasReferral, '1');
    expect(saved.referralHospName, '市儿童医院');
    expect(saved.referralHospId, 'g0000000-0000-0000-0000-000000000001');
    expect(saved.referralDeptName, '儿童保健科');
    expect(saved.referralDeptId, 'g0000000-0000-0000-0000-000000000002');
  });

  test('save：同一儿童同一时段重复保存走更新（ID/创建人不变），不同时段各自成条', () async {
    final first = await saveDraft();
    final updated = await saveDraft(
      draft(
        warning: '不会挥手表示“再见”或拍手表示“欢迎”',
        languageSocial: '语言功能障碍或倒退',
        checkResult: InitialScreeningService.checkResultAbnormal,
        hasReferral: '1',
        referralHospName: '市儿童医院',
        correctedYear: 1,
        correctedMonth: 2,
        correctedDay: 3,
      ),
    );
    expect(updated.id, first.id);
    expect(updated.creatorId, first.creatorId);
    expect(updated.warningSignResult, contains('欢迎'));
    expect(updated.checkResult, InitialScreeningService.checkResultAbnormal);
    expect(updated.correctedAgeYear, 1);
    expect(updated.correctedAgeMonth, 2);
    expect(updated.updateTime, isNotNull);

    await saveDraft(draft(checkMonth: 24));
    final list = await service.listByChild(child1Id, hosp1Id);
    expect(list, hasLength(2));
    // 按检查时段升序：12 在前、24 在后
    expect(list.map((e) => e.checkMonth).toList(), [12, 24]);
  });

  test('save：listByChild 按医院隔离', () async {
    await saveDraft();
    expect(await service.listByChild(child1Id, hosp1Id), hasLength(1));
    expect(await service.listByChild(child1Id, hosp2Id), isEmpty);
    expect(await service.listByChild(child2Id, hosp1Id), isEmpty);
    expect(await service.listByChild(child1Id, ''), isEmpty);
  });

  test('save：初筛结果与询问结果匹配校验（12.1/12.2）', () async {
    // 均未见异常但结果=异常 → 初筛结果应为未见异常
    await expectLater(
      saveDraft(draft(checkResult: InitialScreeningService.checkResultAbnormal)),
      throwsA(predicate((e) => e is AsdException && e.message == '初筛结果应为未见异常，请检查确认')),
    );
    // 存在异常项但结果=未见异常 → 初筛结果应为异常
    await expectLater(
      saveDraft(draft(warning: '不会独坐')),
      throwsA(predicate((e) => e is AsdException && e.message == '初筛结果应为异常，请检查确认')),
    );
    await expectLater(
      saveDraft(draft(languageSocial: '社会交往能力障碍或倒退')),
      throwsA(predicate((e) => e is AsdException && e.message == '初筛结果应为异常，请检查确认')),
    );
    // 匹配组合放行
    await saveDraft();
    await saveDraft(
      draft(checkMonth: 24, warning: '不会独坐', checkResult: InitialScreeningService.checkResultAbnormal, hasReferral: '1', referralHospName: '市儿童医院'),
    );
    expect(await service.listByChild(child1Id, hosp1Id), hasLength(2));
  });

  test('save：异常必须转诊（12.3）', () async {
    await expectLater(
      saveDraft(
        draft(warning: '不会独坐', checkResult: InitialScreeningService.checkResultAbnormal),
      ),
      throwsA(predicate((e) => e is AsdException && e.message == '初筛阳性，必须转诊到县级妇幼保健机构进行复筛')),
    );
  });

  test('save：其余校验失败不落库', () async {
    // 检查时段非法
    await expectLater(saveDraft(draft(checkMonth: 9)), throwsA(predicate((e) => e is AsdException && e.code == 40002)));
    // 儿童不存在/非本院
    await expectLater(saveDraft(draft(childId: child2Id)), throwsA(predicate((e) => e is AsdException && e.code == 40001)));
    // 检查日期格式
    const badDate = InitialScreening(
      childId: child1Id,
      checkDate: '2026/11/23',
      ageYear: 1,
      ageMonth: 0,
      ageDay: 5,
      checkMonth: 12,
      warningSignResult: '未见异常',
      languageSocialCommunicationResult: '未见异常',
      checkResult: '未见异常',
      hasReferral: '0',
      referralHospName: '',
      doctorId: doctor1Id,
      doctorName: '王心怡',
      creatorId: operator1Id,
      creatorName: '测试员',
      hospId: hosp1Id,
      hospName: '示例人民医院',
    );
    await expectLater(
      service.save(
        record: badDate,
        operatorId: operator1Id,
        operatorName: '测试员',
        hospId: hosp1Id,
        hospName: '示例人民医院',
        deptId: dept1Id,
        deptName: '儿童保健科',
      ),
      throwsA(predicate((e) => e is AsdException && e.message.contains('yyyy-MM-dd'))),
    );
    // 检查医生非同科室
    await expectLater(
      saveDraft(draft(doctorId: doctor2Id)),
      throwsA(predicate((e) => e is AsdException && e.message.contains('科室'))),
    );
    // 检查医生非医生类别
    await expectLater(saveDraft(draft(doctorId: doctor3Id)), throwsA(predicate((e) => e is AsdException)));
    // 检查医生为空（12.5）
    await expectLater(saveDraft(draft(doctorId: '  ')), throwsA(predicate((e) => e is AsdException && e.message == '检查医生不能为空')));
    // 初筛结果为空
    await expectLater(saveDraft(draft(checkResult: '  ')), throwsA(predicate((e) => e is AsdException && e.code == 40002)));
    // 有无转诊取值非法
    await expectLater(saveDraft(draft(hasReferral: '2')), throwsA(predicate((e) => e is AsdException && e.code == 40002)));
    // 有转诊但医院名称为空（12.4）
    await expectLater(
      saveDraft(
        draft(warning: '不会独坐', checkResult: InitialScreeningService.checkResultAbnormal, hasReferral: '1'),
      ),
      throwsA(predicate((e) => e is AsdException && e.message == '转诊医院不能为空')),
    );
    // 预警征象为空 / 超出字节上限
    await expectLater(saveDraft(draft(warning: '')), throwsA(predicate((e) => e is AsdException && e.message.contains('预警征象'))));
    final longWarning = '不会挥手表示“再见”或拍手表示“欢迎”、' * 4;
    await expectLater(saveDraft(draft(warning: longWarning)), throwsA(predicate((e) => e is AsdException && e.message.contains('预警征象'))));
    // 指导建议超长（>1000 字节）
    await expectLater(
      saveDraft(draft(guidance: '长' * 400)),
      throwsA(predicate((e) => e is AsdException && e.message.contains('指导建议'))),
    );

    final list = await service.listByChild(child1Id, hosp1Id);
    expect(list, isEmpty); // 全部非法保存均未落库
  });

  test('delete：按 ID 删除本院记录，跨院 ID 返回 0', () async {
    final saved = await saveDraft();
    expect(await service.delete(saved.id!, hosp1Id), 1);
    expect(await service.listByChild(child1Id, hosp1Id), isEmpty);
    expect(await service.delete(saved.id!, hosp1Id), 0);
    await expectLater(service.delete('', hosp1Id), throwsA(isA<AsdException>()));
  });

  test('wscmbdItems：按月龄过滤并按条目序号升序', () async {
    final m12 = await service.wscmbdItems(12);
    expect(m12, hasLength(3));
    expect(m12.map((e) => e.itemOrder).toList(), [1, 3, 4]);
    expect(m12.first.itemName, contains('欢迎'));
    final m8 = await service.wscmbdItems(8);
    expect(m8, hasLength(1));
    expect(m8.single.itemName, '不会独坐');
    expect(await service.wscmbdItems(72), isEmpty);
  });

  test('listDoctors：同科室启用医生，排除其他科室/类别/停用；科室为空返回空', () async {
    final doctors = await service.listDoctors(dept1Id);
    expect(doctors.map((d) => d.id), [doctor1Id]); // 排除心理科/护士/停用
    expect(doctors.single.userName, '王心怡');
    expect(await service.listDoctors(''), isEmpty);
  });

  test('转诊联动：有转诊写 CHILD_REFERRAL（REFL_*+DATA_SRC 键 upsert），改判日期更新原行', () async {
    final first = await saveDraft(
      draft(hasReferral: '1', checkResult: InitialScreeningService.checkResultAbnormal, warning: '不会独坐', referralHospName: '市儿童医院', referralDeptName: '儿童康复科'),
    );
    final rows = await db.query(
      'SELECT ID, CHILD_ID, REFL_DATE, REFL_TYPE, REFL_REASON, REFL_HOSP_NAME, '
      'REFL_DEPT_NAME, DATA_SRC_NAME, DATA_SRC_ID, CREATOR_ID, DEPT_ID, HOSP_ID, UPDATE_TIME '
      'FROM CHILD_REFERRAL',
    );
    expect(rows.rowsAsMaps, hasLength(1));
    final row = rows.rowsAsMaps.single;
    expect(row['CHILD_ID'], child1Id);
    expect(row['REFL_DATE'], '2026-11-23');
    expect(row['REFL_TYPE'], '1');
    expect(row['REFL_REASON'], InitialScreeningService.initialReferralReason);
    expect(row['REFL_HOSP_NAME'], '市儿童医院');
    expect(row['REFL_DEPT_NAME'], '儿童康复科');
    expect(row['DATA_SRC_NAME'], 'ASD_INITIAL_SCREENING');
    expect(row['DATA_SRC_ID'], first.id);
    expect(row['CREATOR_ID'], operator1Id);
    expect(row['DEPT_ID'], dept1Id);
    expect(row['HOSP_ID'], hosp1Id);
    expect(row['UPDATE_TIME'], isNull);

    // 同一初筛记录改判检查日期 → 更新原行（DATA_SRC 键），不另起新行
    await saveDraft(
      draft(hasReferral: '1', checkResult: InitialScreeningService.checkResultAbnormal, warning: '不会独坐', referralHospName: '省儿童医院', referralDeptName: null),
    );
    final after = await db.query('SELECT REFL_DATE, REFL_HOSP_NAME, REFL_DEPT_NAME, UPDATE_TIME FROM CHILD_REFERRAL');
    expect(after.rowsAsMaps, hasLength(1));
    expect(after.rowsAsMaps.single['REFL_HOSP_NAME'], '省儿童医院');
    expect(after.rowsAsMaps.single['REFL_DEPT_NAME'], isNull);
    expect(after.rowsAsMaps.single['UPDATE_TIME'], isNotNull);

    // 改回无转诊：转诊记录不回溯删除
    await saveDraft();
    expect((await db.query('SELECT ID FROM CHILD_REFERRAL')).rows, hasLength(1));
  });

  test('预约与检查汇总联动：有下次日期写两表，日期清空删预约、汇总保留更新', () async {
    final first = await saveDraft(draft(nextCheckDate: '2027-03-22'));
    final appts = await db.query('SELECT APPT_DATE, APPT_CHECK_TYPE, APPT_DOCTOR_ID, APPT_DOCTOR_NAME, DATA_SRC_ID, APPT_DEPT_ID FROM CHILD_APPOINTMENT');
    expect(appts.rowsAsMaps, hasLength(1));
    final appt = appts.rowsAsMaps.single;
    expect(appt['APPT_DATE'], '2027-03-22');
    expect(appt['APPT_CHECK_TYPE'], '孤独症初筛');
    expect(appt['APPT_DOCTOR_ID'], doctor1Id);
    expect(appt['APPT_DOCTOR_NAME'], '王心怡');
    expect(appt['DATA_SRC_ID'], first.id);
    expect(appt['APPT_DEPT_ID'], isNull);

    final records = await db.query('SELECT CHECK_DATE, AGE_YEAR, CHECK_TYPE, CHECK_FINDINGS, CHECK_RESULT, DATA_SRC_ID FROM CHILD_CHECK_RECORD');
    expect(records.rowsAsMaps, hasLength(1));
    final record = records.rowsAsMaps.single;
    expect(record['CHECK_DATE'], '2026-11-23');
    expect(record['AGE_YEAR'], '1');
    expect(record['CHECK_TYPE'], '孤独症初筛');
    expect(record['CHECK_FINDINGS'], '预警征象筛查：未见异常，语言功能和社会交往能力询问：未见异常');
    expect(record['CHECK_RESULT'], '未见异常');
    expect(record['DATA_SRC_ID'], first.id);

    // 再次保存（同键更新）不产生重复行
    await saveDraft(draft(nextCheckDate: '2027-03-23'));
    expect((await db.query('SELECT ID FROM CHILD_APPOINTMENT')).rows, hasLength(1));
    final apptAfter = await db.query('SELECT APPT_DATE FROM CHILD_APPOINTMENT');
    expect(apptAfter.rowsAsMaps.single['APPT_DATE'], '2027-03-23');

    // 下次日期清空（改判异常走转诊）→ 预约删除、汇总保留且更新
    final screeningId = (await service.listByChild(child1Id, hosp1Id)).single.id;
    await saveDraft(
      draft(
        warning: '不会独坐',
        checkResult: InitialScreeningService.checkResultAbnormal,
        hasReferral: '1',
        referralHospName: '市儿童医院',
        nextCheckDate: null,
      ),
    );
    expect((await db.query('SELECT ID FROM CHILD_APPOINTMENT')).rows, isEmpty);
    final recordAfter = await db.query('SELECT CHECK_RESULT FROM CHILD_CHECK_RECORD WHERE DATA_SRC_ID = ?', [screeningId]);
    expect(recordAfter.rows, hasLength(1));
    expect(recordAfter.rowsAsMaps.single['CHECK_RESULT'], '异常');
  });

  test('listForSidebar：医院隔离 + 日期区间 + 分页 + 儿童姓名解密', () async {
    // setUp 最小 CHILD_INFO 结构无 NAME 列（已种子 child1Id/child2Id），
    // 补列后为 child1 写入加密姓名
    await db.executeDirect('ALTER TABLE CHILD_INFO ADD COLUMN NAME TEXT');
    final cipher = FieldCipher.fromMasterKeyBase64(base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')));
    final nameCipher = await cipher.seal(FieldCipher.childNamePurpose, '王小明');
    await db.execute('UPDATE CHILD_INFO SET NAME = ? WHERE ID = ?', [nameCipher, child1Id]);

    Future<void> insertScreening({
      required String id,
      required String childId,
      required String date,
      required int month,
      required String result,
      required String hospId,
    }) => db.execute(
      'INSERT INTO ASD_INITIAL_SCREENING (ID, CHILD_ID, CHECK_DATE, AGE_YEAR, '
      'AGE_MONTH, AGE_DAY, CHECK_MONTH, WARNING_SIGN_RESULT, '
      'LANGUAGE_SOCIAL_COMMUNICATION_RESULT, CHECK_RESULT, HAS_REFERRAL, '
      'REFERRAL_HOSP_NAME, DOCTOR_ID, DOCTOR_NAME, CREATOR_ID, CREATOR_NAME, '
      'HOSP_ID, HOSP_NAME, CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        childId,
        date,
        1,
        2,
        3,
        month,
        '未见异常',
        '未见异常',
        result,
        '0',
        '无',
        doctor1Id,
        '王医生',
        operator1Id,
        '张医生',
        hospId,
        hospId == hosp1Id ? '示例人民医院' : '示例儿童医院',
        '2026-11-24 09:00:00',
      ],
    );

    await insertScreening(id: 'S1', childId: child1Id, date: '2026-01-10', month: 3, result: '未见异常', hospId: hosp1Id);
    await insertScreening(id: 'S2', childId: child1Id, date: '2026-06-20', month: 6, result: '异常', hospId: hosp1Id);
    // 儿童档案已删除（无 CHILD_INFO 行）→ 姓名显示「（已删除）」
    await insertScreening(id: 'S3', childId: 'c0000000-0000-0000-0000-000000000099', date: '2026-08-01', month: 12, result: '未见异常', hospId: hosp1Id);
    // 其他医院记录不应返回（按登录用户医院隔离）
    await insertScreening(id: 'S4', childId: child2Id, date: '2026-09-01', month: 18, result: '未见异常', hospId: hosp2Id);

    // 无日期区间 → 返回本院全部，按检查日期倒序；姓名已解密
    final (records, total, page, pageSize) = await service.listForSidebar(hospId: hosp1Id, page: 1, pageSize: 10, cipher: cipher);
    expect(total, 3);
    expect(page, 1);
    expect(pageSize, 10);
    expect(records.map((r) => r.id), ['S3', 'S2', 'S1']);
    expect(records[1].childName, '王小明');
    expect(records[1].childId, child1Id);
    expect(records[1].checkDate, '2026-06-20');
    expect(records[1].checkMonth, 6);
    expect(records[1].checkResult, '异常');
    expect(records[0].childName, '（已删除）');

    // 日期区间过滤
    final (june, juneTotal, _, _) = await service.listForSidebar(hospId: hosp1Id, startDate: '2026-06-01', endDate: '2026-06-30', page: 1, pageSize: 10, cipher: cipher);
    expect(juneTotal, 1);
    expect(june.single.id, 'S2');

    // 分页：每页 1 条，第 2 页为 S2；越界页为空
    final (page2, page2Total, _, _) = await service.listForSidebar(hospId: hosp1Id, page: 2, pageSize: 1, cipher: cipher);
    expect(page2Total, 3);
    expect(page2.single.id, 'S2');
    final (beyond, _, _, _) = await service.listForSidebar(hospId: hosp1Id, page: 9, pageSize: 1, cipher: cipher);
    expect(beyond, isEmpty);

    // 医院为空 → 空结果
    final (empty, emptyTotal, _, _) = await service.listForSidebar(hospId: ' ', page: 1, pageSize: 10, cipher: cipher);
    expect(empty, isEmpty);
    expect(emptyTotal, 0);
  });
}
