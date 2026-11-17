import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/duplicateCheck
/// 请求体：{name, sex, birthDate, excludeId?}。按「姓名+性别+出生日期」
/// 三键 AND 精确匹配本院已有档案（excludeId 用于修改态排除自身），
/// 返回解密后的相似儿童列表（含联系电话/居住地址，供确认对话框展示）。
/// 医院从令牌会话推导（不信任客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final name = body['name'];
  final sex = body['sex'];
  final birthDate = body['birthDate'];
  if (name is! String || sex is! String || birthDate is! String) {
    return _error(400, 40001, '姓名、性别、出生日期不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能执行重复建档检查');
  }

  final service = context.read<ChildService>();
  try {
    final children = await service.findDuplicates(
      hospId: hospId,
      name: name,
      sex: sex,
      birthDate: birthDate,
      excludeId: (body['excludeId'] as String?)?.trim(),
    );
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'children': children.map((c) => c.toJson()).toList()},
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
