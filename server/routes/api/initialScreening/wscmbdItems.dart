import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';

/// POST /api/initialScreening/wscmbdItems
/// 请求体：{month}。返回指定月龄的儿童心理行为发育问题预警征象条目
/// （SCALE_WSCMBD 基础数据，按条目序号升序；全局数据不按医院隔离），
/// 供初筛记录表【预警征象筛查结果】多选选项。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final month = (body['month'] as num?)?.toInt();
  if (month == null || month <= 0) {
    return _error(400, 40001, '月龄不能为空且应为正整数');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  if (token != null) {
    await context.read<AuthService>().verify(token);
  }

  final service = context.read<InitialScreeningService>();
  try {
    final items = await service.wscmbdItems(month);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'items': items.map((e) => e.toJson()).toList()},
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
