import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/guidance_template_service.dart';

/// POST /api/guidanceTemplate/itemQuery
/// 请求体：{templateId, id?}——无 id 返回指定模板下的全部项目（按创
/// 建时间正序，模板须属本院）；带 id 查项目详情（医院隔离，跨院 ID 按
/// 不存在处理）。医院从令牌会话推导（不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final templateId = (body['templateId'] as String?)?.trim() ?? '';
  if (templateId.isEmpty) {
    return _error(400, 40001, '模板ID不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护指导建议模板');
  }

  final service = context.read<GuidanceTemplateService>();
  try {
    final id = (body['id'] as String?)?.trim() ?? '';
    if (id.isNotEmpty) {
      final item = await service.getItemById(id, hospId);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'item': item.toJson()},
        },
      );
    }
    final items = await service.listItemsByTemplate(templateId, hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'items': items.map((i) => i.toJson()).toList()},
      },
    );
  } on GuidanceTemplateException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
