import 'package:client/models/current_child.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

abstract class BasePage extends StatefulWidget {
  final LoginUser loginUser;
  final CurrentChild child;

  const BasePage({
    super.key,
    required this.loginUser,
    required this.child,
  });
}
