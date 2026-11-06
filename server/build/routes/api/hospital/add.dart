import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/hospital_service.dart';

/// POST /api/hospital/add
/// 请求体：{code, name, province, city, address, parentId?, nameEn?,
/// county?, town?, tel?, logoBase64?, sealBase64?, watermarkBase64?}
/// （parentId 缺省为顶级医院；code 必填且唯一）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final code = body['code'];
  final name = body['name'];
  final province = body['province'];
  final city = body['city'];
  final address = body['address'];
  if (code is! String || name is! String || province is! String || city is! String || address is! String) {
    return _error(400, 40001, '组织机构代码、医院名称、省份、城市、详细地址不能为空');
  }
  final parentId = body['parentId'];
  if (parentId != null && parentId is! String) {
    return _error(400, 40002, '上级医院ID应为字符串');
  }

  final service = context.read<HospitalService>();
  try {
    final hospital = await service.create(
      parentId: parentId as String?,
      code: code,
      name: name,
      nameEn: body['nameEn'] as String?,
      province: province,
      city: city,
      county: body['county'] as String?,
      town: body['town'] as String?,
      address: address,
      tel: body['tel'] as String?,
      logoBase64: body['logoBase64'] as String?,
      sealBase64: body['sealBase64'] as String?,
      watermarkBase64: body['watermarkBase64'] as String?,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'hospital': hospital.toJson()},
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
