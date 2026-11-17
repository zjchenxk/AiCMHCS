// 全局时间服务单元测试：偏移推算（取最小 RTT 采样）、同步失败静默回退
// 本地时钟、nowText 服务端同口径格式。
import 'dart:convert';

import 'package:client/services/time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 构造返回固定服务端时间的伪客户端。
MockClient mockTimeClient(int Function() epochMsOf) => MockClient((request) async {
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {'epochMs': epochMsOf(), 'serverTime': '1970-01-01 00:00:00'},
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });

void main() {
  test('sync：按服务端时间推算 now()（偏移约 5 分钟）', () async {
    final localBefore = DateTime.now();
    // 服务端比本地快 5 分钟
    final service = TimeService(
      apiUrl: 'http://test.local',
      client: mockTimeClient(() => DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch),
    );
    await service.sync();
    expect(service.isSynced, isTrue);
    // now() 应落在 [本地+5分钟, 本地+5分钟+同步耗时] 区间（容忍执行延迟）
    final now = service.now();
    expect(now.isAfter(localBefore.add(const Duration(minutes: 5))), isTrue);
    expect(now.difference(DateTime.now()).inMinutes, inInclusiveRange(4, 6));
  });

  test('sync：多次采样取往返延迟最小的一次（抵消网络抖动）', () async {
    var calls = 0;
    // 第 1/3 次「网络慢」（响应即慢 200ms）且时间值偏 1 分钟；第 2 次快
    // 且时间准——应取第 2 次样本，now() 与本地相差不超过容差
    final service = TimeService(
      apiUrl: 'http://test.local',
      client: MockClient((request) async {
        final slow = calls != 1;
        calls++;
        if (slow) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              'epochMs': DateTime.now().add(slow ? const Duration(minutes: 1) : Duration.zero).millisecondsSinceEpoch,
            },
          }),
          200,
        );
      }),
    );
    await service.sync();
    expect(service.isSynced, isTrue);
    // 若误取慢样本，now() 会比本地快约 1 分钟；取对样本则差秒级以内
    expect(service.now().difference(DateTime.now()).inSeconds, lessThan(10));
  });

  test('sync：服务不可达静默回退本地时钟，业务可用性不受阻', () async {
    final service = TimeService(
      apiUrl: 'http://test.local',
      client: MockClient((request) async => http.Response('not found', 404)),
    );
    await service.sync();
    expect(service.isSynced, isFalse);
    expect(service.now().difference(DateTime.now()).inSeconds, lessThan(2));
    // nowText 也照常可用（本地口径）
    expect(service.nowText(), matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
  });

  test('sync：响应 code 非 0 视为失败', () async {
    final service = TimeService(
      apiUrl: 'http://test.local',
      client: MockClient((request) async {
        return http.Response(jsonEncode({'code': 50000, 'message': 'x', 'data': null}), 200);
      }),
    );
    await service.sync();
    expect(service.isSynced, isFalse);
  });

  test('nowText：与服务器时间同口径（同步后为服务端文本）', () async {
    final server = DateTime.parse('2026-11-17 10:30:45');
    final service = TimeService(
      apiUrl: 'http://test.local',
      client: mockTimeClient(() => server.millisecondsSinceEpoch),
    );
    await service.sync();
    expect(service.nowText(), '2026-11-17 10:30:45');
  });

  test('startAutoSync/stopAutoSync：定时器启停', () async {
    var calls = 0;
    final service = TimeService(
      apiUrl: 'http://test.local',
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'epochMs': DateTime.now().millisecondsSinceEpoch},
          }),
          200,
        );
      }),
    );
    service.startAutoSync();
    // startAutoSync 立即同步一次
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final afterStart = calls;
    expect(afterStart, greaterThanOrEqualTo(1));
    service.stopAutoSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, afterStart);
  });
}
