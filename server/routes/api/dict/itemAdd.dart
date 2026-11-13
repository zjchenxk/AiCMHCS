import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/dict_service.dart';

/// POST /api/dict/itemAdd
/// 请求体：{dictId, itemCode, itemValue, displayOrder?, isDefault?}
/// （编码必填且同字典内唯一；isDefault 为「1」时互斥置为该字典默认项；
/// 创建人从令牌会话推导，医院冗余列取自所属字典）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final dictId = body['dictId'];
  final itemCode = body['itemCode'];
  final itemValue = body['itemValue'];
  if (dictId is! String || itemCode is! String || itemValue is! String) {
    return _error(400, 40001, '字典ID、项目编码、项目值不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  if (user == null || user.id.trim().isEmpty) {
    return _error(400, 40001, '登录用户无效，不能维护数据字典');
  }

  final service = context.read<DictService>();
  try {
    final item = await service.createItem(
      dictId: dictId,
      itemCode: itemCode,
      itemValue: itemValue,
      displayOrder: body['displayOrder']?.toString(),
      isDefault: body['isDefault']?.toString() ?? '0',
      creatorId: user.id,
      creatorName: user.userName,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'item': item.toJson()},
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
