import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';

/// POST /api/initialScreening/delete
/// 请求体：{id}。删除一条初筛记录（医院从令牌会话推导，跨院 ID 删不到
/// 返回 0）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final id = (body['id'] as String?)?.trim() ?? '';
  if (id.isEmpty) {
    return _error(400, 40001, '初筛记录ID不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能删除初筛记录');
  }

  final service = context.read<InitialScreeningService>();
  try {
    final count = await service.delete(id, hospId);
    if (count == 0) {
      return _error(400, 40001, '初筛记录不存在：$id');
    }
    return Response.json(
      body: {
        'code': 0,
        'message': '删除成功',
        'data': {'deleted': count},
      },
    );
  } on AsdException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
