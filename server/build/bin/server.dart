// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../main.dart' as entrypoint;
import '../routes/index.dart' as index;
import '../routes/health.dart' as health;
import '../routes/api/index.dart' as api_index;
import '../routes/api/role/update.dart' as api_role_update;
import '../routes/api/role/query.dart' as api_role_query;
import '../routes/api/role/permissionSave.dart' as api_role_permission_save;
import '../routes/api/role/permissionQuery.dart' as api_role_permission_query;
import '../routes/api/role/delete.dart' as api_role_delete;
import '../routes/api/role/add.dart' as api_role_add;
import '../routes/api/menu/update.dart' as api_menu_update;
import '../routes/api/menu/query.dart' as api_menu_query;
import '../routes/api/menu/delete.dart' as api_menu_delete;
import '../routes/api/menu/add.dart' as api_menu_add;
import '../routes/api/logs/index.dart' as api_logs_index;
import '../routes/api/hospital/update.dart' as api_hospital_update;
import '../routes/api/hospital/query.dart' as api_hospital_query;
import '../routes/api/hospital/delete.dart' as api_hospital_delete;
import '../routes/api/hospital/add.dart' as api_hospital_add;
import '../routes/api/department/update.dart' as api_department_update;
import '../routes/api/department/query.dart' as api_department_query;
import '../routes/api/department/delete.dart' as api_department_delete;
import '../routes/api/department/add.dart' as api_department_add;
import '../routes/api/campus/update.dart' as api_campus_update;
import '../routes/api/campus/query.dart' as api_campus_query;
import '../routes/api/campus/delete.dart' as api_campus_delete;
import '../routes/api/campus/add.dart' as api_campus_add;
import '../routes/api/auth/me.dart' as api_auth_me;
import '../routes/api/auth/login.dart' as api_auth_login;
import '../routes/api/adminDivision/update.dart' as api_admin_division_update;
import '../routes/api/adminDivision/query.dart' as api_admin_division_query;
import '../routes/api/adminDivision/delete.dart' as api_admin_division_delete;
import '../routes/api/adminDivision/add.dart' as api_admin_division_add;

import '../routes/_middleware.dart' as middleware;
import '../routes/api/role/_middleware.dart' as api_role_middleware;
import '../routes/api/menu/_middleware.dart' as api_menu_middleware;
import '../routes/api/logs/_middleware.dart' as api_logs_middleware;
import '../routes/api/hospital/_middleware.dart' as api_hospital_middleware;
import '../routes/api/department/_middleware.dart' as api_department_middleware;
import '../routes/api/campus/_middleware.dart' as api_campus_middleware;
import '../routes/api/auth/_middleware.dart' as api_auth_middleware;
import '../routes/api/adminDivision/_middleware.dart' as api_admin_division_middleware;

void main() async {
  final address = InternetAddress.anyIPv6;
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  createServer(address, port);
}

Future<HttpServer> createServer(InternetAddress address, int port) async {
  final handler = Cascade().add(buildRootHandler()).handler;
  final server = await entrypoint.run(handler, address, port);
  print('\x1B[92m✓\x1B[0m Running on http://${server.address.host}:${server.port}');
  return server;
}

Handler buildRootHandler() {
  final pipeline = const Pipeline().addMiddleware(middleware.middleware);
  final router = Router()
    ..mount('/', (context) => buildHandler()(context))
    ..mount('/api', (context) => buildApiHandler()(context))
    ..mount('/api/role', (context) => buildApiRoleHandler()(context))
    ..mount('/api/menu', (context) => buildApiMenuHandler()(context))
    ..mount('/api/logs', (context) => buildApiLogsHandler()(context))
    ..mount('/api/hospital', (context) => buildApiHospitalHandler()(context))
    ..mount('/api/department', (context) => buildApiDepartmentHandler()(context))
    ..mount('/api/campus', (context) => buildApiCampusHandler()(context))
    ..mount('/api/auth', (context) => buildApiAuthHandler()(context))
    ..mount('/api/adminDivision', (context) => buildApiAdminDivisionHandler()(context));
  return pipeline.addHandler(router);
}

Handler buildHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/health', (context) => health.onRequest(context,))..all('/', (context) => index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => api_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiRoleHandler() {
  final pipeline = const Pipeline().addMiddleware(api_role_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_role_add.onRequest(context,))..all('/delete', (context) => api_role_delete.onRequest(context,))..all('/permissionQuery', (context) => api_role_permission_query.onRequest(context,))..all('/permissionSave', (context) => api_role_permission_save.onRequest(context,))..all('/query', (context) => api_role_query.onRequest(context,))..all('/update', (context) => api_role_update.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiMenuHandler() {
  final pipeline = const Pipeline().addMiddleware(api_menu_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_menu_add.onRequest(context,))..all('/delete', (context) => api_menu_delete.onRequest(context,))..all('/query', (context) => api_menu_query.onRequest(context,))..all('/update', (context) => api_menu_update.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiLogsHandler() {
  final pipeline = const Pipeline().addMiddleware(api_logs_middleware.middleware);
  final router = Router()
    ..all('/', (context) => api_logs_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiHospitalHandler() {
  final pipeline = const Pipeline().addMiddleware(api_hospital_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_hospital_add.onRequest(context,))..all('/delete', (context) => api_hospital_delete.onRequest(context,))..all('/query', (context) => api_hospital_query.onRequest(context,))..all('/update', (context) => api_hospital_update.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiDepartmentHandler() {
  final pipeline = const Pipeline().addMiddleware(api_department_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_department_add.onRequest(context,))..all('/delete', (context) => api_department_delete.onRequest(context,))..all('/query', (context) => api_department_query.onRequest(context,))..all('/update', (context) => api_department_update.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiCampusHandler() {
  final pipeline = const Pipeline().addMiddleware(api_campus_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_campus_add.onRequest(context,))..all('/delete', (context) => api_campus_delete.onRequest(context,))..all('/query', (context) => api_campus_query.onRequest(context,))..all('/update', (context) => api_campus_update.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiAuthHandler() {
  final pipeline = const Pipeline().addMiddleware(api_auth_middleware.middleware);
  final router = Router()
    ..all('/login', (context) => api_auth_login.onRequest(context,))..all('/me', (context) => api_auth_me.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiAdminDivisionHandler() {
  final pipeline = const Pipeline().addMiddleware(api_admin_division_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_admin_division_add.onRequest(context,))..all('/delete', (context) => api_admin_division_delete.onRequest(context,))..all('/query', (context) => api_admin_division_query.onRequest(context,))..all('/update', (context) => api_admin_division_update.onRequest(context,));
  return pipeline.addHandler(router);
}

