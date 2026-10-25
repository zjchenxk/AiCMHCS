import 'dart:convert';

import 'package:server/database/engine/sqlite/sqlite_gateway.dart';
import 'package:server/database/migrator/schema_migrator.dart';
import 'package:server/services/operation_log_service.dart';
import 'package:server/utils/field_cipher.dart';
import 'package:server/utils/log_helper.dart';
import 'package:test/test.dart';

import '../support/test_divisions.dart';

void main() {
  final cipher = FieldCipher.fromMasterKeyBase64(
    base64Encode(utf8.encode('0123456789abcdef0123456789abcdef')),
  );

  late SqliteGateway db;
  late OperationLogService service;
  late String divisionsDir;

  setUp(() async {
    divisionsDir = setUpTestDivisionsCsv();
    db = await SqliteGateway.start(':memory:');
    await SchemaMigrator(db, fieldCipher: cipher).migrate();
    service = OperationLogService(db);
  });

  tearDown(() {
    db.close();
    clearTestDivisionsCsv(divisionsDir);
  });

  /// 查询最新一条日志（按 ID 倒序）。
  Future<Map<String, String?>> lastRow() async {
    final result = await db.query(
      'SELECT USER_ID, LOG_TYPE, LOG_NAME, LOG_CONTENT, LOG_TIME '
      'FROM SYS_OPERATION_LOG ORDER BY ID DESC LIMIT 1',
    );
    return result.rowsAsMaps.first;
  }

  test('add：写入全字段（userId 为空合法）', () async {
    await service.add(
      logType: OperationLogService.typeError,
      logName: 'client:AdminDivisionManagementViewModel.loadRoots',
      logContent: 'Bad state: 加载失败\n#0      main (file.dart:1:1)',
    );

    final row = await lastRow();
    expect(row['USER_ID'], isNull);
    expect(row['LOG_TYPE'], '错误');
    expect(row['LOG_NAME'], 'client:AdminDivisionManagementViewModel.loadRoots');
    expect(row['LOG_CONTENT'], contains('加载失败'));
    // 时间为本地时间文本（YYYY-MM-DD HH:MM:SS）。
    expect(row['LOG_TIME'], matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
  });

  test('add：userId 与日志内容为空均可写入', () async {
    await service.add(
      userId: 1,
      logType: OperationLogService.typeInfo,
      logName: '/api/admin-divisions',
    );

    final row = await lastRow();
    expect(row['USER_ID'], '1');
    expect(row['LOG_TYPE'], '信息');
    expect(row['LOG_CONTENT'], isNull);
  });

  test('超长内容截断：LOG_CONTENT 4000 字符、LOG_NAME 240 字符', () async {
    await service.add(
      logType: OperationLogService.typeWarn,
      logName: 'N' * 300,
      logContent: 'C' * 5000,
    );

    final row = await lastRow();
    expect(row['LOG_NAME']!.length, 241); // 240 + 省略号
    expect(row['LOG_NAME']!.endsWith('…'), isTrue);
    expect(row['LOG_CONTENT']!.length, 4001); // 4000 + 省略号
    expect(row['LOG_CONTENT']!.endsWith('…'), isTrue);
  });

  test('中文内容（含非 ASCII）正常写入与读回', () async {
    const content = '异常：新增行政区划失败，编码重复（110000）';
    await service.add(
      userId: 2,
      logType: OperationLogService.typeError,
      logName: 'server:AdminDivisionService.create',
      logContent: content,
    );

    final row = await lastRow();
    expect(row['LOG_CONTENT'], content);
    expect(row['LOG_NAME'], 'server:AdminDivisionService.create');
  });

  test('LogHelper：写入失败不抛异常（表不存在时吞错，防递归）', () async {
    // 未迁移的空库：插入必然失败，LogHelper 必须吞掉而非上抛。
    final emptyDb = await SqliteGateway.start(':memory:');
    LogHelper.service = OperationLogService(emptyDb);
    addTearDown(emptyDb.close);

    await LogHelper.error('server:X.y', StateError('boom'), StackTrace.current);
    await LogHelper.info('server:X.z', content: 'hello', userId: 9);
  });
}
