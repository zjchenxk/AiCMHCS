import 'package:client/main.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 指导建议自定义模板对话框（需求 9.2）。
///
/// 顶部搜索框过滤列表；列表每条显示指导建议内容（最多两行），内容下方
/// 显示类别与创建人，公共模板（IS_PERSONAL='0'）用主题色醒目显示；列表
/// 可滚动、可多选。交互：
/// - **双击**某条 → 关闭对话框并回传该条内容（单条选入）；
/// - **确定** → 把全部选中项内容合并（换行分隔）回传；
/// - **新增** → 新建对话框（内容/类别/是否个人模板，默认个人），保存到
///   库后刷新列表；
/// - **修改/删除** → 对选中项（多条取第一条）操作，仅本人录入可改删
///   （他人录入由服务端 40001 拦截，界面提示）；
/// - **取消** → 关闭且不回传。
class GuidanceTemplateDialog extends StatefulWidget {
  const GuidanceTemplateDialog({super.key, this.service});

  /// 服务覆写（测试注入用；缺省经服务定位器获取）。
  final InitialScreeningService? service;

  /// 打开对话框，返回选中模板内容（单条或合并文本；取消为 null）。
  static Future<String?> show(BuildContext context, {InitialScreeningService? service}) {
    return showDialog<String>(
      context: context,
      builder: (_) => GuidanceTemplateDialog(service: service),
    );
  }

  @override
  State<GuidanceTemplateDialog> createState() => _GuidanceTemplateDialogState();
}

class _GuidanceTemplateDialogState extends State<GuidanceTemplateDialog> {
  final TextEditingController _searchCtrl = TextEditingController();

  InitialScreeningService get _service => widget.service ?? getIt<InitialScreeningService>();

  /// 当前登录用户 ID（判断是否本人模板）。
  String get _operatorId => loginUser?.id ?? '';

  List<GuidanceTemplate> _templates = [];

  bool _loading = true;

  String? _errorMsg;

