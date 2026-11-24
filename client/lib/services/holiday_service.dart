import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 法定节假日服务：基于 BaseService 走后端 /api/holiday/*（自动加解密
/// 信封、携带 token）。数据按医院隔离，医院与创建人由服务端从登录会话
/// 推导，客户端无需传入。
class HolidayService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 查询登录用户所属医院的全部法定节假日（按起始日期倒序）。
  Future<List<BaseHoliday>> queryAll() async {
    final data = await _base.post('/api/holiday/query', const {});
    final list = data['holidays'] as List<dynamic>? ?? const [];
    return list.map((e) => BaseHoliday.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增法定节假日（主键由数据库自增生成，整表重拉后可见）。
  ///param startDate: 起始日期（yyyy-MM-dd，必填）
  ///param endDate: 截止日期（yyyy-MM-dd，必填，闭区间）
  ///param holidayType: 节假日类型（1-8，标签见 BaseHoliday.holidayTypeLabels）
  Future<void> create({
    required String startDate,
    required String endDate,
    required int holidayType,
  }) async {
    await _base.post('/api/holiday/add', {
      'startDate': startDate,
      'endDate': endDate,
      'holidayType': holidayType,
    });
  }

  /// 修改法定节假日。
  ///param id: 节假日 ID
  ///param changes: 要修改的字段集合（键为 startDate / endDate /
  /// holidayType，仅传本次要修改的字段）
  Future<void> update(String id, Map<String, Object?> changes) async {
    await _base.post('/api/holiday/update', {'id': id, ...changes});
  }

  /// 删除法定节假日。
  ///param id: 节假日 ID
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/holiday/delete', {'id': id});
    return data['deleted'] as int;
  }
}
