import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/checkRecordQuery
/// 请求体：{childId}。返回该儿童已汇总的检查记录（CHILD_CHECK_RECORD，
/// 按检查日期/ID 倒序），无记录时 records 为空列表。医院从令牌会话推导
/// （不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final childId = (body['childId'] as String?)?.trim() ?? '';
  if (childId.isEmpty) {
    return _error(400, 40001, '儿童ID不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能查询儿童检查记录');
  }

  final service = context.read<ChildService>();
  try {
    final records = await service.listCheckRecords(childId, hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'records': records.map((r) => r.toJson()).toList()},
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
