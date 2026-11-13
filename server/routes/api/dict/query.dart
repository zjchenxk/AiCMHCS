import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/dict_service.dart';

/// POST /api/dict/query
/// 请求体：{}（无需入参）。
/// 返回登录用户所属医院的全部数据字典扁平列表（前端按 parentId 组树），
/// 医院从令牌会话推导（不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护数据字典');
  }

  final service = context.read<DictService>();
  try {
    final dicts = await service.listByHospital(hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'dicts': dicts.map((d) => d.toJson()).toList()},
      },
    );
  } on DictException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
