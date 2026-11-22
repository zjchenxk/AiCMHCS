import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/photoSave
/// 请求体：{childId, photoBase64, avatarBase64, thumbBase64?}。为指定
/// 儿童追加一条拍照记录（照片管理页拍照/上传裁剪后独立保存入口）；
/// thumb 为照片等比缩略图（可空）。创建人与医院信息从令牌会话推导
/// （不信任客户端上报），科室/院区归属沿用档案归属。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final childId = (body['childId'] as String?)?.trim() ?? '';
  final photoBase64 = (body['photoBase64'] as String?)?.trim() ?? '';
  final avatarBase64 = (body['avatarBase64'] as String?)?.trim() ?? '';
  if (childId.isEmpty) {
    return _error(400, 40001, '儿童ID不能为空');
  }
  if (photoBase64.isEmpty || avatarBase64.isEmpty) {
    return _error(400, 40002, '照片与头像不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能保存儿童照片');
  }

  final service = context.read<ChildService>();
  try {
    final photo = await service.savePhoto(
      childId: childId,
      photoBase64: photoBase64,
      avatarBase64: avatarBase64,
      thumbBase64: (body['thumbBase64'] as String?)?.trim(),
      creatorId: user!.id,
      creatorName: user.userName,
      hospId: hospId,
      hospName: user.hospName ?? '',
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '保存成功',
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
