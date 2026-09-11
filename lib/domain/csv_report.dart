/// CSV 报表导出。只出不进，不参与恢复，因此没有解析风险。
///
/// 两条硬规定：
/// 1. 输出以 UTF-8 BOM 开头并使用 CRLF，否则中文在 Excel 里是乱码；
/// 2. 金额列写「元」的两位小数纯数字，不带千分位；剩余为负时才带负号。
///    「方向」「类型」列负责说明谁欠谁，这样金额列可以被 Excel 直接求和。
library;

import 'models.dart';
import 'money.dart';

const String _bom = '﻿';

const List<String> txCsvHeader = [
  '日期', '方向', '借款人', '账单', '类型', '金额(元)', '渠道', '备注'
];
const List<String> billCsvHeader = [
  '方向', '借款人', '账单', '本金合计(元)', '还款合计(元)', '剩余(元)',
  '状态', '说明', '笔数', '首笔日期', '最近日期'
];
const List<String> contactCsvHeader = [
  '借款人', '手机号', '应收合计(元)', '应付合计(元)', '净差额(元)',
  '账单数', '流水数', '最近活动', '状态', '备注'
];

/// 建议文件名，日期后缀便于同一目录里区分多次导出。
String csvFileName(String label, String dateIso) => '${label}_$dateIso.csv';

class CsvInput {
  CsvInput({required this.contacts, required this.bills, required this.txs});

  final List<Contact> contacts;
  final List<Bill> bills;
  final List<Tx> txs;

  late final Map<int, Contact> contactById = {
    for (final c in contacts) c.id: c
  };
  late final Map<int, Bill> billById = {
    for (final b in bills) b.id: b
  };

  Bill? billOf(Tx t) => billById[t.billId];

  /// 借款人：优先用账单反查，账单已不存在时退回流水上的冗余字段（正常导出不出现）。
  Contact? contactOf(Tx t) => contactById[billById[t.billId]?.contactId];

  /// 每个账单的笔数与首末日期，由流水现算，不信任查询带出的聚合值。
  late final Map<int, BillStat> statByBill = () {
    final map = <int, BillStat>{};
    for (final t in txs) {
      final stat = map.putIfAbsent(t.billId, BillStat.new);
      stat.count++;
      if (stat.first == null || t.occurredDate.compareTo(stat.first!) < 0) {
        stat.first = t.occurredDate;
      }
      if (stat.last == null || t.occurredDate.compareTo(stat.last!) > 0) {
        stat.last = t.occurredDate;
      }
    }
    return map;
  }();

  late final List<ContactTotal> contactTotals = () {
    final map = <int, ContactTotal>{};
    ContactTotal of(int id) => map.putIfAbsent(id, () => ContactTotal(id));
    for (final b in bills) {
      final t = of(b.contactId);
      t.billCount++;
      if (b.direction == directionOut) {
        t.payable += b.balanceCents;
      } else {
        t.receivable += b.balanceCents;
      }
    }
    for (final tx in txs) {
      final bill = billById[tx.billId];
      if (bill == null) continue;
      final t = of(bill.contactId);
      t.txCount++;
      if (t.last == null || tx.occurredDate.compareTo(t.last!) > 0) {
        t.last = tx.occurredDate;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final net = b.net.compareTo(a.net);
        if (net != 0) return net;
        return (contactById[a.contactId]?.name ?? '').compareTo(
            contactById[b.contactId]?.name ?? '');
      });
    return list;
  }();
}

class BillStat {
  int count = 0;
  String? first;
  String? last;
}

class ContactTotal {
  ContactTotal(this.contactId);

  final int contactId;
  int receivable = 0;
  int payable = 0;
  int billCount = 0;
  int txCount = 0;
  String? last;

  int get net => receivable - payable;
  bool get isClear => receivable == 0 && payable == 0;
}

String buildTransactionCsv(CsvInput input) {
  final txs = input.txs.toList()
    ..sort((a, b) {
      final d = a.occurredDate.compareTo(b.occurredDate);
      return d != 0 ? d : a.id.compareTo(b.id);
    });

  return _encode(txCsvHeader, [
    for (final t in txs)
      _txCells(input, t),
  ]);
}

List<String> _txCells(CsvInput input, Tx t) {
  final bill = input.billById[t.billId];
  final direction = bill?.direction ?? directionIn;
  return [
    t.occurredDate,
    directionShort(direction),
    input.contactOf(t)?.name ?? '',
    bill?.title ?? '',
    txKindLabel(direction, t.kind),
    formatCentsPlain(t.amountCents),
    t.channel ?? '',
    t.note ?? '',
  ];
}

String buildBillSummaryCsv(CsvInput input) {
  final bills = input.bills.toList()
    ..sort((a, b) {
      final an = input.contactById[a.contactId]?.name ?? '';
      final bn = input.contactById[b.contactId]?.name ?? '';
      final n = an.compareTo(bn);
      if (n != 0) return n;
      return a.id.compareTo(b.id);
    });

  return _encode(billCsvHeader, [
    for (final b in bills)
      _billCells(input, b),
  ]);
}

List<String> _billCells(CsvInput input, Bill b) {
  final stat = input.statByBill[b.id] ?? BillStat();
  return [
    directionShort(b.direction),
    input.contactById[b.contactId]?.name ?? '',
    b.title,
    formatCentsPlain(b.principalCents),
    formatCentsPlain(b.paymentCents),
    formatCentsPlain(b.balanceCents),
    b.statusLabel,
    balanceMeaning(b.direction, b.balanceCents),
    '${stat.count}',
    stat.first ?? '',
    stat.last ?? '',
  ];
}

String buildContactSummaryCsv(CsvInput input) {
  return _encode(contactCsvHeader, [
    for (final t in input.contactTotals)
      _contactCells(input, t),
  ]);
}

List<String> _contactCells(CsvInput input, ContactTotal t) {
  final c = input.contactById[t.contactId];
  return [
    c?.name ?? '',
    c?.phone ?? '',
    formatCentsPlain(t.receivable),
    formatCentsPlain(t.payable),
    formatCentsPlain(t.net),
    '${t.billCount}',
    '${t.txCount}',
    t.last ?? '',
    c != null && c.archived ? '已归档' : (t.isClear ? '已结清' : '有欠款'),
    c?.note ?? '',
  ];
}

/// 剩余金额的业务含义，避免看表的人搞错谁欠谁。
String balanceMeaning(String direction, int balance) {
  if (balance == 0) return '已结清';
  if (direction == directionOut) {
    return balance > 0 ? '我还欠对方' : '对方多付给我';
  }
  return balance > 0 ? '对方还欠我' : '对方多还了';
}

String _encode(List<String> header, List<List<String>> rows) {
  final buf = StringBuffer(_bom)..writelnCsvRow(header);
  for (final r in rows) {
    buf.writelnCsvRow(r);
  }
  return buf.toString();
}

extension on StringBuffer {
  void writelnCsvRow(List<String> cells) {
    write(cells.map(_escapeCell).join(','));
    write('\r\n');
  }
}

String _escapeCell(String value) {
  if (value.isEmpty) return value;
  final needsQuote = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  return needsQuote ? '"${value.replaceAll('"', '""')}"' : value;
}
