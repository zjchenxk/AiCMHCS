import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/hospital_service.dart';

/// POST /api/hospital/query
/// 请求体：{id} 查单个医院详情、子树规模与子树内院区数（删除确认
/// 提示用）；缺省查医院扁平列表（医院规模有限，前端据此建医联体树），
/// 并按登录用户所属医院做数据范围过滤：用户 hospId 为空返回全部，
/// 非空仅返回该医院及其全部嵌套下级（scopeRootId 随响应下发供前端
/// 识别限定范围，如隐藏「添加顶级医院」入口）。
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

  // 数据范围：从令牌会话推导（不信任客户端上报），verify 失败由
  // 加密中间件的会话校验前置拦截，此处正常返回
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final scopeHospId = token == null ? null : (await context.read<AuthService>().verify(token)).hospId;

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

    final scope = scopeHospId?.trim() ?? '';
    final hospitals = await service.listAll(scopeHospId: scope.isEmpty ? null : scope);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'hospitals': hospitals.map((h) => h.toJson()).toList(),
          // null 表示未限定范围（系统管理员全量视图）
          'scopeRootId': scope.isEmpty ? null : scope,
        },
      },
    );
  } on HospitalException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
