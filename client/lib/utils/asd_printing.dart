import 'package:client/main.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:common/model.dart';

/// 初筛打印（初筛记录表/转诊单）数据装配：儿童整档 + 监护人 + 全部时段
/// 初筛记录 + 各月龄预警征象条目 + 医生签名图，供打印 HTML 生成器
/// （`asd_print_html.dart`，矢量文本渲染）使用。
class AsdPrinting {
  AsdPrinting._();

  /// 装载打印所需数据：儿童整档（保健号/证件号/电话等解密字段）+ 监护人
  /// + 全部时段初筛记录 + 各月龄预警征象条目 + 医生签名图。
  ///
  ///param childId: 当前儿童档案 ID
  ///param screeningService: 初筛服务（模板 CRUD/签名/条目/记录）
  ///param childService: 儿童服务（整档与监护人，敏感字段服务端解密下发）
  ///returns: 打印装配结果（见 [PrintBundle]）
  static Future<PrintBundle> loadBundle({
    required String childId,
    InitialScreeningService? screeningService,
    ChildService? childService,
  }) async {
    final screening = screeningService ?? getIt<InitialScreeningService>();
    final childSrv = childService ?? getIt<ChildService>();
    final archive = await childSrv.load(childId);
    final child = archive.$1;
    final guardians = archive.$3;
    final records = await screening.query(childId);
    // 打印整张表需要该表覆盖的全部月龄条目（婴儿期 3/6/8/12、幼儿期
    // 18/24/30/36、学龄前 48/60/72），逐月龄拉取后按月龄缓存
    final doctorIds = {for (final r in records) r.doctorId}.where((e) => e.isNotEmpty).toList();
    final results = await Future.wait([
      for (final month in const [3, 6, 8, 12, 18, 24, 30, 36, 48, 60, 72]) screening.wscmbdItems(month),
      if (doctorIds.isNotEmpty) screening.doctorSignatures(doctorIds) else Future<Map<String, String>>.value(const {}),
    ]);
    final scaleByMonth = <int, List<WscmbdItem>>{
      for (var i = 0; i < 11; i++) const [3, 6, 8, 12, 18, 24, 30, 36, 48, 60, 72][i]: results[i] as List<WscmbdItem>,
    };
    final signatures = doctorIds.isEmpty ? const <String, String>{} : results.last as Map<String, String>;
    return PrintBundle(child: child, guardians: guardians, records: records, scaleByMonth: scaleByMonth, doctorSignatures: signatures);
  }
}

/// 初筛打印数据包：儿童整档 + 监护人 + 全部初筛记录 + 各月龄预警征象
/// 条目 + 医生签名图映射。
class PrintBundle {
  const PrintBundle({
    required this.child,
    required this.guardians,
    required this.records,
    required this.scaleByMonth,
    required this.doctorSignatures,
  });

  /// 儿童整档（敏感字段已由服务端解密：保健号/证件号/联系电话）。
  final ChildInfo child;

  /// 监护人列表（含解密联系电话）。
  final List<ChildGuardianInfo> guardians;

  /// 当前儿童全部时段初筛记录（按 CHECK_MONTH 升序）。
  final List<InitialScreening> records;

  /// 各月龄预警征象条目（月龄 → 条目，ITEM_ORDER 升序）。
  final Map<int, List<WscmbdItem>> scaleByMonth;

  /// 医生签名图（doctorId → base64；无签名不含在映射内）。
  final Map<String, String> doctorSignatures;

  /// 取指定月龄的初筛记录（未录入为 null）。
  InitialScreening? recordOf(int month) {
    for (final r in records) {
      if (r.checkMonth == month) return r;
    }
    return null;
  }

  /// 打印用监护人：GUARDIAN_ORDER=1 或关系为「母亲/父亲」的第一位（需求
  /// 4.9/4.10；没有则返回 null，联系电话回退儿童本人电话）。
  ChildGuardianInfo? get preferredGuardian {
    for (final g in guardians) {
      final order = g.guardianOrder;
      final relation = g.guardianRelationship;
      if (order == '1' || relation == '母亲' || relation == '父亲') return g;
    }
    return null;
  }
}

/// 打印模板共用常量/工具。
class AsdPrintingUtil {
  AsdPrintingUtil._();

  /// 未见异常文案（与初筛协议值一致）。
  static const String noneAbnormal = '未见异常';

  /// 异常文案。
  static const String abnormal = '异常';
}
