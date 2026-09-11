import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../domain/models.dart';
import '../../state/store.dart';
import '../theme.dart';
import '../widgets/ledger_widgets.dart';

/// 新增 / 编辑账单。方向只在还没有流水时可改，这条禁令由 repo 兜底，
/// 界面这里同时把入口禁用掉，不让用户点了才知道不行。
Future<void> showBillSheet(
  BuildContext context, {
  required int contactId,
  Bill? bill,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BillForm(contactId: contactId, bill: bill),
  );
}

class _BillForm extends StatefulWidget {
  const _BillForm({required this.contactId, this.bill});
  final int contactId;
  final Bill? bill;

  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.bill?.title ?? '');
  late final _note = TextEditingController(text: widget.bill?.note ?? '');
  late String _direction = widget.bill?.direction ?? directionIn;
  bool _saving = false;

  bool get _isEdit => widget.bill != null;
  bool get _directionLocked => _isEdit && widget.bill!.hasTransactions;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final store = StoreScope.read(context);
    try {
      if (_isEdit) {
        await store.repo.updateBill(
          id: widget.bill!.id,
          title: _title.text,
          note: _note.text,
        );
        // 方向单独走 changeBillDirection：它会再查一次流水数，
        // 防止表单打开期间别处已经写了流水。
        if (!_directionLocked && _direction != widget.bill!.direction) {
          await store.repo.changeBillDirection(widget.bill!.id, _direction);
        }
      } else {
        await store.repo.insertBill(
          contactId: widget.contactId,
          title: _title.text,
          direction: _direction,
          note: _note.text,
        );
      }
      store.invalidate();
      if (mounted) Navigator.of(context).pop();
    } on LedgerFailure catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = LedgerPalette.of(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_isEdit ? '编辑账单' : '新建账单',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  autofocus: !_isEdit,
                  decoration: const InputDecoration(
                    labelText: '账单名称',
                    hintText: '例如：2026年春节借款',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '账单名称不能为空' : null,
                ),
                const SizedBox(height: 16),
                Text('这笔账算哪边？', style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ToneChoice(
                          label: '别人欠我',
                          caption: '应收',
                          icon: Icons.north_east,
                          tone: Tone.receivable,
                          selected: _direction == directionIn,
                          enabled: !_directionLocked,
                          onTap: () => setState(() => _direction = directionIn),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ToneChoice(
                          label: '我欠别人',
                          caption: '应付',
                          icon: Icons.south_east,
                          tone: Tone.payable,
                          selected: _direction == directionOut,
                          enabled: !_directionLocked,
                          onTap: () => setState(() => _direction = directionOut),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_directionLocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, size: 15, color: pal.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '这个账单下已有流水，方向不能改：一改，借款与还款的含义会整体反转，账就算反了。',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: pal.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_isEdit ? '保存' : '创建账单'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
