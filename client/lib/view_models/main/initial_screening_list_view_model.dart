import 'dart:async';

import 'package:client/main.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:flutter/foundation.dart';

/// 右侧侧边栏「初筛儿童」列表视图模型：按检查日期区间 + 分页查询本院
/// 全部初筛记录（服务端解密儿童姓名），供双击打开初筛记录表定位月龄
/// TAB。复筛/诊断/干预列表的取数暂缓开放（界面结构与本列表一致）。
class InitialScreeningListViewModel extends ChangeNotifier {
  /// 构造函数：可选注入服务（缺省经服务定位器取，便于测试覆写）。
  InitialScreeningListViewModel({InitialScreeningService? screeningService}) : _screeningService = screeningService ?? getIt<InitialScreeningService>();

  final InitialScreeningService _screeningService;

  /// 每页条数（侧边栏列表固定 10 条）。
  static const int pageSize = 10;

  // 查询条件（yyyy-MM-dd；空串表示不限）
  String _startDate = '';
  String _endDate = '';
  String get startDate => _startDate;
  String get endDate => _endDate;

  // 列表状态
  List<InitialScreeningListItem> _records = const [];
  List<InitialScreeningListItem> get records => _records;

  int _total = 0;
  int get total => _total;

  int _page = 1;
  int get page => _page;

  int get totalPages => _total == 0 ? 1 : ((_total + pageSize - 1) ~/ pageSize);

  bool _loading = false;
  bool get loading => _loading;

  bool _loadFailed = false;
  bool get loadFailed => _loadFailed;

  /// 是否已成功加载过一次（区分「未查询」与「查询结果为空」）。
  bool _loaded = false;
  bool get loaded => _loaded;

  /// 设置日期区间并回到第 1 页重新查询；两段均为空则查询全部。
  ///param start: 起始日期（yyyy-MM-dd；null/空串不限）
  ///param end: 截止日期（yyyy-MM-dd；null/空串不限）
  Future<void> search({String? start, String? end}) async {
    _startDate = (start ?? '').trim();
    _endDate = (end ?? '').trim();
    _page = 1;
    await _load();
  }

  /// 翻页（越界自动夹取到有效页码后重新查询）。
  Future<void> goToPage(int target) async {
    final clamped = target.clamp(1, totalPages);
    if (clamped == _page && _loaded) return;
    _page = clamped;
    await _load();
  }

  /// 以当前条件重新查询（失败重试入口）。
  Future<void> refresh() => _load();

  /// 首次进入列表时惰性加载（已加载/加载中则跳过）。
  Future<void> ensureLoaded() {
    if (_loaded || _loading) return Future.value();
    return refresh();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    // 首次查询不清空旧列表（保留上一页内容，避免翻页闪烁）
    notifyListeners();
    try {
      final (records, total, page, _) = await _screeningService.list(
        startDate: _startDate.isEmpty ? null : _startDate,
        endDate: _endDate.isEmpty ? null : _endDate,
        page: _page,
        pageSize: pageSize,
      );
      _records = records;
      _total = total;
      _page = page;
      _loadFailed = false;
      _loaded = true;
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningListViewModel.load', e, st);
      _loadFailed = true;
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
