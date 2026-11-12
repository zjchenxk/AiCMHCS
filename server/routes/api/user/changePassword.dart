import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/user_service.dart';

/// POST /api/user/changePassword
/// 请求体：{userId, oldPassword, newPassword}
/// 当前登录用户自助修改口令：服务端先验证原口令，再按等保三级复杂度
/// 兜底校验新口令，通过后更新 SYS_USER.PASSWORD 并刷新 UPDATE_TIME。
///
/// 注意：userId 理想来源是登录会话（token 关联用户）而非请求体，
/// 防止越权改他人口令。若项目已有登录中间件往 context 注入会话
/// 用户，应改为 context.read<会话类型>().userId 并忽略请求体值。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final userId = body['userId'];
  final oldPassword = body['oldPassword'];
  final newPassword = body['newPassword'];
  if (userId is! String || userId.trim().isEmpty) {
    return _error(400, 40001, '用户ID不能为空');
  }
  if (oldPassword is! String || oldPassword.isEmpty) {
    return _error(400, 40001, '原密码不能为空');
  }
  if (newPassword is! String || newPassword.isEmpty) {
    return _error(400, 40001, '新密码不能为空');
  }

  final service = context.read<UserService>();
  try {
    await service.changePassword(id: userId, oldPassword: oldPassword, newPassword: newPassword);
    return Response.json(
      body: {
        'code': 0,
        'message': '密码修改成功',
        'data': <String, Object?>{},
      },
    );
  } on UserException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
