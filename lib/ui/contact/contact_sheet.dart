import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../domain/models.dart';
import '../../state/store.dart';
import '../theme.dart';

/// 新增 / 编辑借款人。
Future<void> showContactSheet(BuildContext context, {Contact? contact}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ContactForm(contact: contact),
  );
}

class _ContactForm extends StatefulWidget {
  const _ContactForm({this.contact});
  final Contact? contact;

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _phone = TextEditingController(text: widget.contact?.phone ?? '');
  late final _note = TextEditingController(text: widget.contact?.note ?? '');
  bool _saving = false;

  bool get _isEdit => widget.contact != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final store = StoreScope.read(context);
    try {
      if (_isEdit) {
        await store.repo.updateContact(
          id: widget.contact!.id,
          name: _name.text,
          phone: _phone.text,
          note: _note.text,
        );
      } else {
        await store.repo.insertContact(
          name: _name.text,
          phone: _phone.text,
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
                Text(_isEdit ? '编辑借款人' : '添加借款人',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  autofocus: !_isEdit,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    hintText: '例如：张三',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '姓名不能为空' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号（可选）',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_isEdit ? '保存' : '添加'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 归档/取消归档与删除都在这里，避免人员页塞满确认对话框。
Future<void> showContactActions(BuildContext context, Contact contact) async {
  final store = StoreScope.read(context);
  final counts = await store.repo.contactRecordCounts(contact.id);

  if (!context.mounted) return;
  final pal = LedgerPalette.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑资料'),
            onTap: () => Navigator.of(context).pop('edit'),
          ),
          ListTile(
            leading: Icon(contact.archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            title: Text(contact.archived ? '取消归档' : '归档（从列表隐藏，记录保留）'),
            onTap: () => Navigator.of(context).pop('archive'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: pal.danger),
            title: Text(
              counts.bills == 0
                  ? '删除这个借款人'
                  : '删除借款人及其 ${counts.bills} 个账单、${counts.transactions} 笔流水',
              style: TextStyle(color: pal.danger),
            ),
            subtitle: counts.bills == 0
                ? null
                : const Text('此操作不可撤销，建议先去「数据」页导出一份备份'),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'edit':
      await showContactSheet(context, contact: contact);
    case 'archive':
      await store.repo.setContactArchived(contact.id, !contact.archived);
      store.invalidate();
    case 'delete':
      final ok = await _confirmDelete(context, contact, counts);
      if (!ok || !context.mounted) return;
      try {
        if (counts.bills == 0) {
          await store.repo.deleteContact(contact.id);
        } else {
          await store.repo.deleteContactWithRecords(contact.id);
        }
        store.invalidate();
        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } on LedgerFailure catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
  }
}

Future<bool> _confirmDelete(
  BuildContext context,
  Contact contact,
  ({int bills, int transactions}) counts,
) async {
  final pal = LedgerPalette.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('删除「${contact.name}」？'),
      content: Text(counts.bills == 0
          ? '这个人还没有账单，删除后不可恢复。'
          : '将连带删除 ${counts.bills} 个账单和 ${counts.transactions} 笔流水，'
              '这些记录无法恢复。建议先到「数据」页导出一份备份。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: pal.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认删除'),
        ),
      ],
    ),
  );
  return yes ?? false;
}
