// 儿童年龄口径测试：实足年龄按日历「对日」计算年/月/天（月末封顶），
// 早产儿矫正年龄以预产期（矫正胎龄 40 周）为起点；非早产、未到预产期
// 或超出矫正窗口时不返回文本。
import 'package:client/utils/age_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('实足年龄', () {
    test('按日历计算年/月/天', () {
      expect(AgeUtil.formatAgeYmd(DateTime(2023, 9, 1), DateTime(2026, 11, 17)), '3岁2个月16天');
      expect(AgeUtil.formatAgeYmd(DateTime(2026, 10, 20), DateTime(2026, 11, 17)), '28天');
      expect(AgeUtil.formatAgeYmd(DateTime(2026, 10, 17), DateTime(2026, 11, 17)), '1个月');
    });

    test('月末出生按目标月份天数封顶', () {
      expect(AgeUtil.formatAgeYmd(DateTime(2020, 1, 31), DateTime(2021, 3, 1)), '1岁1个月1天');
      expect(AgeUtil.formatAgeYmd(DateTime(2020, 1, 31), DateTime(2020, 2, 29)), '29天');
    });

    test('出生日期缺失返回空串', () {
      expect(AgeUtil.formatAgeYmd(DateTime.fromMillisecondsSinceEpoch(0), DateTime(2026, 11, 17)), '');
    });
  });

  group('早产儿矫正年龄', () {
    test('33⁺⁴周早产按预产期折算', () {
      // 胎龄 235 天，预产期 = 2026-08-01 + 45 天 = 2026-09-15
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: DateTime(2026, 8, 1),
          now: DateTime(2026, 11, 17),
          gestationalWeek: '33',
          gestationalDay: '4',
        ),
        '2个月2天',
      );
    });

    test('足月儿不计算矫正年龄', () {
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: DateTime(2026, 8, 1),
          now: DateTime(2026, 11, 17),
          gestationalWeek: '38',
          gestationalDay: '2',
        ),
        isNull,
      );
    });

    test('未到预产期不展示负矫正年龄', () {
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: DateTime(2026, 11, 1),
          now: DateTime(2026, 11, 17),
          gestationalWeek: '33',
          gestationalDay: '0',
        ),
        isNull,
      );
    });

    test('矫正月龄满 24 个月后不再展示', () {
      // 32 周（224 天），预产期 = 2024-01-01 + 56 天 = 2024-02-26
      final birth = DateTime(2024, 1, 1);
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: birth,
          now: DateTime(2026, 2, 25),
          gestationalWeek: '32',
          gestationalDay: '0',
        ),
        isNotNull,
      );
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: birth,
          now: DateTime(2026, 2, 26),
          gestationalWeek: '32',
          gestationalDay: '0',
        ),
        isNull,
      );
    });

    test('极早产儿矫正窗口延长至 36 个月', () {
      // 27 周（189 天），预产期 = 2023-01-01 + 91 天 = 2023-04-02
      final birth = DateTime(2023, 1, 1);
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: birth,
          now: DateTime(2026, 4, 1), // 矫正 2岁11个月30天
          gestationalWeek: '27',
          gestationalDay: '0',
        ),
        isNotNull,
      );
      expect(
        AgeUtil.formatCorrectedAge(
          birthDate: birth,
          now: DateTime(2026, 4, 2), // 矫正满 3 岁
          gestationalWeek: '27',
          gestationalDay: '0',
        ),
        isNull,
      );
    });
  });
}
