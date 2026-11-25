import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:common/model.dart';

/// 初筛下次检查日期计算（需求 10.1~10.4）。
///
/// 规则：初筛未见异常时，下次检查日期 = 出生日期 + 下一年龄段月数
/// （如出生 2026-03-22、当前 8 月龄 → 下一年龄段 12 月龄 → 2027-03-22）；
/// 若落在周末或本院法定节假日，则顺延到最近的工作日（周一~周五且非
/// 节假日）。初筛异常时清空下次检查日期；**手动选择**的日期不受周末
/// 与节假日限制。已到 6 岁（72 月龄）末段时无下一年龄段，返回 null。
class NextCheckDateUtil {
  NextCheckDateUtil._();

  /// 下一年龄段映射（当前年龄段 → 下一时段；72 为末段返回 null）。
  static int? nextMonthOf(int month) {
    const order = [3, 6, 8, 12, 18, 24, 30, 36, 48, 60, 72];
    final index = order.indexOf(month);
    if (index < 0 || index == order.length - 1) return null;
    return order[index + 1];
  }

  /// 计算自动下次检查日期。
  ///
  ///param birthDate: 儿童出生日期
  ///param currentMonth: 当前初筛年龄段（CHECK_MONTH）
  ///param holidays: 本院法定节假日区间（顺延判断用，可为空）
  ///returns: 顺延到工作日后的日期；已到末段（72 月龄）时返回 null
  static DateTime? compute({
    required DateTime birthDate,
    required int currentMonth,
    required List<BaseHoliday> holidays,
  }) {
    final nextMonth = nextMonthOf(currentMonth);
    if (nextMonth == null) return null;
    final target = _addMonths(birthDate, nextMonth);
    return shiftToWorkday(target, holidays);
  }

  /// 日期加月（月末封顶，与 AgeUtil 口径一致：1 月 31 日 + 1 月 → 2 月末）。
  static DateTime _addMonths(DateTime date, int months) {
    final year = date.year + (date.month - 1 + months) ~/ 12;
    final month = (date.month - 1 + months) % 12 + 1;
    final monthDays = DateTime(year, month + 1, 0).day;
    final day = date.day <= monthDays ? date.day : monthDays;
    return DateTime(year, month, day);
  }

  /// 顺延到最近的工作日：跳过周六/周日与节假日区间（含端点）。
  ///
  ///param date: 目标日期
  ///param holidays: 法定节假日区间列表
  ///returns: 首个工作日
  static DateTime shiftToWorkday(DateTime date, List<BaseHoliday> holidays) {
    var cursor = DateTime(date.year, date.month, date.day);
    // 连续假日+周末最长不超过十余天，上限 60 次防御死循环
    for (var i = 0; i < 60; i++) {
      if (cursor.weekday != DateTime.saturday && cursor.weekday != DateTime.sunday && !_isHoliday(cursor, holidays)) {
        return cursor;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return cursor;
  }

  /// 日期是否落在任一节假日区间内（含端点；按 yyyy-MM-dd 字符串比较，
  /// 与库内 DATE 列口径一致）。
  static bool _isHoliday(DateTime date, List<BaseHoliday> holidays) {
    final key = formatDate(date);
    for (final holiday in holidays) {
      if (holiday.startDate.compareTo(key) <= 0 && holiday.endDate.compareTo(key) >= 0) {
        return true;
      }
    }
    return false;
  }

  /// 本地日期格式化为 yyyy-MM-dd（与 DATE 列绑定的字符串口径一致）。
  static String formatDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// 初筛未见异常时的默认指导建议文本。
  static const String normalGuidance = '请定期带儿童接受心理行为发育评估';

  /// 当前年龄段对应的 TAB 标签（找不到时回退「N月龄」）。
  static String tabLabelOf(int month) {
    for (final (m, label) in screeningTabs) {
      if (m == month) return label;
    }
    return '$month月龄';
  }
}
