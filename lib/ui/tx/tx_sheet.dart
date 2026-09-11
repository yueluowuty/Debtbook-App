import 'package:flutter/material.dart';

import '../../db/repo.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/store.dart';
import '../theme.dart';
import '../widgets/ledger_widgets.dart';

/// 记一笔：起始借款 / 再借款 / 还款都走这一个面板，
/// 只有 kind 不同，账单余额由 repo 重算，界面从不手工加减。
Future<void> showTxSheet(
  BuildContext context, {
  required Bill bill,
  Tx? tx,
  String initialKind = kindPrincipal,
  List<Bill> movableTargets = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TxForm(
      bill: bill,
      tx: tx,
      initialKind: initialKind,
      movableTargets: movableTargets,
    ),
  );
}

String _yuanInput(int cents) {
  final s = formatCents(cents);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseIso(String s) {
  if (!isValidDateIso(s)) return null;
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

class _TxForm extends StatefulWidget {
  const _TxForm({
    required this.bill,
    this.tx,
    this.initialKind = kindPrincipal,
    this.movableTargets = const [],
  });
  final Bill bill;
  final Tx? tx;
  final String initialKind;
  final List<Bill> movableTargets;

  @override
  State<_TxForm> createState() => _TxFormState();
}

class _TxFormState extends State<_TxForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount =
      TextEditingController(text: widget.tx == null ? '' : _yuanInput(widget.tx!.amountCents));
  late final _note = TextEditingController(text: widget.tx?.note ?? '');
  late final _channel = TextEditingController(text: widget.tx?.channel ?? '');
  late String _kind = widget.tx?.kind ?? widget.initialKind;
  late DateTime _date = _parseIso(widget.tx?.occurredDate ?? '') ?? DateTime.now();
  late int _billId = widget.tx?.billId ?? widget.bill.id;
  bool _saving = false;

  bool get _isEdit => widget.tx != null;
  bool get _isOut => widget.bill.direction == directionOut;

  /// 同一笔流水挪到别的账单需要二次确认，所以只在编辑时给这个选择。
  bool get _canMove => _isEdit && widget.movableTargets.isNotEmpty;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _channel.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_billId != widget.bill.id) {
      final target = widget.movableTargets.firstWhere((b) => b.id == _billId);
      final ok = await _confirmMove(target);
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    final store = StoreScope.read(context);
    final cents = parseYuanToCents(_amount.text)!;
    try {
      if (_isEdit) {
        await store.repo.updateTx(
          id: widget.tx!.id,
          kind: _kind,
          amountCents: cents,
          occurredDate: _isoDate(_date),
          channel: _channel.text,
          note: _note.text,
          billId: _billId,
        );
      } else {
        await store.repo.insertTx(
          billId: _billId,
          kind: _kind,
          amountCents: cents,
          occurredDate: _isoDate(_date),
          channel: _channel.text,
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

  Future<bool> _confirmMove(Bill target) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('把这笔流水挪到另一个账单？'),
        content: Text('将从「${widget.bill.title}」移出，计入「${target.title}」。\n'
            '两个账单的余额都会按流水重算。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('确认移动')),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = LedgerPalette.of(context);
    final mq = MediaQuery.of(context);
    final isIn = !_isOut;
    // 颜色跟着「对余额的影响」走：加欠款一笔是账单自己的方向色，
    // 还款一笔统一是橙色，和列表里的 −¥ 完全对应。
    final principalTone = isIn ? Tone.receivable : Tone.payable;

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit ? '编辑流水' : '记一笔',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    ToneBadge(
                      text: widget.bill.title,
                      tone: pal.toneOfDirection(widget.bill.direction),
                      dot: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ToneChoice(
                          label: _isOut ? '借入' : '借出',
                          caption: '欠款增加',
                          icon: Icons.north_east,
                          tone: principalTone,
                          selected: _kind == kindPrincipal,
                          onTap: () => setState(() => _kind = kindPrincipal),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ToneChoice(
                          label: '还款',
                          caption: '欠款减少',
                          icon: Icons.south_east,
                          tone: Tone.payable,
                          selected: _kind == kindPayment,
                          onTap: () => setState(() => _kind = kindPayment),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  autofocus: !_isEdit,
                  style: theme.textTheme.headlineSmall,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '金额',
                    prefixText: '¥ ',
                    hintText: '0.00',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入金额';
                    final cents = parseYuanToCents(v);
                    if (cents == null) {
                      return '金额最多两位小数，且必须大于 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '发生日期',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(_isoDate(_date)),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in kChannelPresets)
                      ChoiceChip(
                        label: Text(preset),
                        selected: _channel.text == preset,
                        onSelected: (_) => setState(() =>
                            _channel.text =
                                _channel.text == preset ? '' : preset),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _channel,
                  decoration: const InputDecoration(
                    labelText: '渠道（可选，也可自己填）',
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
                if (_canMove) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _billId,
                    decoration: const InputDecoration(
                      labelText: '计入哪个账单',
                    ),
                    items: [
                      for (final b in [widget.bill, ...widget.movableTargets])
                        DropdownMenuItem(value: b.id, child: Text(b.title)),
                    ],
                    onChanged: (v) => setState(() => _billId = v ?? _billId),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kind == kindPayment
                        ? pal.payable
                        : pal.receivable,
                  ),
                  onPressed: _saving ? null : _submit,
                  child: Text(_isEdit ? '保存修改' : '记一笔'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
