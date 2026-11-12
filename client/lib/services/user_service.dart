import 'package:client/main.dart';
import 'package:client/services/base/base_service.dart';
import 'package:common/model.dart';

/// 用户服务：基于 BaseService 走后端 /api/user/*（自动加解密信封、
/// 携带 token）。用户归属登录用户的所属医院，医院参数由调用方传
/// loginUser.hospId；用户列表携带各自的角色 ID 列表（roleIds）。
class UserService {
  ///经服务定位器取加密客户端（登录后才可用；构造期不取，便于测试覆写）。
  BaseService get _base => getIt<BaseService>();

  ///获取指定医院下的用户列表（按创建顺序，携带各自角色 ID）。
  ///param hospId: 医院 ID（登录用户所属医院）
  Future<List<User>> getByHospital(String hospId) async {
    final data = await _base.post('/api/user/query', {'hospId': hospId});
    final list = data['users'] as List<dynamic>? ?? const [];
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  ///查询单个用户。
  ///param id: 用户 ID
  Future<User> getById(String id) async {
    final data = await _base.post('/api/user/query', {'id': id});
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  ///新增用户。
  ///param hospId: 所属医院 ID（登录用户所属医院）
  ///param deptId: 挂载科室 ID（须属于该医院）
  ///param userCode: 登录账号（全局唯一）
  ///param userName: 姓名
  ///param password: 口令（6-32 位）
  ///param userType: 用户类别
  ///param permissionLevel: 权限级别（0/1/2）
  ///param phone: 手机号
  ///param idCardNo: 身份证号
  ///param hisUserCode: HIS 用户代码
  ///param mchisUserCode: 妇幼保健系统用户代码
  ///param certId: CA 证书 ID
  ///param signatureImage: 手写签名（base64 图片）
  ///param status: 状态（1-启用 / 0-停用，缺省启用）
  ///param roleIds: 角色 ID 全量列表（可空）
  ///returns: 新增后的用户（含生成的 ID）
  Future<User> create({
    required String hospId,
    required String deptId,
    required String userCode,
    required String userName,
    required String password,
    String? userType,
    String? permissionLevel,
    String? phone,
    String? idCardNo,
    String? hisUserCode,
    String? mchisUserCode,
    String? certId,
    String? avatarImage,
    String? signatureImage,
    String? status,
    List<String> roleIds = const [],
  }) async {
    final data = await _base.post('/api/user/add', {
      'hospId': hospId,
      'deptId': deptId,
      'userCode': userCode,
      'userName': userName,
      'password': password,
      'userType': userType,
      'permissionLevel': permissionLevel,
      'phone': phone,
      'idCardNo': idCardNo,
      'hisUserCode': hisUserCode,
      'mchisUserCode': mchisUserCode,
      'certId': certId,
      'avatarImage': avatarImage,
      'signatureImage': signatureImage,
      'status': status,
      'roleIds': roleIds,
    });
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  ///修改用户。
  ///param id: 用户 ID
  ///param changes: 要修改的字段集合（键为 userName/userType/
  /// permissionLevel/phone/idCardNo/status/hisUserCode/mchisUserCode/
  /// certId/signatureImage，值 null 表示清空；登录账号与归属不可改）
  ///param password: 非空时重置口令（留空/null 不改）
  ///param roleIds: 非 null 时全量覆盖角色关联（null 不动角色，空列表清空）
  ///returns: 修改后的用户
  Future<User> update(String id, Map<String, Object?> changes, {String? password, List<String>? roleIds}) async {
    final data = await _base.post('/api/user/update', {
      'id': id,
      ...changes,
      'password': ?password,
      'roleIds': ?roleIds,
    });
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  ///修改密码
  ///param userId: 用户 ID
  ///param oldPassword: 旧密码
  ///param newPassword: 新密码
  Future<void> changePassword({required String userId, required String oldPassword, required String newPassword}) async {
    await _base.post('/api/user/changePassword', {
      'userId': userId,
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }
}