  /// 选中模板 ID 集合（支持多选）。
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final templates = await _service.guidanceTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        // 移除已不存在的选中项
        _selectedIds.removeWhere((id) => !templates.any((t) => t.id == id));
        _loading = false;
      });
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateDialog._load', e, st);
      if (!mounted) return;
      setState(() {
        _errorMsg = _messageOf(e);
        _loading = false;
      });
    }
  }

  /// 搜索过滤后的列表（内容或类别包含关键词）。
  List<GuidanceTemplate> get _filtered {
    final kw = _searchCtrl.text.trim().toLowerCase();
    if (kw.isEmpty) return _templates;
    return _templates.where((t) => t.guidance.toLowerCase().contains(kw) || t.guidanceType.toLowerCase().contains(kw)).toList();
  }

  /// 提示（错误/成功统一 SnackBar）。
  void _toast(String message, {bool error = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: error ? theme.colorScheme.onError : null)),
          backgroundColor: error ? theme.colorScheme.error : null,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// 选中项（多条取第一条，用于修改/删除）。
  GuidanceTemplate? get _firstSelected {
    for (final t in _templates) {
      if (_selectedIds.contains(t.id)) return t;
    }
    return null;
  }

  /// 新增模板。
  Future<void> _add() async {
    final created = await _showTemplateForm();
    if (created) await _load();
  }

  /// 修改选中的模板（仅本人可改）。
  Future<void> _edit() async {
    final target = _firstSelected;
    if (target == null) {
      _toast('请先选择要修改的指导建议模板', error: true);
      return;
    }
    if (target.creatorId != _operatorId) {
      _toast('不能修改他人的指导建议', error: true);
      return;
    }
    final updated = await _showTemplateForm(template: target);
    if (updated) await _load();
  }

  /// 删除选中的模板（仅本人可删，带确认）。
  Future<void> _delete() async {
    final target = _firstSelected;
    if (target == null) {
      _toast('请先选择要删除的指导建议模板', error: true);
      return;
    }
    if (target.creatorId != _operatorId) {
      _toast('不能删除他人的指导建议', error: true);
      return;
    }
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassPanel(
            blur: 24,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('删除指导建议模板', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('将删除选中的指导建议模板，删除后不可恢复。确定删除吗？', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteGuidanceTemplate(target.id);
      _toast('删除成功');
      await _load();
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateDialog._delete', e, st);
      _toast(_messageOf(e), error: true);
    }
  }

  /// 打开模板新增/修改对话框，保存成功返回 true。
  Future<bool> _showTemplateForm({GuidanceTemplate? template}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _GuidanceTemplateFormDialog(service: _service, template: template),
    );
    return result == true;
  }

  /// 单条双击选入（直接关闭回传内容）。
  void _pickOne(GuidanceTemplate template) {
    Navigator.of(context).pop(template.guidance);
  }

  /// 确定：合并全部选中项（按列表顺序，换行分隔）。
  void _confirm() {
    final picked = [
      for (final t in _filtered)
        if (_selectedIds.contains(t.id)) t.guidance,
    ];
    // 过滤后可能漏掉被搜索隐藏的选中项，回退按全量列表顺序取
    final all = picked.isEmpty
        ? [
            for (final t in _templates)
              if (_selectedIds.contains(t.id)) t.guidance,
          ]
        : [
            for (final t in _templates)
              if (_selectedIds.contains(t.id)) t.guidance,
          ];
    if (all.isEmpty) {
      _toast('请至少选择一条指导建议', error: true);
      return;
    }
    Navigator.of(context).pop(all.join('\n'));
  }

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '选择指导建议模板',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '双击某条直接选入；勾选多条后确定则合并（换行分隔）',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  style: theme.textTheme.bodyMedium,
                  decoration: _decoration(theme, '搜索指导建议内容或类别').copyWith(
                    prefixIcon: Icon(Icons.search_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _searchCtrl.clear(),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMsg != null
                      ? Center(
                          child: Text(
                            '模板加载失败：$_errorMsg',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : list.isEmpty
                      ? Center(
                          child: Text(
                            _templates.isEmpty ? '暂无指导建议模板，可点击【新增】录入' : '没有匹配的指导建议',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final template = list[index];
                            final selected = _selectedIds.contains(template.id);
                            // 公共模板用主题色醒目显示
                            final isPublic = template.isPersonal == '0';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() {
                                    selected ? _selectedIds.remove(template.id) : _selectedIds.add(template.id);
                                  }),
                                  onDoubleTap: () => _pickOne(template),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                                      border: Border.all(
                                        color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Checkbox(
                                          value: selected,
                                          onChanged: (checked) => setState(() {
                                            (checked ?? false) ? _selectedIds.add(template.id) : _selectedIds.remove(template.id);
                                          }),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                template.guidance,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: isPublic ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                                  fontWeight: isPublic ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${template.guidanceType}　${template.creatorName}${isPublic ? '（公共模板）' : ''}',
                                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Tooltip(
                      message: '新增指导建议模板',
                      child: OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add_outlined, size: 16), label: const Text('新增')),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '修改选中的模板（仅本人录入）',
                      child: OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('修改')),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '删除选中的模板（仅本人录入）',
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        icon: Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                        label: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => _load(), icon: const Icon(Icons.refresh_outlined, size: 16), label: const Text('刷新')),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _confirm, child: Text('确定（已选 ${_selectedIds.length} 条）')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(ThemeData theme, String hint) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: border(theme.colorScheme.primary),
    );
  }
}

/// 指导建议模板新增/修改对话框。
class _GuidanceTemplateFormDialog extends StatefulWidget {
  const _GuidanceTemplateFormDialog({required this.service, this.template});

  final InitialScreeningService service;

  /// 修改目标（null 表示新增）。
  final GuidanceTemplate? template;

  @override
  State<_GuidanceTemplateFormDialog> createState() => _GuidanceTemplateFormDialogState();
}

class _GuidanceTemplateFormDialogState extends State<_GuidanceTemplateFormDialog> {
  late final TextEditingController _guidanceCtrl = TextEditingController(text: widget.template?.guidance ?? '');

  late final TextEditingController _typeCtrl = TextEditingController(text: widget.template?.guidanceType ?? '');

  /// 是否个人模板（新增默认「是」）。
  late String _isPersonal = widget.template?.isPersonal ?? '1';

  bool _busy = false;

  @override
  void dispose() {
    _guidanceCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final theme = Theme.of(context);
    final guidance = _guidanceCtrl.text.trim();
    final type = _typeCtrl.text.trim();
    if (guidance.isEmpty) {
      _toast('指导建议不能为空', theme);
      return;
    }
    if (type.isEmpty) {
      _toast('指导建议类别不能为空', theme);
      return;
    }
    setState(() => _busy = true);
    try {
      final template = widget.template;
      if (template == null) {
        await widget.service.addGuidanceTemplate(guidance: guidance, guidanceType: type, isPersonal: _isPersonal);
      } else {
        await widget.service.updateGuidanceTemplate(id: template.id, guidance: guidance, guidanceType: type, isPersonal: _isPersonal);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      LogHelper.error('client:GuidanceTemplateFormDialog._submit', e, st);
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), ''), theme);
    }
  }

  void _toast(String message, ThemeData theme) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError)),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.template != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? '修改指导建议模板' : '新增指导建议模板',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _typeCtrl,
                  style: theme.textTheme.bodyMedium,
                  decoration: _decoration(theme, '指导建议类别'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _guidanceCtrl,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 6,
                  minLines: 4,
                  decoration: _decoration(theme, '指导建议'),
                ),
                const SizedBox(height: 4),
                // 是否个人模板：开关（开=个人模板，关=公共模板；新增默认开）
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _isPersonal == '1',
                  onChanged: _busy ? null : (checked) => setState(() => _isPersonal = checked ? '1' : '0'),
                  title: Text('是否个人模板', style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    _isPersonal == '1' ? '个人模板：仅本人可见、可修改删除' : '公共模板：本院所有医生可见',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('取消')),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 16),
                      label: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(ThemeData theme, String label) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: border(theme.colorScheme.primary),
    );
  }
}
