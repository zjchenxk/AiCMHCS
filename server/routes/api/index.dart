import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'code': 0,
      'message': 'ok',
      'data': {
        'name': 'AiCMHCS API',
        'version': 'v1',
        'endpoints': [
          {'method': 'POST', 'path': '/api/auth/login', 'desc': '用户登录'},
          {'method': 'GET', 'path': '/api/auth/me', 'desc': '当前登录用户'},
          {'method': 'POST', 'path': '/api/adminDivisions/query', 'desc': '行政区划查询（code 查详情与子树规模；parentCode 缺省为省级查子级列表）'},
          {'method': 'POST', 'path': '/api/adminDivisions/add', 'desc': '新增行政区划'},
          {'method': 'POST', 'path': '/api/adminDivisions/update', 'desc': '修改行政区划（名称/编码，改编码级联更新下级父引用）'},
          {'method': 'POST', 'path': '/api/adminDivisions/delete', 'desc': '级联删除行政区划及其全部下级'},
          {'method': 'GET', 'path': '/health', 'desc': '健康检查（含数据库探活）'},
        ],
      },
    },
  );
}
