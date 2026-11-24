import 'package:common/model.dart';
import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/initial_screening_service.dart';
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
/// 字段校验（时段/日期/结果/转诊/医生）、删除与跨院隔离。
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
  HAS_REFERRAL TEXT NOT NULL,
  REFERRAL_HOSP_ID TEXT,
  REFERRAL_HOSP_NAME TEXT NOT NULL,
  REFERRAL_DEPT_ID TEXT,
  REFERRAL_DEPT_NAME TEXT,
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
  REFERRAL_DATE TEXT NOT NULL,
  REFERRAL_TYPE INTEGER NOT NULL,
  REFERRAL_REASON TEXT NOT NULL,
  REFERRAL_HOSP_NAME TEXT NOT NULL,
  REFERRAL_DEPT_NAME TEXT,
  CONSULTATION_DATE TEXT,
  CONSULTATION_DESC TEXT,
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

  /// 构造一条合法初筛记录草稿（医院 1 儿童 1、12 月龄、无转诊）。
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
    hasReferral: hasReferral,
    referralHospId: referralHospId,
    referralHospName: referralHospName,
    referralDeptId: referralDeptId,
    referralDeptName: referralDeptName,
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
  });

  test('save：有转诊时医院名称必填、ID/科室随入参落库', () async {
    final saved = await saveDraft(
      draft(
        hasReferral: '1',
        checkResult: InitialScreeningService.checkResultAbnormal,
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
      draft(warning: '不会挥手表示“再见”或拍手表示“欢迎”', languageSocial: '语言功能障碍或倒退', checkResult: InitialScreeningService.checkResultAbnormal, correctedYear: 1, correctedMonth: 2, correctedDay: 3),
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

  test('save：校验失败不落库', () async {
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
    // 初筛结果为空
    await expectLater(saveDraft(draft(checkResult: '  ')), throwsA(predicate((e) => e is AsdException && e.code == 40002)));
    // 有无转诊取值非法
    await expectLater(saveDraft(draft(hasReferral: '2')), throwsA(predicate((e) => e is AsdException && e.code == 40002)));
    // 有转诊但医院名称为空
    await expectLater(saveDraft(draft(hasReferral: '1')), throwsA(predicate((e) => e is AsdException && e.message.contains('转诊医院名称'))));
    // 预警征象为空 / 超出字节上限
    await expectLater(saveDraft(draft(warning: '')), throwsA(predicate((e) => e is AsdException && e.message.contains('预警征象'))));
    final longWarning = '不会挥手表示“再见”或拍手表示“欢迎”、' * 4;
    await expectLater(saveDraft(draft(warning: longWarning)), throwsA(predicate((e) => e is AsdException && e.message.contains('预警征象'))));

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

  test('save：有转诊自动写 CHILD_REFERRAL（TYPE=1、原因默认、同儿童同日同键更新）', () async {
    final saved = await saveDraft(
      draft(hasReferral: '1', referralHospName: '市儿童医院', referralDeptName: '儿童康复科'),
    );
    final rows = await db.query(
      'SELECT ID, CHILD_ID, REFERRAL_DATE, REFERRAL_TYPE, REFERRAL_REASON, '
      'REFERRAL_HOSP_NAME, REFERRAL_DEPT_NAME, CREATOR_ID, DEPT_ID, HOSP_ID, UPDATE_TIME '
      'FROM CHILD_REFERRAL',
    );
    expect(rows.rowsAsMaps, hasLength(1));
    final row = rows.rowsAsMaps.single;
    expect(row['CHILD_ID'], child1Id);
    expect(row['REFERRAL_DATE'], '2026-11-23');
    expect(row['REFERRAL_TYPE'], '1');
    expect(row['REFERRAL_REASON'], InitialScreeningService.initialReferralReason);
    expect(row['REFERRAL_HOSP_NAME'], '市儿童医院');
    expect(row['REFERRAL_DEPT_NAME'], '儿童康复科');
    expect(row['CREATOR_ID'], operator1Id);
    expect(row['DEPT_ID'], dept1Id);
    expect(row['HOSP_ID'], hosp1Id);
    expect(row['UPDATE_TIME'], isNull);

    // 同儿童同日再保存（同键覆盖）→ 更新同一条而非新增
    await saveDraft(
      draft(hasReferral: '1', referralHospName: '省儿童医院'),
    );
    final after = await db.query('SELECT ID, REFERRAL_HOSP_NAME, REFERRAL_DEPT_NAME, UPDATE_TIME FROM CHILD_REFERRAL');
    expect(after.rowsAsMaps, hasLength(1));
    expect(after.rowsAsMaps.single['ID'], row['ID']);
    expect(after.rowsAsMaps.single['REFERRAL_HOSP_NAME'], '省儿童医院');
    expect(after.rowsAsMaps.single['REFERRAL_DEPT_NAME'], isNull);
    expect(after.rowsAsMaps.single['UPDATE_TIME'], isNotNull);

    // 改判检查日期 → 生成新一天的转诊（旧日期记录保留）
    const moved = InitialScreening(
      childId: child1Id,
      checkDate: '2026-11-24',
      ageYear: 1,
      ageMonth: 0,
      ageDay: 6,
      checkMonth: 12,
      warningSignResult: '未见异常',
      languageSocialCommunicationResult: '未见异常',
      checkResult: '异常',
      hasReferral: '1',
      referralHospName: '市儿童医院',
      doctorId: doctor1Id,
      doctorName: '王心怡',
      creatorId: operator1Id,
      creatorName: '测试员',
      hospId: hosp1Id,
      hospName: '示例人民医院',
    );
    await service.save(record: moved, operatorId: operator1Id, operatorName: '测试员', hospId: hosp1Id, hospName: '示例人民医院', deptId: dept1Id, deptName: '儿童保健科');
    final both = await db.query('SELECT REFERRAL_DATE FROM CHILD_REFERRAL ORDER BY REFERRAL_DATE');
    expect(both.rowsAsMaps.map((r) => r['REFERRAL_DATE']).toList(), ['2026-11-23', '2026-11-24']);
    expect(saved.id, isNotNull);
  });

  test('save：无转诊不写 CHILD_REFERRAL；改判无转诊保留已生成记录', () async {
    await saveDraft(
      draft(hasReferral: '1', referralHospName: '市儿童医院'),
    );
    expect((await db.query('SELECT ID FROM CHILD_REFERRAL')).rows, hasLength(1));
    // 改回无转诊：转诊记录不回溯删除
    await saveDraft(draft());
    expect((await db.query('SELECT ID FROM CHILD_REFERRAL')).rows, hasLength(1));
    // 纯无转诊保存：不产生转诊记录
    await saveDraft(draft(checkMonth: 24));
    expect((await db.query('SELECT ID FROM CHILD_REFERRAL')).rows, hasLength(1));
  });

  test('listDoctors：同科室启用医生，排除其他科室/类别/停用；科室为空返回空', () async {
    final doctors = await service.listDoctors(dept1Id);
    expect(doctors.map((d) => d.id), [doctor1Id]); // 排除心理科/护士/停用
    expect(doctors.single.userName, '王心怡');
    expect(await service.listDoctors(''), isEmpty);
  });
}
