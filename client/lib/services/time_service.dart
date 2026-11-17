import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// 全局时间服务：客户端采集时间统一以服务端为准（避免各终端本地时钟
/// 不一致导致建档时间、实际年龄、相对时间等业务时间口径混乱）。
///
/// 工作方式为「偏移推算式时钟同步」而非逐次请求：向服务端 `/api/time`
/// 采样若干次（取往返延迟最小的一次，抵消网络抖动），计算本地时钟与
/// 服务端时钟的偏移量；此后 [now] 以「本地时钟 + 偏移」零开销推算，
/// 业务侧无须为取时间发起网络请求。登录成功后与 [autoSyncInterval]
/// 周期性重新校准（终端中途改系统时间、长时间挂起等场景兜底）。
///
/// 可用性与兜底：同步失败（后端不可达、超时）静默忽略并回退本地时钟
/// （[isSynced] 为 false），业务流程不因时间服务受阻；恢复可达后由下
/// 一次周期校准自动收敛。
class TimeService {
  TimeService({this.apiUrl = '', http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String apiUrl = '';

  /// 启动时从 assets/config.json 读取后端地址（与服务定位流程一致）。
  Future<void> loadConfig() async {
    final config = jsonDecode(await rootBundle.loadString('assets/config.json')) as Map<String, dynamic>;
    apiUrl = config['apiUrl'] as String;
  }

  /// 本地时钟相对服务端时钟的偏移量（服务端时刻 - 本地时刻，含 RTT/2
  /// 修正）。未同步过或最近一次同步失败时为零——即回退本地时钟。
  Duration _offset = Duration.zero;

  /// 最近一次同步是否成功取得服务端时间（诊断用；业务侧无须关心，
  /// [now] 恒可用）。
  bool get isSynced => _synced;
  bool _synced = false;

  /// 周期重校准间隔：终端改时间/挂起等偏移失真场景的兜底收敛周期。
  static const Duration autoSyncInterval = Duration(minutes: 30);

  /// 单次采样的请求超时（超过即放弃该次采样；总时长仍受采样次数约束）。
  static const Duration _sampleTimeout = Duration(seconds: 3);

  /// 每次同步的采样次数（取往返延迟最小的一次计算偏移）。
  static const int _sampleCount = 3;

  Timer? _autoSyncTimer;

  /// 启动周期校准（立即先同步一次）。应用启动（main）时调用；重复
  /// 调用安全（先取消既有定时器）。
  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(autoSyncInterval, (_) => sync());
    sync();
  }

  /// 停止周期校准（测试或注销场景用；已取得的偏移保留，[now] 仍可用）。
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// 向服务端采样并更新时钟偏移。全部采样失败时静默返回（保持既有
  /// 偏移/回退状态），不抛异常——调用方无须 try-catch。
  Future<void> sync() async {
    if (apiUrl.isEmpty) {
      return;
    }
    try {
      final uri = Uri.parse('$apiUrl/api/time');
      Duration? bestRtt;
      int? bestServerEpochMs;
      for (var i = 0; i < _sampleCount; i++) {
        final t0 = DateTime.now();
        final response = await _client.get(uri).timeout(_sampleTimeout);
        final rtt = DateTime.now().difference(t0);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] != 0) {
          continue;
        }
        final data = json['data'] as Map<String, dynamic>?;
        final epochMs = data?['epochMs'];
        if (epochMs is! int) {
          continue;
        }
        // NTP 简化口径：往返延迟最小的样本受网络抖动影响最小，以其
        // 「服务端时刻 + RTT/2」估计请求到达服务端的时刻。
        if (bestRtt == null || rtt < bestRtt) {
          bestRtt = rtt;
          bestServerEpochMs = epochMs;
        }
      }
      if (bestServerEpochMs == null || bestRtt == null) {
        return;
      }
      final serverAtArrival = DateTime.fromMillisecondsSinceEpoch(bestServerEpochMs + bestRtt.inMilliseconds ~/ 2);
      _offset = serverAtArrival.difference(DateTime.now());
      _synced = true;
    } catch (_) {
      // 同步失败静默：保持既有偏移（或未同步时的零偏移回退），
      // 等待下一次周期校准。
    }
  }

  /// 当前时间（服务端口径）：本地时钟加同步偏移推算，零网络开销；
  /// 从未同步成功（或最近一次失败后偏移失真无法识别）时等价于本地
  /// 时钟——保证任何情况下可用，仅精度差异。
  DateTime now() => DateTime.now().add(_offset);

  /// 当前时间的格式化文本（`yyyy-MM-dd HH:mm:ss`，与服务端
  /// formatTimestamp 同口径，本地时区）。
  String nowText() {
    final t = now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
