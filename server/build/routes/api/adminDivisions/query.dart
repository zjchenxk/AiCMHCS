import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/admin_division_service.dart';

/// POST /api/adminDivisions/query
/// 请求体：{code} 查单个区划详情与子树规模；{parentCode} 查下一级列表
/// （缺省省级）。动作式路由，操作日志按路径即可辨识。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final code = body['code'];
  final parentCode = body['parentCode'];
  if (code != null && code is! String) {
    return _error(400, 40002, '行政区划代码应为字符串');
  }
  if (parentCode != null && parentCode is! String) {
    return _error(400, 40002, '上级行政区划代码应为字符串');
  }

  final service = context.read<AdminDivisionService>();
  try {
    // code 优先：查单个详情 + 子树规模（删除确认提示用）
    final c = (code as String?)?.trim() ?? '';
    if (c.isNotEmpty) {
      final division = await service.getByCode(c);
      final count = await service.subtreeCount(c);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {'division': division.toJson(), 'subtreeCount': count},
        },
      );
    }

    final divisions = await service.listChildren(parentCode: parentCode as String?);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'divisions': divisions.map((d) => d.toJson()).toList(),
        },
      },
    );
  } on AdminDivisionException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
