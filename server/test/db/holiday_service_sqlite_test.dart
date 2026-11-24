import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/holiday_service.dart';
import 'package:test/test.dart';

// 种子数据固定 ID（自增表允许显式插入整数主键，固定值便于排序断言稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 示例儿童医院
const creator1Id = 'b0000000-0000-0000-0000-000000000009'; // 张三

/// 不存在的 ID 取值（自增主键以字符串经网关取回，非空未知取值统一走「不存在」）。
const unknownId = '99999999';

/// 法定节假日服务单元测试（SQLite :memory:）：新增回读、入参校验
/// （类型取值/日期格式/先后顺序）、医院隔离列表与排序、详情、部分
/// 字段修改与 UPDATE_TIME、删除。
void main() {
  late SqliteGateway db;
  late HolidayService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE BASE_HOLIDAY (
  ID INTEGER PRIMARY KEY AUTOINCREMENT, -- 主键（自增）
  START_DATE TEXT NOT NULL, -- 起始日期
  END_DATE TEXT NOT NULL, -- 截止日期
  HOLIDAY_TYPE INTEGER NOT NULL, -- 节假日类型
  CREATOR_ID TEXT NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID TEXT NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    service = HolidayService(db);
  });

  tearDown(() {
    db.close();
  });

  /// 直接插入一条节假日（测试种子，绕过服务层校验）。
  Future<void> seedHoliday({
    required String hospId,
    required String hospName,
    required String startDate,
    required String endDate,
    int holidayType = 1,
    String creatorName = '张三',
  }) async {
    await db.execute(
      'INSERT INTO BASE_HOLIDAY (START_DATE, END_DATE, HOLIDAY_TYPE, '
      'CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, CREATE_TIME) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [startDate, endDate, holidayType, creator1Id, creatorName, hospId, hospName, '2026-11-24 10:00:00'],
    );
  }

  /// 新增医院 1 的 2027 年元旦。
  Future<void> seedViaCreate() async {
    await service.create(
      startDate: '2027-01-01',
      endDate: '2027-01-03',
      holidayType: 1,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
  }

  test('新增后列表可查到且字段回读正确（创建人/医院冗余、UPDATE_TIME 为空）', () async {
    await seedViaCreate();
    final list = await service.listByHospital(hosp1Id);
    expect(list, hasLength(1));
    final holiday = list.single;
    expect(holiday.id, isNotEmpty);
    expect(holiday.startDate, '2027-01-01');
    expect(holiday.endDate, '2027-01-03');
    expect(holiday.holidayType, 1);
    expect(holiday.holidayTypeLabel, '元旦');
    expect(holiday.creatorId, creator1Id);
    expect(holiday.creatorName, '张三');
    expect(holiday.hospId, hosp1Id);
    expect(holiday.hospName, '示例人民医院');
    expect(holiday.createTime, isNotNull);
    expect(holiday.updateTime, isNull);
  });

  test('新增校验：类型越界、日期格式、起始晚于截止、名称缺失', () async {
    // 类型越界（0 与 9 均越界）
    expect(
      () => service.create(
        startDate: '2027-01-01',
        endDate: '2027-01-03',
        holidayType: 0,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    expect(
      () => service.create(
        startDate: '2027-01-01',
        endDate: '2027-01-03',
        holidayType: 9,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    // 日期格式非法
    expect(
      () => service.create(
        startDate: '2027/01/01',
        endDate: '2027-01-03',
        holidayType: 1,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    // 起始晚于截止
    expect(
      () => service.create(
        startDate: '2027-01-04',
        endDate: '2027-01-03',
        holidayType: 1,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    // 医院名称缺失
    expect(
      () => service.create(
        startDate: '2027-01-01',
        endDate: '2027-01-03',
        holidayType: 1,
        hospId: hosp1Id,
        hospName: '',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    // 全部被拒绝后不应留下任何数据
    expect(await service.listByHospital(hosp1Id), isEmpty);
  });

  test('医院隔离：列表只返回本院数据，未归属医院返回空列表', () async {
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2026-01-01', endDate: '2026-01-03');
    await seedHoliday(hospId: hosp2Id, hospName: '示例儿童医院', startDate: '2026-10-01', endDate: '2026-10-07', holidayType: 7);

    final hosp1 = await service.listByHospital(hosp1Id);
    expect(hosp1, hasLength(1));
    expect(hosp1.single.hospId, hosp1Id);
    expect(hosp1.single.holidayType, 1);

    final hosp2 = await service.listByHospital(hosp2Id);
    expect(hosp2, hasLength(1));
    expect(hosp2.single.holidayType, 7);

    expect(await service.listByHospital(''), isEmpty);
  });

  test('列表按起始日期倒序（同年往后追加的年份在前）', () async {
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2026-01-01', endDate: '2026-01-03');
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2027-01-01', endDate: '2027-01-03');
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2026-10-01', endDate: '2026-10-07', holidayType: 7);

    final list = await service.listByHospital(hosp1Id);
    expect(list.map((h) => h.startDate).toList(), ['2027-01-01', '2026-10-01', '2026-01-01']);
  });

  test('详情：存在按 ID 回读，不存在抛 40001', () async {
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2027-01-01', endDate: '2027-01-03');
    final holiday = await service.getById('1');
    expect(holiday.startDate, '2027-01-01');
    expect(holiday.holidayTypeLabel, '元旦');

    expect(
      () => service.getById(unknownId),
      throwsA(predicate((e) => e is HolidayException && e.code == 40001)),
    );
  });

  test('修改：仅传类型时日期沿用并刷新 UPDATE_TIME，整行校验生效', () async {
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2027-01-01', endDate: '2027-01-03');

    final updated = await service.update('1', {'holidayType': 8});
    expect(updated.startDate, '2027-01-01');
    expect(updated.endDate, '2027-01-03');
    expect(updated.holidayType, 8);
    expect(updated.holidayTypeLabel, '其它');
    expect(updated.updateTime, isNotNull);
    // 创建人与医院冗余列不可变
    expect(updated.creatorName, '张三');
    expect(updated.hospId, hosp1Id);

    // 同时改起止日期（先后顺序合法）
    final moved = await service.update('1', {'startDate': '2027-01-01', 'endDate': '2027-01-02'});
    expect(moved.endDate, '2027-01-02');
  });

  test('修改校验：未知字段、类型越界、日期倒置、记录不存在', () async {
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2027-01-01', endDate: '2027-01-03');

    // 未知字段（创建人等不在白名单）
    expect(
      () => service.update('1', {'creatorName': '李四'}),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    // 类型越界
    expect(
      () => service.update('1', {'holidayType': 9}),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    // 日期倒置（校验失败不应落库半途状态）
    expect(
      () => service.update('1', {'startDate': '2027-02-01'}),
      throwsA(predicate((e) => e is HolidayException && e.code == 40002)),
    );
    final after = await service.getById('1');
    expect(after.startDate, '2027-01-01');
    expect(after.updateTime, isNull);

    expect(
      () => service.update(unknownId, {'holidayType': 1}),
      throwsA(predicate((e) => e is HolidayException && e.code == 40001)),
    );
  });

  test('删除：返回删除行数，删除后再查不存在', () async {
    await seedHoliday(hospId: hosp1Id, hospName: '示例人民医院', startDate: '2027-01-01', endDate: '2027-01-03');

    final deleted = await service.delete('1');
    expect(deleted, 1);
    expect(
      () => service.getById('1'),
      throwsA(predicate((e) => e is HolidayException && e.code == 40001)),
    );
    expect(
      () => service.delete(unknownId),
      throwsA(predicate((e) => e is HolidayException && e.code == 40001)),
    );
  });
}
