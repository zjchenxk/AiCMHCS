import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/hospital_service.dart';

/// POST /api/hospital/query
/// 请求体：{id} 查单个医院详情、子树规模与子树内院区数（删除确认
/// 提示用）；缺省查全部医院扁平列表（医院规模有限，前端据此建医联体树）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id != null && id is! String) {
    return _error(400, 40002, '医院ID应为字符串');
  }

  final service = context.read<HospitalService>();
  try {
    // id 优先：查单个详情 + 子树规模 + 子树内院区数
    final i = (id as String?)?.trim() ?? '';
    if (i.isNotEmpty) {
      final hospital = await service.getById(i);
      final count = await service.subtreeCount(i);
      final campusCount = await service.subtreeCampusCount(i);
      return Response.json(
        body: {
          'code': 0,
          'message': 'ok',
          'data': {
            'hospital': hospital.toJson(),
            'subtreeCount': count,
            'campusCount': campusCount,
          },
        },
      );
    }

    final hospitals = await service.listAll();
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'hospitals': hospitals.map((h) => h.toJson()).toList(),
        },
      },
    );
  } on HospitalException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
