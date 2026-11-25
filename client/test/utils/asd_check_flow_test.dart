import 'package:client/utils/asd_check_flow.dart';
import 'package:flutter_test/flutter_test.dart';

/// 初筛界面级联规则单元测试（2026-11-25 需求 1~4）。
void main() {
  group('deriveResult：两项询问结果推导初筛结果', () {
    test('两项均为未见异常 → 未见异常', () {
      expect(
        AsdCheckFlow.deriveResult(warningSigns: {AsdCheckFlow.noneAbnormal}, languageSocial: {AsdCheckFlow.noneAbnormal}),
        AsdCheckFlow.noneAbnormal,
      );
    });

    test('预警征象存在非未见异常项 → 异常', () {
      expect(
        AsdCheckFlow.deriveResult(warningSigns: {'与人无目光交流'}, languageSocial: {AsdCheckFlow.noneAbnormal}),
        AsdCheckFlow.abnormal,
      );
      expect(
        AsdCheckFlow.deriveResult(warningSigns: {'与人无目光交流', '不会独坐'}, languageSocial: {AsdCheckFlow.noneAbnormal}),
        AsdCheckFlow.abnormal,
      );
    });

    test('询问结果存在非未见异常项 → 异常', () {
      expect(
        AsdCheckFlow.deriveResult(warningSigns: {AsdCheckFlow.noneAbnormal}, languageSocial: {'语言功能障碍或倒退'}),
        AsdCheckFlow.abnormal,
      );
      expect(
        AsdCheckFlow.deriveResult(warningSigns: {AsdCheckFlow.noneAbnormal}, languageSocial: {'语言功能障碍或倒退', '社会交往能力障碍或倒退'}),
        AsdCheckFlow.abnormal,
      );
    });

    test('两项均存在异常项 → 异常', () {
      expect(
        AsdCheckFlow.deriveResult(warningSigns: {'不会独坐'}, languageSocial: {'社会交往能力障碍或倒退'}),
        AsdCheckFlow.abnormal,
      );
    });

    test('空集合（非法中间态）按异常处理', () {
      expect(AsdCheckFlow.deriveResult(warningSigns: {}, languageSocial: {AsdCheckFlow.noneAbnormal}), AsdCheckFlow.abnormal);
    });
  });

  test('guidanceFor：未见异常给默认文本，异常清空', () {
    expect(AsdCheckFlow.guidanceFor(AsdCheckFlow.noneAbnormal), '请定期带儿童接受心理行为发育评估');
    expect(AsdCheckFlow.guidanceFor(AsdCheckFlow.abnormal), '');
  });

  test('referralFlagFor：未见异常＝无（0），异常＝有（1）', () {
    expect(AsdCheckFlow.referralFlagFor(AsdCheckFlow.noneAbnormal), '0');
    expect(AsdCheckFlow.referralFlagFor(AsdCheckFlow.abnormal), '1');
  });
}
