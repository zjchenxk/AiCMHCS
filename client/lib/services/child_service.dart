import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 儿童整档：基本信息 + 扩展信息（可空）+ 监护人列表。
typedef ChildArchive = (ChildInfo, ChildExtInfo?, List<ChildGuardianInfo>);

/// 高级组合查询结果页：当前页儿童列表 + 总条数（服务端分页）。
typedef ChildAdvancedQueryPage = (List<ChildInfo> children, int total);

/// 儿童建档服务：基于 BaseService 走后端 /api/child/*（自动加解密信封、
/// 携带 token）。归属医院与创建人由服务端从登录会话推导，客户端无需
/// 传入；敏感字段在 JSON 协议中为服务端解密后的明文，传输由信封保护。
class ChildService {
  /// 经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  /// 解析整档响应（child + ext + guardians）。
  ChildArchive _parseArchive(Map<String, dynamic> data) {
    final child = ChildInfo.fromJson(data['child'] as Map<String, dynamic>);
    final extJson = data['ext'];
    final ext = extJson is Map<String, dynamic> ? ChildExtInfo.fromJson(extJson) : null;
    final guardians = ((data['guardians'] as List<dynamic>? ?? const [])).whereType<Map<String, dynamic>>().map(ChildGuardianInfo.fromJson).toList();
    return (child, ext, guardians);
  }

  /// 多条件精确检索本院儿童档案：姓名/证件号码/联系电话走盲索引精确
  /// 匹配，就诊卡号/保健号明文精确匹配（至少一个条件，返回前 20 条）。
  Future<List<ChildInfo>> search({String? name, String? visitCardNo, String? healthNo, String? certificateNo, String? phone}) async {
    final data = await _base.post('/api/child/query', {
      'name': name,
      'visitCardNo': visitCardNo,
      'healthNo': healthNo,
      'certificateNo': certificateNo,
      'phone': phone,
    });
    final list = data['children'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChildInfo.fromJson).toList();
  }

  /// 重复建档检查：按「姓名+性别+出生日期」三键 AND 精确匹配本院已有
  /// 档案（excludeId 用于修改态排除自身），返回解密后的相似儿童列表
  /// （含联系电话/居住地址，供确认对话框展示）。
  Future<List<ChildInfo>> duplicateCheck({required String name, required String sex, required String birthDate, String? excludeId}) async {
    final data = await _base.post('/api/child/duplicateCheck', {
      'name': name,
      'sex': sex,
      'birthDate': birthDate,
      'excludeId': excludeId,
    });
    final list = data['children'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChildInfo.fromJson).toList();
  }

