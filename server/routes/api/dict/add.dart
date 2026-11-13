import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/dict_service.dart';

/// POST /api/dict/add
/// 请求体：{dictCode, dictName, displayOrder?, parentId?}
/// （编码/名称必填且同医院内唯一；parentId 空为顶级字典；医院与创建人
/// 从令牌会话推导，不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final dictCode = body['dictCode'];
  final dictName = body['dictName'];
  if (dictCode is! String || dictName is! String) {
    return _error(400, 40001, '字典编码、字典名称不能为空');
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
    final dict = await service.create(
      dictCode: dictCode,
      dictName: dictName,
      hospId: hospId,
      hospName: user!.hospName ?? '',
      creatorId: user.id,
      creatorName: user.userName,
      parentId: body['parentId'] as String?,
      displayOrder: body['displayOrder']?.toString(),
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'dict': dict.toJson()},
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
