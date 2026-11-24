import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 检查医生候选（同科室 USER_TYPE=DOCTOR 的启用用户）。
typedef DoctorOption = ({String id, String userCode, String userName});

/// 孤独症初筛服务：基于 BaseService 走后端 /api/initialScreening/*
/// （自动加解密信封、携带 token）。归属医院与创建人由服务端从登录
/// 会话推导，客户端无需传入。
class InitialScreeningService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 装载当前儿童全部初筛记录（按检查时段升序，TAB 红点与逐月龄浏览
  /// 共用一次请求）。
  Future<List<InitialScreening>> query(String childId) async {
    final data = await _base.post('/api/initialScreening/query', {'childId': childId});
    final list = data['records'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(InitialScreening.fromJson).toList();
  }

  /// 查询指定月龄的预警征象条目（SCALE_WSCMBD 基础数据，按条目序号
  /// 升序；无条目表示字典未录入）。
  Future<List<WscmbdItem>> wscmbdItems(int month) async {
    final data = await _base.post('/api/initialScreening/wscmbdItems', {'month': month});
    final list = data['items'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(WscmbdItem.fromJson).toList();
  }

  /// 查询检查医生候选（当前登录用户所属科室的同科室启用医生）。
  Future<List<DoctorOption>> doctors() async {
    final data = await _base.post('/api/initialScreening/doctors', const {});
    final list = data['doctors'] as List<dynamic>? ?? const [];
    return [
      for (final e in list.whereType<Map<String, dynamic>>()) (id: e['id'] as String? ?? '', userCode: e['userCode'] as String? ?? '', userName: e['userName'] as String? ?? ''),
    ];
  }

  /// 保存初筛记录（同一儿童同一检查时段至多一条，服务端查重后走新增
  /// 或修改），返回保存后的记录。
  Future<InitialScreening> save(InitialScreening record) async {
    final data = await _base.post('/api/initialScreening/save', {'record': record.toJson()});
    return InitialScreening.fromJson(data['record'] as Map<String, dynamic>);
  }

  /// 删除初筛记录（按 ID）。
  Future<void> delete(String id) async {
    await _base.post('/api/initialScreening/delete', {'id': id});
  }
}