  /// 高级组合查询本院儿童档案（条件之间为「与」关系，服务端分页）：
  /// 日期区间 yyyy-MM-dd、性别码值、文本条件精确匹配（姓名/证件号码/
  /// 联系电话/监护人姓名走盲索引，不支持模糊）、孕周按周数与体重按克
  /// 数值区间。page/pageSize 由服务端夹取（默认 1 / 20）。
  ///returns: (当前页儿童列表, 总条数)
  Future<ChildAdvancedQueryPage> advancedQuery({
    String? checkTimeFrom,
    String? checkTimeTo,
    String? birthDateFrom,
    String? birthDateTo,
    String? name,
    String? sex,
    String? visitCardNo,
    String? certificateNo,
    String? phone,
    String? guardianName,
    int? gestationalWeekFrom,
    int? gestationalWeekTo,
    int? birthWeightFrom,
    int? birthWeightTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _base.post('/api/child/advancedQuery', {
      'checkTimeFrom': checkTimeFrom,
      'checkTimeTo': checkTimeTo,
      'birthDateFrom': birthDateFrom,
      'birthDateTo': birthDateTo,
      'name': name,
      'sex': sex,
      'visitCardNo': visitCardNo,
      'certificateNo': certificateNo,
      'phone': phone,
      'guardianName': guardianName,
      'gestationalWeekFrom': gestationalWeekFrom,
      'gestationalWeekTo': gestationalWeekTo,
      'birthWeightFrom': birthWeightFrom,
      'birthWeightTo': birthWeightTo,
      'page': page,
      'pageSize': pageSize,
    });
    final list = data['children'] as List<dynamic>? ?? const [];
    final children = list.whereType<Map<String, dynamic>>().map(ChildInfo.fromJson).toList();
    final total = (data['total'] as num?)?.toInt() ?? children.length;
    return (children, total);
  }

  /// 装载儿童整档（基本信息 + 扩展信息 + 监护人列表）。
  Future<ChildArchive> load(String id) async {
    final data = await _base.post('/api/child/query', {'id': id});
    return _parseArchive(data);
  }

  /// 新增儿童档案（整档保存：child 必填，ext/guardians/photo/
  /// highRiskFactorIds 可选），返回入库后的整档（child 含生成的 ID）；
  /// photo 两字段同时非空时随档案一并插入一条拍照记录；
  /// highRiskFactorIds 为 null 表示不改动高危因素，显式传列表（含空
  /// 列表——表示清空）则整表替换。
  Future<ChildArchive> create({required ChildInfo child, ChildExtInfo? ext, List<ChildGuardianInfo> guardians = const [], String? photoBase64, String? avatarBase64, List<String>? highRiskFactorIds}) async {
    final data = await _base.post('/api/child/add', {
      'child': child.toJson(),
      'ext': ext?.toJson(),
      'guardians': guardians.map((g) => g.toJson()).toList(),
      'photo': buildPhotoPayload(photoBase64, avatarBase64),
      'highRiskFactorIds': highRiskFactorIds,
    });
    return _parseArchive(data);
  }

  /// 修改儿童档案（整档保存：基本信息全量更新、病人ID不可改；ext 传
  /// null 即清空扩展信息；监护人全量覆盖；photo/highRiskFactorIds 同
  /// 新增）。
  Future<ChildArchive> update({required String id, required ChildInfo child, ChildExtInfo? ext, List<ChildGuardianInfo> guardians = const [], String? photoBase64, String? avatarBase64, List<String>? highRiskFactorIds}) async {
    final data = await _base.post('/api/child/update', {
      'id': id,
      'child': child.toJson(),
      'ext': ext?.toJson(),
      'guardians': guardians.map((g) => g.toJson()).toList(),
      'photo': buildPhotoPayload(photoBase64, avatarBase64),
      'highRiskFactorIds': highRiskFactorIds,
    });
    return _parseArchive(data);
  }

  /// 组装照片负载（两字段齐备才携带，避免服务端只收到半截数据）。
  Map<String, dynamic>? buildPhotoPayload(String? photoBase64, String? avatarBase64) {
    if (photoBase64 == null || photoBase64.isEmpty || avatarBase64 == null || avatarBase64.isEmpty) {
      return null;
    }
    return {'photoBase64': photoBase64, 'avatarBase64': avatarBase64};
  }

  /// 删除儿童档案（连带删除扩展信息、监护人与全部拍照记录）。
  ///returns: 删除的行数
  Future<int> delete(String id) async {
    final data = await _base.post('/api/child/delete', {'id': id});
    return data['deleted'] as int;
  }

  /// 查询儿童最近一次拍照记录（仅回显头像，不含照片大图），无记录返回
  /// null。
  Future<ChildPhoto?> latestPhoto(String childId) async {
    final data = await _base.post('/api/child/photoQuery', {'childId': childId});
    final photo = data['photo'];
    return photo is Map<String, dynamic> ? ChildPhoto.fromJson(photo) : null;
  }

  /// 查询儿童已保存的高危因素记录（随档案保存整表替换，列表按创建
  /// 时间/ID 倒序），无记录返回空列表。
  Future<List<ChildHighRiskFactor>> highRiskFactors(String childId) async {
    final data = await _base.post('/api/child/highRiskFactorQuery', {'childId': childId});
    final list = data['factors'] as List<dynamic>? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(ChildHighRiskFactor.fromJson).toList();
  }

  /// 移除儿童当天全部拍照记录，返回 (移除条数, 移除后的最近记录——null
  /// 表示已无任何记录，界面恢复空白占位)。
  Future<(int, ChildPhoto?)> removeTodayPhotos(String childId) async {
    final data = await _base.post('/api/child/photoRemoveToday', {'childId': childId});
    final photo = data['photo'];
    return (
      data['removed'] as int? ?? 0,
      photo is Map<String, dynamic> ? ChildPhoto.fromJson(photo) : null,
    );
  }
}
