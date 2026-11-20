import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/high_risk_factor_exclusion_service.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（固定值便于跨行引用；按字符串序排好，保证
// 「ORDER BY ID」类排序断言稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 示例儿童医院
const creator1Id = 'b0000000-0000-0000-0000-000000000009'; // 张三
const factor1Id = 'e0000000-0000-0000-0000-000000000001'; // 早产（医院 1）
const factor2Id = 'e0000000-0000-0000-0000-000000000002'; // 低出生体重（医院 1）
const factor3Id = 'e0000000-0000-0000-0000-000000000003'; // 新生儿窒息（医院 1）
const factor4Id = 'e0000000-0000-0000-0000-000000000004'; // 早产（医院 2）
const factor5Id = 'e0000000-0000-0000-0000-000000000005'; // 颅内出血（医院 1）
const factor6Id = 'e0000000-0000-0000-0000-000000000006'; // 低出生体重（医院 2）

/// 不存在的 ID 取值（UUID 主键不校验格式，任意非空未知取值统一走「不存在」）。
const unknownId = '99999999-9999-9999-9999-999999999999';

/// UUID v7 主键形态（36 位连字符形式）。
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 高危因素互斥规则服务单元测试（SQLite :memory:）：医院隔离列表、
/// 详情、新增校验与 UUID 主键回读、因素存在性/同院校验、组合无序唯一、
/// 字段级修改与第三项清空、删除。
void main() {
  late SqliteGateway db;
  late HighRiskFactorExclusionService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE BASE_HIGH_RISK_FACTOR (
  ID TEXT PRIMARY KEY NOT NULL, -- 主键
  RISK_FACTOR_CODE TEXT NOT NULL, -- 高危因素编码
  RISK_FACTOR_NAME TEXT NOT NULL, -- 高危因素名称
  CREATOR_ID TEXT NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID TEXT NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL -- 创建时间
)''');
    await db.executeDirect('''
CREATE TABLE BASE_HIGH_RISK_FACTOR_EXCLUSION (
  ID TEXT PRIMARY KEY NOT NULL, -- 主键
  FIRST_RISK_FACTOR_ID TEXT NOT NULL, -- 第一个高危因素ID
  SECOND_RISK_FACTOR_ID TEXT NOT NULL, -- 第二个高危因素ID
  THIRD_RISK_FACTOR_ID TEXT, -- 第三个高危因素ID
  CREATOR_ID TEXT NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID TEXT NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');

    Future<void> seedFactor(String id, String name, String hospId, String hospName) async {
      await db.execute(
        'INSERT INTO BASE_HIGH_RISK_FACTOR (ID, RISK_FACTOR_CODE, '
        'RISK_FACTOR_NAME, CREATOR_ID, CREATOR_NAME, HOSP_ID, HOSP_NAME, '
        'CREATE_TIME) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, 'R${id.substring(id.length - 1)}', name, creator1Id, '张三', hospId, hospName, '2026-11-20 10:00:00'],
      );
    }

    await seedFactor(factor1Id, '早产', hosp1Id, '示例人民医院');
    await seedFactor(factor2Id, '低出生体重', hosp1Id, '示例人民医院');
    await seedFactor(factor3Id, '新生儿窒息', hosp1Id, '示例人民医院');
    await seedFactor(factor5Id, '新生儿颅内出血', hosp1Id, '示例人民医院');
    await seedFactor(factor4Id, '早产', hosp2Id, '示例儿童医院');
    await seedFactor(factor6Id, '低出生体重', hosp2Id, '示例儿童医院');
    service = HighRiskFactorExclusionService(db);
  });

  tearDown(() {
    db.close();
  });

  /// 新增医院 1 的「早产 + 低出生体重」规则。
  Future<void> seedRule() async {
    await service.create(
      firstRiskFactorId: factor1Id,
      secondRiskFactorId: factor2Id,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
  }

  test('listByHospital：按医院隔离返回；hospId 为空返回空列表', () async {
    await seedRule();
    final hosp1 = await service.listByHospital(hosp1Id);
    expect(hosp1, hasLength(1));
    expect(hosp1.single.firstRiskFactorId, factor1Id);
    expect(hosp1.single.secondRiskFactorId, factor2Id);
    expect(hosp1.single.thirdRiskFactorId, isNull);

    expect(await service.listByHospital(hosp2Id), isEmpty);
    expect(await service.listByHospital(''), isEmpty);
    expect(await service.listByHospital('  '), isEmpty);
    // 医院 ID 不校验格式，未知取值查不到数据返回空列表
    expect(await service.listByHospital('abc'), isEmpty);
  });

  test('getById：查详情；未知 ID 报不存在', () async {
    await seedRule();
    final id = (await service.listByHospital(hosp1Id)).single.id;
    final rule = await service.getById(id);
    expect(rule.hospId, hosp1Id);
    expect(rule.hospName, '示例人民医院');
    expect(rule.creatorId, creator1Id);
    expect(rule.creatorName, '张三');
    expect(rule.createTime, isNotNull);
    expect(rule.updateTime, isNull);

    await expectLater(
      service.getById(unknownId),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：两项/三项规则成功，返回新生成的 UUID 主键', () async {
    final two = await service.create(
      firstRiskFactorId: factor1Id,
      secondRiskFactorId: factor2Id,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(two.id, matches(_uuidPattern));
    expect(two.riskFactorIds, [factor1Id, factor2Id]);
    expect(two.thirdRiskFactorId, isNull);

    final three = await service.create(
      firstRiskFactorId: factor1Id,
      secondRiskFactorId: factor2Id,
      thirdRiskFactorId: factor3Id,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(three.riskFactorIds, [factor1Id, factor2Id, factor3Id]);
    expect((await service.listByHospital(hosp1Id)).map((r) => r.id), [two.id, three.id]);
  });

  test('create：必填项与重复项校验', () async {
    Future<void> expectInvalid({required String message, String? first, String? second, String? third}) {
      return expectLater(
        service.create(
          firstRiskFactorId: first ?? factor1Id,
          secondRiskFactorId: second ?? factor2Id,
          thirdRiskFactorId: third,
          hospId: hosp1Id,
          hospName: '示例人民医院',
          creatorId: creator1Id,
          creatorName: '张三',
        ),
        throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains(message))),
      );
    }

    await expectInvalid(first: '  ', message: '第一个高危因素ID不能为空');
    await expectInvalid(second: '  ', message: '第二个高危因素ID不能为空');
    await expectInvalid(third: factor1Id, message: '不能重复');
    await expectInvalid(second: factor1Id, message: '不能重复');
  });

  test('create：高危因素须存在且属于同一医院', () async {
    await expectLater(
      service.create(
        firstRiskFactorId: factor1Id,
        secondRiskFactorId: unknownId,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('高危因素不存在'))),
    );

    // 他院因素不可用于本院规则
    await expectLater(
      service.create(
        firstRiskFactorId: factor1Id,
        secondRiskFactorId: factor4Id,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('不属于当前医院'))),
    );
  });

  test('create：组合无序唯一（A+B 与 B+A 视为同一规则），跨院互不影响', () async {
    await seedRule();
    await expectLater(
      service.create(
        firstRiskFactorId: factor2Id,
        secondRiskFactorId: factor1Id,
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('互斥规则已存在'))),
    );

    // 三项规则包含两项规则的不同组合，允许
    final three = await service.create(
      firstRiskFactorId: factor1Id,
      secondRiskFactorId: factor2Id,
      thirdRiskFactorId: factor3Id,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(three.thirdRiskFactorId, factor3Id);

    // 医院 2 可建立自己的两项规则（唯一性按医院隔离）
    final other = await service.create(
      firstRiskFactorId: factor4Id,
      secondRiskFactorId: factor6Id,
      hospId: hosp2Id,
      hospName: '示例儿童医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(other.hospId, hosp2Id);
  });

  test('update：字段级修改、第三项清空、更新时间', () async {
    final rule = await service.create(
      firstRiskFactorId: factor1Id,
      secondRiskFactorId: factor2Id,
      thirdRiskFactorId: factor3Id,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );

    final updated = await service.update(rule.id, {
      'secondRiskFactorId': factor5Id,
      'thirdRiskFactorId': null,
    });
    expect(updated.firstRiskFactorId, factor1Id);
    expect(updated.secondRiskFactorId, factor5Id);
    expect(updated.thirdRiskFactorId, isNull);
    expect(updated.updateTime, isNotNull);

    // 空 changes 不写库
    expect((await service.update(rule.id, const {})).secondRiskFactorId, factor5Id);
    // 非白名单字段
    await expectLater(
      service.update(rule.id, {'hospId': hosp2Id}),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
  });

  test('update：组合唯一排除自身；修改为已有组合报错', () async {
    await seedRule(); // 早产 + 低出生体重
    final second = await service.create(
      firstRiskFactorId: factor1Id,
      secondRiskFactorId: factor3Id,
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );

    // 修改为另一条规则的组合 → 报错（当前为 早产 + 新生儿窒息，
    // 把第二项改为低出生体重即与种子规则「早产 + 低出生体重」相同）
    await expectLater(
      service.update(second.id, {'secondRiskFactorId': factor2Id}),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('互斥规则已存在'))),
    );

    // 自身改回自身组合允许（前后两项互换仍视为同一组合）
    final same = await service.update(second.id, {'firstRiskFactorId': factor3Id, 'secondRiskFactorId': factor1Id});
    expect(same.riskFactorIds, [factor3Id, factor1Id]);
  });

  test('delete：删除成功；不存在报错', () async {
    await seedRule();
    final id = (await service.listByHospital(hosp1Id)).single.id;
    expect(await service.delete(id), 1);
    expect(await service.listByHospital(hosp1Id), isEmpty);

    await expectLater(
      service.delete(id),
      throwsA(isA<HighRiskFactorExclusionException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
