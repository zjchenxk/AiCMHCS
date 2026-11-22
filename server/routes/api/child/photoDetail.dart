import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/photoDetail
/// 请求体：{photoId}。返回单条拍照记录详情（含 PHOTO 大图与缩略图，
/// 供照片管理放大预览/下载按需取用）。照片不存在或非本院记录时返回
/// 40001（跨院 ID 按不存在处理），医院从令牌会话推导。
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
    return _error(400, 40001, '当前登录用户未归属医院，不能查询儿童照片');
  }

  final service = context.read<ChildService>();
  try {
    final photo = await service.photoDetail(photoId, hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'photo': photo.toJson()},
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
