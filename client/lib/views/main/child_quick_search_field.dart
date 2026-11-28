import 'package:client/view_models/main/main_view_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 主界面顶部儿童快速搜索框：输入关键词回车触发精确检索（onSearch），
/// 右侧「高级搜索」按钮打开多条件对话框（onAdvancedSearch）。
///
/// 交互细节：搜索框再次获得输入焦点且已有内容时默认**全选文本**（便于
/// 直接输入覆盖或退格清除）；MainViewModel 的当前儿童上下文发生变更
/// （顶部选定、建档/高级搜索回写、切角色清空等）时自动**清空输入内容**，
/// 避免残留与当前儿童无关的关键词。
class ChildQuickSearchField extends StatefulWidget {
  /// 构造函数。
  const ChildQuickSearchField({super.key, required this.onSearch, required this.onAdvancedSearch});

  /// 提交精确检索（keyword 已去首尾空格，空串由调用方提示）。
  final ValueChanged<String> onSearch;

  /// 打开高级搜索对话框。
  final VoidCallback onAdvancedSearch;

  @override
  State<ChildQuickSearchField> createState() => _ChildQuickSearchFieldState();
}

class _ChildQuickSearchFieldState extends State<ChildQuickSearchField> {
  static const String _searchTip = '输入就诊号/就诊卡号/姓名/证件号码/电话号码精确搜索儿童...';

  final TextEditingController _controller = TextEditingController();

  final FocusNode _focus = FocusNode();

  /// 上一次记录的当前儿童 ID（变更检测去重）。
  String _lastChildId = '';

  MainViewModel? _mainViewModel;

  @override
  void initState() {
    super.initState();
    _mainViewModel = context.read<MainViewModel>();
    _lastChildId = _mainViewModel!.child.id;
    _mainViewModel!.addListener(_onMainViewModelChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _mainViewModel?.removeListener(_onMainViewModelChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 再次获得焦点且已有内容 → 全选文本（方便直接清除或覆盖输入）。
  void _onFocusChanged() {
    if (_focus.hasFocus && _controller.text.isNotEmpty) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    }
  }

  /// 当前儿童上下文变更（ID 变化，含清空/切角色）→ 清空搜索框内容。
  void _onMainViewModelChanged() {
    final id = _mainViewModel?.child.id ?? '';
    if (id == _lastChildId) return;
    _lastChildId = id;
    if (_controller.text.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: _searchTip,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => widget.onSearch(_controller.text.trim()),
                decoration: InputDecoration(
                  hintText: _searchTip,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.person_search_outlined,
                    color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                    size: 18,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  filled: true,
                  fillColor: theme.colorScheme.surface.withValues(alpha: 0.5),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '高级搜索',
            child: OutlinedButton.icon(
              onPressed: widget.onAdvancedSearch,
              icon: Icon(Icons.tune, size: 16, color: theme.colorScheme.onPrimaryContainer),
              label: Text(
                '高级搜索',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
              style: OutlinedButton.styleFrom(
                // 高度随全局统一按钮主题（勿加 visualDensity，会改变高度）
                side: BorderSide(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
