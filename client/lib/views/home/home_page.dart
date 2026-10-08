import 'package:client/views/base/base_page.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends BasePage {
  const HomePage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    // final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('首页'),
      ),
      body: Center(
        child: Text('操作员：${widget.loginUser.userName}'),
      ),
    );
  }
}
