import 'package:client/services/time_service.dart';
import 'package:client/view_models/home/home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // TimeService 空构造即可用（now() 回退本地时钟），不经 startAutoSync 联网
  late TimeService timeService;

  setUp(() {
    timeService = TimeService();
  });

  Future<HomeViewModel> loadedViewModel() async {
    final vm = HomeViewModel(timeService: timeService);
    expect(await vm.loadDashboard(), isTrue);
    return vm;
  }

  test('loadDashboard 生成 24 个月演示序列，终点为当月且确定性一致', () async {
    final vm = await loadedViewModel();

    expect(vm.series, isNotNull);
    expect(vm.series!.months.length, HomeViewModel.demoMonths);
    // 序列升序、终点为当月
    for (var i = 1; i < vm.series!.months.length; i++) {
      expect(vm.series!.months[i].month.compareTo(vm.series!.months[i - 1].month), greaterThan(0));
    }
    expect(vm.latestMonth, monthKey(timeService.now()));

    // 确定性：另起实例重新生成，序列逐月一致（重建后数字不跳变）
    final vm2 = await loadedViewModel();
    for (var i = 0; i < vm.series!.months.length; i++) {
      expect(vm2.series!.months[i].month, vm.series!.months[i].month);
      expect(vm2.series!.months[i].screened, vm.series!.months[i].screened);
      expect(vm2.series!.months[i].screenAbnormal, vm.series!.months[i].screenAbnormal);
      expect(vm2.series!.months[i].confirmed, vm.series!.months[i].confirmed);
    }
  });

  test('默认区间为近 12 个月（起 = 当月前推 11 个月）', () async {
    final vm = await loadedViewModel();

    final now = timeService.now();
    final expectedFrom = monthKey(DateTime(now.year, now.month - 11));
    for (final board in DashboardBoard.values) {
      final range = vm.rangeOf(board);
      expect(range.from, expectedFrom, reason: 'board=$board 起始月');
      expect(range.to, monthKey(now), reason: 'board=$board 截止月');
    }
  });

  test('KPI 数字为板块一区间内对应曲线求和', () async {
    final vm = await loadedViewModel();

    var sumScreenAbnormal = 0;
    var sumReScreenAbnormal = 0;
    var sumConfirmed = 0;
    for (final p in vm.slice(DashboardBoard.kpi)) {
      sumScreenAbnormal += p.screenAbnormal;
      sumReScreenAbnormal += p.reScreenAbnormal;
      sumConfirmed += p.confirmed;
    }

    expect(vm.kpiScreenAbnormalCount, sumScreenAbnormal);
    expect(vm.kpiReScreenAbnormalCount, sumReScreenAbnormal);
    expect(vm.kpiConfirmedCount, sumConfirmed);
  });

  test('setRange 起晚于止拒绝、超窗截断到数据窗口边界', () async {
    final vm = await loadedViewModel();

    final earliest = vm.earliestMonth!;
    final latest = vm.latestMonth!;
    final earliestYear = int.parse(earliest.substring(0, 4));
    final earliestMonth = int.parse(earliest.substring(5));
    final before = monthKey(DateTime(earliestYear, earliestMonth - 3));

    // 起晚于止：拒绝且不生效
    expect(vm.setRange(DashboardBoard.screen, latest, earliest), isFalse);
    expect(vm.rangeOf(DashboardBoard.screen).from, isNot(latest));

    // 起月早于数据窗口：截断到窗口起点
    expect(vm.setRange(DashboardBoard.screen, before, latest), isTrue);
    final range = vm.rangeOf(DashboardBoard.screen);
    expect(range.from, earliest);
    expect(range.to, latest);
  });

  test('slice 返回闭区间切片（含起止月、升序）', () async {
    final vm = await loadedViewModel();

    final latest = vm.latestMonth!;
    // 近 3 个月：从当月前推 2 个月到当月
    final now = timeService.now();
    final from = monthKey(DateTime(now.year, now.month - 2));
    expect(vm.setRange(DashboardBoard.diagnosis, from, latest), isTrue);

    final slice = vm.slice(DashboardBoard.diagnosis);
    expect(slice.length, 3);
    expect(slice.first.month, from);
    expect(slice.last.month, latest);
  });
}
