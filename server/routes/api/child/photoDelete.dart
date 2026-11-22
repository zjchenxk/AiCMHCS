import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/photoDelete
/// 请求体：{photoId}。删除单条拍照记录（照片管理页按 ID 删除，区别于
/// photoRemoveToday 的当天整批移除）；照片 ID 非本院记录时删不到，
/// deleted 为 0。医院从令牌会话推导（不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final photoId = (body['photoId'] as String?)?.trim() ?? '';
  if (photoId.isEmpty) {
    return _error(400, 40001, '照片ID不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能删除儿童照片');
  }

  final service = context.read<ChildService>();
  try {
    final deleted = await service.deletePhoto(photoId, hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': '删除成功',
        'data': {'deleted': deleted},
      },
    );
  } on ChildException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
