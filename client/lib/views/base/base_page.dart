import 'package:client/models/child_info.dart';
import 'package:client/models/login_user.dart';
import 'package:material_ui/material_ui.dart';

abstract class BasePage extends StatefulWidget {
  final LoginUser loginUser;
  final ChildInfo child;

  const BasePage({
    super.key,
    required this.loginUser,
    required this.child,
  });
}
