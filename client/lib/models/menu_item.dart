import 'package:material_ui/material_ui.dart';

class MenuItem {
  final String id;
  final String title;
  final IconData icon;
  final List<MenuItem> children;
  final String? route; //功能页面对应的路由

  const MenuItem({
    required this.id,
    required this.title,
    required this.icon,
    this.children = const [],
    this.route,
  });
}
