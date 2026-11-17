/// 儿童年龄工具（临床口径）。
///
/// - 实足年龄：以公历出生日期为起点按日历「对日」计算年/月/天，不做
///   30 天/月的近似换算；日不足时向前借当月实际天数，月末出生（如
///   1 月 31 日）按目标月份天数封顶，不出现负天数。
/// - 矫正年龄（早产儿）：以预产期（矫正胎龄 40 周）为起点重新计算，
///   即矫正年龄 = 实足年龄 −（40 周 − 出生胎龄）。用于体格生长与神经
///   发育评估；预防接种、行政报表等仍按实足年龄。
class AgeUtil {
  AgeUtil._();

  /// 足月胎龄（40 周）天数。
  static const int fullTermDays = 280;

  /// 早产判定阈值（37 周）天数。
  static const int pretermThresholdDays = 259;

  /// 极早产（<28 周）判定天数。
  static const int extremelyPretermDays = 196;

  /// 一般早产儿矫正随访窗口（矫正月龄 24 个月）。
  static const int correctedAgeMaxMonths = 24;

  /// 极早产儿矫正随访窗口（矫正月龄 36 个月）。
  static const int extremelyPretermCorrectedAgeMaxMonths = 36;

  /// 格式化实足年龄（岁/月/天，如「3岁2个月15天」「28天」）。
  /// 出生日期缺失（epoch 0）或晚于当前时间时返回空串。
  ///param birth: 出生日期
  ///param now: 业务当前时间（全局时间服务口径）
  ///returns: 岁/月/天年龄文本
  static String formatAgeYmd(DateTime birth, DateTime now) {
    if (birth.millisecondsSinceEpoch <= 0 || now.isBefore(birth)) return '';
    final parts = _ageParts(birth, now);
    if (parts.years == 0 && parts.months == 0 && parts.days == 0) return '0天';
    return [
      if (parts.years > 0) '${parts.years}岁',
      if (parts.months > 0) '${parts.months}个月',
      if (parts.days > 0) '${parts.days}天',
    ].join();
  }

  /// 格式化早产儿矫正年龄（岁/月/天）。
  ///
  /// 仅满足以下条件时返回文本，否则返回 null（界面不展示矫正年龄）：
  /// - 出生胎龄 < 37 周（早产）；
  /// - 胎龄数据合理（≥ 20 周）；
  /// - 已到预产期（矫正年龄 ≥ 0，未到预产期时负数年龄无临床意义）；
  /// - 未超出矫正窗口：一般早产至矫正月龄 24 个月，极早产（<28 周）
  ///   至 36 个月。
  ///param birthDate: 出生日期
  ///param now: 业务当前时间（全局时间服务口径）
  ///param gestationalWeek: 出生孕周（字符串，可空）
  ///param gestationalDay: 出生孕天（字符串，可空，缺省按 0 天）
  ///returns: 矫正年龄文本；非早产/未到预产期/已过窗口时为 null
  static String? formatCorrectedAge({
    required DateTime birthDate,
    required DateTime now,
    String? gestationalWeek,
    String? gestationalDay,
  }) {
    if (birthDate.millisecondsSinceEpoch <= 0) return null;
    final week = int.tryParse(gestationalWeek?.trim() ?? '');
    if (week == null || week < 20 || week >= 37) {
      // 胎龄缺失、异常或已足月：不是需要矫正的早产儿
      return null;
    }
    final day = (int.tryParse(gestationalDay?.trim() ?? '') ?? 0).clamp(0, 6).toInt();
    final gestationalDays = week * 7 + day;
    if (gestationalDays >= pretermThresholdDays) return null;

    // 预产期 = 出生日期 + 剩余宫内天数（40 周 − 出生胎龄）
    final expectedDeliveryDate = birthDate.add(Duration(days: fullTermDays - gestationalDays));
    if (now.isBefore(expectedDeliveryDate)) return null;

    // 矫正随访窗口：极早产儿可矫正至 3 岁，其余至 2 岁
    final maxMonths = gestationalDays < extremelyPretermDays ? extremelyPretermCorrectedAgeMaxMonths : correctedAgeMaxMonths;
    final corrected = _ageParts(expectedDeliveryDate, now);
    if (corrected.years * 12 + corrected.months >= maxMonths) return null;

    return formatAgeYmd(expectedDeliveryDate, now);
  }

  /// 年龄拆分为完整的年/月/天（月末出生按目标月份天数封顶）。
  static ({int years, int months, int days}) _ageParts(DateTime birth, DateTime now) {
    var years = now.year - birth.year;
    var months = now.month - birth.month;
    if (now.day < birth.day) months--;
    if (months < 0) {
      years--;
      months += 12;
    }
    if (years < 0) return (years: 0, months: 0, days: 0);

    // 已满的年/月对应的锚点日期（月末封顶），剩余天数取与今天的差
    final anchorYear = birth.year + years;
    final anchorMonth = birth.month + months;
    final monthDays = DateTime(anchorYear, anchorMonth + 1, 0).day;
    final anchorDay = birth.day <= monthDays ? birth.day : monthDays;
    final anchor = DateTime(anchorYear, anchorMonth, anchorDay);
    var days = now.difference(anchor).inDays;
    if (days < 0) days = 0;
    return (years: years, months: months, days: days);
  }
}
