import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/services/initial_screening_guidance_service.dart';
import 'package:server/services/initial_screening_service.dart';
import 'package:test/test.dart';

// 种子固定 UUID。
const hosp1Id = 'a0000000-0000-0000-0000-000000000001'; // 示例人民医院
const hosp2Id = 'a0000000-0000-0000-0000-000000000002'; // 示例儿童医院
const user1Id = 'b0000000-0000-0000-0000-000000000001'; // 甲医生（医院 1）
const user2Id = 'b0000000-0000-0000-0000-000000000002'; // 乙医生（医院 1）
const user3Id = 'b0000000-0000-0000-0000-000000000003'; // 丙医生（医院 2）

/// 指导建议模板服务单元测试（SQLite :memory:）：可见性（公共+本人）、
/// 新增归属随会话、仅创建人可改删、字节限长。
void main() {
  late SqliteGateway db;
  late InitialScreeningGuidanceService service;

  setUp(() async {
    db = await SqliteGateway.start(':memory:');
    await db.executeDirect('''
CREATE TABLE ASD_INITIAL_SCREENING_GUIDANCE (
  ID TEXT PRIMARY KEY NOT NULL,
  GUIDANCE TEXT NOT NULL,
  GUIDANCE_TYPE TEXT NOT NULL,
  IS_PERSONAL TEXT NOT NULL,
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
    service = InitialScreeningGuidanceService(db);
  });

  tearDown(() {
    db.close();
  });

  /// 新增一条模板（医院 1、甲医生）。
  Future<String> addTemplate({String guidance = '请定期复查', String type = '常规指导', String isPersonal = '1', String userId = user1Id}) async {
    final t = await service.create(
      guidance: guidance,
      guidanceType: type,
      isPersonal: isPersonal,
      operatorId: userId,
      operatorName: '甲医生',
      hospId: hosp1Id,
      hospName: '示例人民医院',
    );
    return t.id;
  }

  test('create + listByHospital：公共模板全院可见、个人模板仅本人可见', () async {
    await addTemplate(guidance: '公共模板-ABC', isPersonal: '0', userId: user1Id);
    await addTemplate(guidance: '甲的个人模板', isPersonal: '1', userId: user1Id);
    await addTemplate(guidance: '乙的个人模板', isPersonal: '1', userId: user2Id);

    final forUser1 = await service.listByHospital(hosp1Id, user1Id);
    expect(forUser1.map((t) => t.guidance).toSet(), {'公共模板-ABC', '甲的个人模板'});
    final forUser2 = await service.listByHospital(hosp1Id, user2Id);
    expect(forUser2.map((t) => t.guidance).toSet(), {'公共模板-ABC', '乙的个人模板'});
    // 跨院不可见
    expect(await service.listByHospital(hosp2Id, user1Id), isEmpty);
    // 空参数返回空
    expect(await service.listByHospital('', user1Id), isEmpty);
    expect(await service.listByHospital(hosp1Id, ''), isEmpty);
  });

  test('create：归属与创建人随会话，默认个人模板', () async {
    final t = await service.create(
      guidance: '内容',
      guidanceType: '类别',
      isPersonal: '1',
      operatorId: user1Id,
      operatorName: '甲医生',
      hospId: hosp1Id,
      hospName: '示例人民医院',
      deptId: 'dept-1',
      deptName: '儿童保健科',
    );
    expect(t.creatorId, user1Id);
    expect(t.creatorName, '甲医生');
    expect(t.hospId, hosp1Id);
    expect(t.deptId, 'dept-1');
    expect(t.isPersonal, '1');
    expect(t.createTime, isNotNull);
  });

  test('update/delete：仅创建人本人，他人模板提示不能修改/删除', () async {
    final id = await addTemplate();
    // 他人修改/删除
    await expectLater(
      service.update(id: id, guidance: '改', guidanceType: '类', isPersonal: '1', operatorId: user2Id, hospId: hosp1Id),
      throwsA(predicate((e) => e is AsdException && e.message == '不能修改他人的指导建议')),
    );
    await expectLater(
      service.delete(id, user2Id, hosp1Id),
      throwsA(predicate((e) => e is AsdException && e.message == '不能修改他人的指导建议')),
    );
    // 本人修改
    final updated = await service.update(id: id, guidance: '改后内容', guidanceType: '新类别', isPersonal: '0', operatorId: user1Id, hospId: hosp1Id);
    expect(updated.guidance, '改后内容');
    expect(updated.guidanceType, '新类别');
    expect(updated.isPersonal, '0');
    expect(updated.updateTime, isNotNull);
    // 本人删除
    expect(await service.delete(id, user1Id, hosp1Id), 1);
    expect(await service.listByHospital(hosp1Id, user1Id), isEmpty);
    // 不存在 / 跨院
    await expectLater(
      service.delete(id, user1Id, hosp1Id),
      throwsA(predicate((e) => e is AsdException && e.message == '指导建议模板不存在')),
    );
    final other = await addTemplate(guidance: '医院 1 模板');
    await expectLater(
      service.delete(other, user1Id, hosp2Id),
      throwsA(predicate((e) => e is AsdException && e.message == '指导建议模板不存在')),
    );
  });

  test('校验：内容/类别必填、个人标记取值、内容字节限长', () async {
    await expectLater(
      service.create(guidance: '  ', guidanceType: '类', isPersonal: '1', operatorId: user1Id, operatorName: '甲', hospId: hosp1Id, hospName: '示例人民医院'),
      throwsA(predicate((e) => e is AsdException && e.message == '指导建议不能为空')),
    );
    await expectLater(
      service.create(guidance: '内容', guidanceType: ' ', isPersonal: '1', operatorId: user1Id, operatorName: '甲', hospId: hosp1Id, hospName: '示例人民医院'),
      throwsA(predicate((e) => e is AsdException && e.message == '指导建议类别不能为空')),
    );
    await expectLater(
      service.create(guidance: '内容', guidanceType: '类', isPersonal: '2', operatorId: user1Id, operatorName: '甲', hospId: hosp1Id, hospName: '示例人民医院'),
      throwsA(predicate((e) => e is AsdException && e.message.contains('是否个人模板'))),
    );
    await expectLater(
      service.create(guidance: '长' * 400, guidanceType: '类', isPersonal: '1', operatorId: user1Id, operatorName: '甲', hospId: hosp1Id, hospName: '示例人民医院'),
      throwsA(predicate((e) => e is AsdException && e.message.contains('指导建议超出长度限制'))),
    );
  });
}
