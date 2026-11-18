import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/high_risk_factor_service.dart';
import 'package:test/test.dart';

// 种子数据固定 UUID（任意 36 位字符串均可作 TEXT/CHAR(36) 主键值，固定值
// 便于跨行引用；按字符串序排好，保证「ORDER BY ID」类排序断言稳定）。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 示例儿童医院
const creator1Id = 'b0000000-0000-0000-0000-000000000009'; // 张三
const creator2Id = 'b0000000-0000-0000-0000-000000000008'; // 李四
const factor1Id = 'e0000000-0000-0000-0000-000000000001'; // 感染/新生儿/早发败血症（医院 1）
const factor2Id = 'e0000000-0000-0000-0000-000000000002'; // 无大类/无小类/低出生体重（医院 1）
const factor3Id = 'e0000000-0000-0000-0000-000000000003'; // 感染/新生儿/早发败血症（医院 2，编码跨院重复）

/// 不存在的 ID 取值（UUID 主键不校验格式，任意非空未知取值统一走「不存在」）。
const unknownId = '99999999-9999-9999-9999-999999999999';

/// UUID v7 主键形态（36 位连字符形式）。
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// 高危因素字典服务单元测试（SQLite :memory:）：医院隔离列表、详情、
/// 新增校验与 UUID 主键回读、同医院编码唯一、字段级修改与可空列清空、
/// 颜色/分值校验、删除。
void main() {
  late SqliteGateway db;
  late HighRiskFactorService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE BASE_HIGH_RISK_FACTOR (
  ID TEXT PRIMARY KEY NOT NULL,
  RISK_FACTOR_CATEGORY TEXT, -- 大类
  RISK_FACTOR_SUBCATEGORY TEXT, -- 小类
  RISK_FACTOR_CODE TEXT NOT NULL, -- 高危因素编码
  RISK_FACTOR_NAME TEXT NOT NULL, -- 高危因素名称
  RISK_COLOR TEXT, -- 高危颜色
  RISK_LEVEL TEXT, -- 高危等级
  RISK_SCORE INTEGER, -- 高危分值
  CREATOR_ID TEXT NOT NULL, -- 创建人ID
  CREATOR_NAME TEXT NOT NULL, -- 创建人姓名
  HOSP_ID TEXT NOT NULL, -- 医院ID
  HOSP_NAME TEXT NOT NULL, -- 医院名称
  CREATE_TIME TEXT NOT NULL, -- 创建时间
  UPDATE_TIME TEXT -- 更新时间
)''');
    Future<void> seed(
      String id,
      String? category,
      String? subcategory,
      String code,
      String name,
      String? color,
      String? level,
      int? score,
      String hospId,
      String hospName,
      String creatorName,
      String creatorId,
    ) async {
      await db.execute(
        'INSERT INTO BASE_HIGH_RISK_FACTOR (ID, RISK_FACTOR_CATEGORY, '
        'RISK_FACTOR_SUBCATEGORY, RISK_FACTOR_CODE, RISK_FACTOR_NAME, '
        'RISK_COLOR, RISK_LEVEL, RISK_SCORE, CREATOR_ID, CREATOR_NAME, '
        'HOSP_ID, HOSP_NAME, CREATE_TIME) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, category, subcategory, code, name, color, level, score, creatorId, creatorName, hospId, hospName, '2026-11-18 10:00:00'],
      );
    }

    await seed(factor1Id, '感染', '新生儿', 'R001', '早发败血症', '红色', 'Ⅲ', 10, hosp1Id, '示例人民医院', '张三', creator1Id);
    await seed(factor2Id, null, null, 'R002', '低出生体重', '黄色', 'Ⅱ', 5, hosp1Id, '示例人民医院', '张三', creator1Id);
    await seed(factor3Id, '感染', '新生儿', 'R001', '早发败血症', '红色', 'Ⅲ', 10, hosp2Id, '示例儿童医院', '李四', creator2Id);
    service = HighRiskFactorService(db);
  });

  tearDown(() {
    db.close();
  });

  test('listByHospital：按医院隔离返回；hospId 为空返回空列表', () async {
    final hosp1 = await service.listByHospital(hosp1Id);
    expect(hosp1.map((f) => f.id), [factor1Id, factor2Id]);
    expect(hosp1.first.riskFactorCategory, '感染');
    expect(hosp1.first.riskColor, '红色');
    expect(hosp1.last.riskFactorCategory, isNull);

    final hosp2 = await service.listByHospital(hosp2Id);
    expect(hosp2.map((f) => f.id), [factor3Id]);
    expect(hosp2.first.hospName, '示例儿童医院');

    expect(await service.listByHospital(''), isEmpty);
    expect(await service.listByHospital('  '), isEmpty);
    // 医院 ID 不校验格式，未知取值查不到数据返回空列表
    expect(await service.listByHospital('abc'), isEmpty);
  });

  test('getById：查详情；未知 ID 报不存在', () async {
    final factor = await service.getById(factor1Id);
    expect(factor.riskFactorCode, 'R001');
    expect(factor.riskFactorSubcategory, '新生儿');
    expect(factor.riskLevel, 'Ⅲ');
    expect(factor.riskScore, '10');
    expect(factor.creatorName, '张三');

    // UUID 主键不校验格式：任意非空未知取值统一走「不存在」（40001）
    await expectLater(
      service.getById(unknownId),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('不存在'))),
    );
    await expectLater(
      service.getById('abc'),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });

  test('create：全字段新增成功，返回新生成的 UUID 主键', () async {
    final factor = await service.create(
      riskFactorCategory: '遗传代谢',
      riskFactorSubcategory: '先天畸形',
      riskFactorCode: 'R003',
      riskFactorName: '先天性心脏病',
      riskColor: '橙色',
      riskLevel: 'Ⅰ',
      riskScore: '8',
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(factor.id, matches(_uuidPattern));
    expect(factor.riskFactorCategory, '遗传代谢');
    expect(factor.riskFactorSubcategory, '先天畸形');
    expect(factor.riskFactorCode, 'R003');
    expect(factor.riskFactorName, '先天性心脏病');
    expect(factor.riskColor, '橙色');
    expect(factor.riskLevel, 'Ⅰ');
    expect(factor.riskScore, '8');
    expect(factor.hospId, hosp1Id);
    expect(factor.creatorId, creator1Id);
    expect(factor.createTime, isNotNull);
    expect(factor.updateTime, isNull);

    // 回读同值
    final reloaded = await service.getById(factor.id);
    expect(reloaded.riskFactorName, '先天性心脏病');
  });

  test('create：可空字段留空归一为 null', () async {
    final factor = await service.create(
      riskFactorCategory: '  ',
      riskFactorCode: 'R004',
      riskFactorName: '无分类因素',
      riskColor: '',
      riskLevel: '',
      riskScore: '',
      hospId: hosp1Id,
      hospName: '示例人民医院',
      creatorId: creator1Id,
      creatorName: '张三',
    );
    expect(factor.riskFactorCategory, isNull);
    expect(factor.riskFactorSubcategory, isNull);
    expect(factor.riskColor, isNull);
    expect(factor.riskLevel, isNull);
    expect(factor.riskScore, isNull);
  });

  test('create：编码同医院内唯一、跨医院可重复', () async {
    // 医院 1 已有 R001
    await expectLater(
      service.create(
        riskFactorCode: 'R001',
        riskFactorName: '重复编码',
        hospId: hosp1Id,
        hospName: '示例人民医院',
        creatorId: creator1Id,
        creatorName: '张三',
      ),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('该医院下高危因素编码已存在'))),
    );

    // 医院 1 与医院 2 各自拥有 R001，互不影响
    expect((await service.listByHospital(hosp2Id)).single.riskFactorCode, 'R001');
  });

  test('create：必填、颜色与分值校验', () async {
    Future<void> expectInvalid({required String message, String? code, String? name, String? color, String? score}) {
      return expectLater(
        service.create(
          riskFactorCode: code ?? 'R900',
          riskFactorName: name ?? '校验因素',
          riskColor: color,
          riskScore: score,
          hospId: hosp1Id,
          hospName: '示例人民医院',
          creatorId: creator1Id,
          creatorName: '张三',
        ),
        throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains(message))),
      );
    }

    await expectInvalid(code: '  ', message: '高危因素编码不能为空');
    await expectInvalid(name: '  ', message: '高危因素名称不能为空');
    await expectInvalid(code: 'R' * 21, message: '高危因素编码不能超过');
    await expectInvalid(name: '因' * 201, message: '高危因素名称不能超过');
    await expectInvalid(color: '蓝色', message: '高危颜色应为');
    await expectInvalid(score: '-1', message: '高危分值应为');
    await expectInvalid(score: '128', message: '高危分值应为');
    await expectInvalid(score: 'abc', message: '高危分值应为');
  });

  test('update：字段级修改；null 清空可空列；必填列不可清空', () async {
    final updated = await service.update(factor1Id, {
      'riskFactorCategory': '代谢',
      'riskFactorSubcategory': null,
      'riskFactorName': '早发败血症（修改）',
      'riskColor': '橙色',
      'riskLevel': 'Ⅱ',
      'riskScore': '15',
    });
    expect(updated.riskFactorCategory, '代谢');
    expect(updated.riskFactorSubcategory, isNull);
    expect(updated.riskFactorName, '早发败血症（修改）');
    expect(updated.riskColor, '橙色');
    expect(updated.riskLevel, 'Ⅱ');
    expect(updated.riskScore, '15');
    expect(updated.updateTime, isNotNull);

    // 必填列清空 → 报错
    await expectLater(
      service.update(factor1Id, {'riskFactorCode': null}),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('高危因素编码不能为空'))),
    );
    await expectLater(
      service.update(factor1Id, {'riskFactorName': '  '}),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('高危因素名称不能为空'))),
    );
    // 非白名单字段
    await expectLater(
      service.update(factor1Id, {'hospId': hosp2Id}),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('不支持的修改字段'))),
    );
    // 空 changes 不写库
    expect((await service.update(factor1Id, const {})).riskFactorName, '早发败血症（修改）');
  });

  test('update：编码同医院内唯一（排除自身）', () async {
    await expectLater(
      service.update(factor1Id, {'riskFactorCode': 'R002'}),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('该医院下高危因素编码已存在'))),
    );
    // 改为自身编码允许
    final same = await service.update(factor1Id, {'riskFactorCode': 'R001'});
    expect(same.riskFactorCode, 'R001');
  });

  test('delete：删除成功；不存在报错', () async {
    expect(await service.delete(factor2Id), 1);
    expect((await service.listByHospital(hosp1Id)).map((f) => f.id), [factor1Id]);

    await expectLater(
      service.delete(factor2Id),
      throwsA(isA<HighRiskFactorException>().having((e) => e.message, 'message', contains('不存在'))),
    );
  });
}
