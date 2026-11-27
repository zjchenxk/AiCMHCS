import 'dart:convert';

import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

// =====================================================================
// 指导建议项目表单对话框（公用：指导建议模板管理页与初筛记录表指导
// 建议对话框共用，2026-11-27 需求）
//
// 毛玻璃对话框：新增模式全空待录（公共模板默认）、编辑模式回填选中
// 项目；提交期间保持打开（按钮转进度），失败保留输入并内联显示错误
// 信息，成功后关闭。表单自身不落库——保存经 [GuidanceItemSave] 回调
// 交给调用方（管理页经 ViewModel、初筛对话框直连服务按传入模板 ID
// 落库）。类别可空（填则 50 字节）、内容 1000 字节限长由服务端兜底
// 校验（此处按字节即时校验给出前置提示）。
// 底部【是否个人模板】开关与【取消】/【确定】按钮同行（开关靠左、
// 按钮靠右）。
// =====================================================================

/// 保存回调：由调用方执行新增/修改，返回错误信息（null = 成功）。
///param guidanceType: 指导建议类别（可空，空串已归一为 null）
///param guidance: 指导建议内容（已去首尾空格）
///param personal: 是否个人模板
typedef GuidanceItemSave = Future<String?> Function({String? guidanceType, required String guidance, required bool personal});

class GuidanceItemFormDialog extends StatefulWidget {
  /// 构造函数：注入模板名（标题展示用）、保存回调、新增默认是否个人
  /// 模板与编辑目标（null 为新增；新增落到哪个模板由 onSave 闭包捕获
  /// 的 templateId 决定）。
  ///
  /// [defaultPersonal] 仅作用于新增态（编辑态回填目标项目实际值）：
  /// 前台业务（初筛页指导建议对话框）入口传 true 默认个人模板，后台
  /// 管理页入口缺省 false 默认公共模板（2026-11-27 需求）。
  const GuidanceItemFormDialog({super.key, required this.templateName, required this.onSave, this.defaultPersonal = false, this.item});

  /// 所属模板名称（新增标题「新增指导建议——<模板名>」）。
  final String templateName;

  /// 保存回调（见 [GuidanceItemSave]）。
  final GuidanceItemSave onSave;

  /// 新增态【是否个人模板】默认值（true=个人模板；编辑态不生效）。
  final bool defaultPersonal;

  /// 编辑的目标项目（null 表示新增）。
  final BaseGuidanceTemplateItem? item;

  /// 打开对话框，保存成功返回 true（取消/失败关闭前返回 false）。
  static Future<bool> show(BuildContext context, {required String templateName, required GuidanceItemSave onSave, bool defaultPersonal = false, BaseGuidanceTemplateItem? item}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => GuidanceItemFormDialog(templateName: templateName, onSave: onSave, defaultPersonal: defaultPersonal, item: item),
    );
    return result == true;
  }

  @override
  State<GuidanceItemFormDialog> createState() => _GuidanceItemFormDialogState();
}

class _GuidanceItemFormDialogState extends State<GuidanceItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _typeCtrl;
  late final TextEditingController _guidanceCtrl;

  // 显式焦点链：类别输入框回车跳到内容输入框；内容为多行文本框不参与
  // 回车链（换行），由确定按钮提交
  final _typeFocus = FocusNode();
  final _guidanceFocus = FocusNode();

  late bool _personal;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 编辑模式回填目标项目实际值；新增模式按调用方入口取默认
    //（前台初筛入口默认个人模板、后台管理页默认公共模板）
    final item = widget.item;
    _typeCtrl = TextEditingController(text: item?.guidanceType);
    _guidanceCtrl = TextEditingController(text: item?.guidance);
    _personal = item?.isPersonalTemplate ?? widget.defaultPersonal;
  }

  @override
  void dispose() {
    _typeCtrl.dispose();
    _guidanceCtrl.dispose();
    _typeFocus.dispose();
    _guidanceFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // 防重复提交
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final type = _typeCtrl.text.trim();
    final guidance = _guidanceCtrl.text.trim();
    final error = await widget.onSave(guidanceType: type.isEmpty ? null : type, guidance: guidance, personal: _personal);

    if (!mounted) return;
    if (error != null) {
      // 保留输入与对话框，内联展示错误（对话框遮罩会挡住页面 SnackBar）
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creating = widget.item == null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        creating ? Icons.playlist_add_outlined : Icons.edit_outlined,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          creating ? '新增指导建议——${widget.templateName}' : '编辑指导建议',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _typeCtrl,
                    focusNode: _typeFocus,
                    autofocus: true,
                    style: theme.textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _guidanceFocus.requestFocus(),
                    decoration: _decoration(theme, '指导建议类别'),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isNotEmpty && utf8.encode(text).length > 50) return '指导建议类别超出长度限制（50 字节）';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _guidanceCtrl,
                    focusNode: _guidanceFocus,
                    style: theme.textTheme.bodyMedium,
                    minLines: 5,
                    maxLines: 8,
                    decoration: _decoration(theme, '指导建议', required: true, alignLabelTop: true),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) return '请输入指导建议';
                      if (utf8.encode(text).length > 1000) return '指导建议超出长度限制（1000 字节）';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),

                  // 底部操作行：【是否个人模板】开关（公共=全院可用 /
                  // 个人=个人录入者可见）与标签紧挨、整体靠左，【取消】/
                  //【确定】靠右（2026-11-27 需求：开关与操作按钮同行）
                  Row(
                    children: [
                      // 标签 + 开关紧挨成组（点标签也可切换）
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _saving ? null : () => setState(() => _personal = !_personal),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: _personal,
                                onChanged: _saving ? null : (v) => setState(() => _personal = v),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _personal ? '个人模板（仅本人可见）' : '公共模板（全院可见）',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(creating ? Icons.playlist_add_outlined : Icons.save_outlined, size: 18),
                        label: Text(creating ? '添加' : '保 存'),
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
  }

  /// 统一的毛玻璃输入框装饰（同模板表单对话框；多行文本标签随内容
  /// 顶部对齐）。
  InputDecoration _decoration(ThemeData theme, String label, {bool required = false, bool alignLabelTop = false}) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      alignLabelWithHint: alignLabelTop,
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ),
            )
          : Text(label, style: theme.textTheme.bodyMedium),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: border(theme.colorScheme.primary),
    );
  }
}
