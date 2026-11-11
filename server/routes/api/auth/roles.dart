import 'dart:async';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/utils/log_helper.dart';

/// GET /api/auth/roles?usercode=<用户名>
/// 登录前按用户名查询其拥有的角色（SYS_USER × SYS_USER_ROLE × SYS_ROLE），
/// 供登录页输入用户名回车后绑定角色下拉框。该接口在加密中间件白名单内
/// （登录前无会话密钥）走明文；仅返回角色 ID 与名称。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: 405,
      body: const {
        'code': 40500,
        'message': '该接口仅支持 GET 请求',
        'data': null,
      },
    );
  }

  final userCode = context.request.uri.queryParameters['usercode']?.trim() ?? '';
  if (userCode.isEmpty) {
    return _error(400, 40001, '用户名不能为空');
  }

  unawaited(
    LogHelper.info('server:routes/api/auth/roles', content: '查询用户 $userCode 的角色列表'),
  );

  final auth = context.read<AuthService>();
  try {
    final roles = await auth.listUserRoles(userCode);
    return Response.json(
      body: {
        'code': 0,
        'message': '查询成功',
        'data': {'roles': roles},
      },
    );
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
