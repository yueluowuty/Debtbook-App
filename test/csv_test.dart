/// CSV 报表导出测试。重点验三件事：BOM 与 CRLF（否则 Excel 里中文乱码）、
/// 金额列的可求和性（纯数字两位小数、不带千分位、只在为负时带负号）、
/// 以及中文备注里的逗号/引号/换行不会破坏列结构。
library;

import 'dart:convert';

import 'package:debtbook/domain/csv_report.dart';
import 'package:debtbook/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

const String _bomChar = '﻿';

Contact _contact(int id, String name, {String? phone, String? note, bool archived = false}) =>
    Contact(
        id: id,
        name: name,
        phone: phone,
        note: note,
        archived: archived,
        createdAt: '2026-01-01T09:00:00.000');

Bill _bill(
  int id,
  int contactId,
  String title, {
  String direction = directionIn,
  int principal = 0,
  int payment = 0,
  int? balance,
}) =>
    Bill(
      id: id,
      contactId: contactId,
      title: title,
      note: null,
      direction: direction,
      principalCents: principal,
      paymentCents: payment,
      balanceCents: balance ?? (principal - payment),
      createdAt: '2026-01-01T09:00:00.000',
      updatedAt: '2026-01-01T09:00:00.000',
    );

Tx _tx(int id, int billId, String kind, int cents, String date,
        {String? channel, String? note}) =>
    Tx(
      id: id,
      billId: billId,
      kind: kind,
      amountCents: cents,
      occurredDate: date,
      channel: channel,
      note: note,
      createdAt: '2026-01-01T09:00:00.000',
      updatedAt: '2026-01-01T09:00:00.000',
    );

/// 一条应收（张三欠我 8000）+ 一条应付（我欠李四 3000）的最小可用账本。
CsvInput _sample() {
  return CsvInput(
    contacts: [
      _contact(1, '张三', phone: '13800000000', note: '老同学'),
      _contact(2, '李四'),
      _contact(3, '王五', archived: true),
    ],
    bills: [
      _bill(10, 1, '装修借款', principal: 1000000, payment: 200000),
      _bill(11, 2, '买车', direction: directionOut, principal: 300000),
      _bill(12, 3, '已清', principal: 50000, payment: 50000),
    ],
    txs: [
      _tx(100, 10, kindPrincipal, 1000000, '2026-01-01', channel: '微信'),
      _tx(101, 10, kindPayment, 200000, '2026-02-15', channel: '支付宝'),
      _tx(102, 11, kindPrincipal, 300000, '2026-03-20', note: '首付垫付'),
      _tx(103, 12, kindPrincipal, 50000, '2026-01-05'),
      _tx(104, 12, kindPayment, 50000, '2026-04-01'),
    ],
  );
}

List<String> _rawLines(String csv) {
  final lines = csv.split('\r\n')..removeWhere((l) => l.isEmpty);
  return lines.skip(1).toList();
}

/// 引号感知的切分：被双引号包住的逗号与换行都属于单元格内容，
/// 连续两个引号是转义。不这样解析，备注里一个逗号就能把列数撑乱。
List<String> _parseRow(String line) {
  final cells = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      cells.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString());
  return cells;
}

List<List<String>> _dataRows(String csv) =>
    _rawLines(csv).map(_parseRow).toList();

void main() {
  group('编码规则', () {
    test('三份报表都以 UTF-8 BOM 开头且用 CRLF 分行', () {
      final input = _sample();
      for (final csv in [
        buildTransactionCsv(input),
        buildBillSummaryCsv(input),
        buildContactSummaryCsv(input),
      ]) {
        expect(csv.startsWith(_bomChar), isTrue, reason: '缺 BOM 会在 Excel 里乱码');
        expect(csv, contains('\r\n'));
        expect(csv.replaceAll('\r\n', ''), isNot(contains('\n')),
            reason: '不允许出现裸 LF');
        expect(csv.endsWith('\r\n'), isTrue);
      }
    });

    test('BOM 解码后是标准的 EF BB BF 三字节', () {
      final bytes = const Utf8Encoder().convert(_bomChar);
      expect(bytes, [0xEF, 0xBB, 0xBF]);
    });

    test('表头行数与数据行数对得上', () {
      final input = _sample();
      expect(_dataRows(buildTransactionCsv(input)), hasLength(5));
      expect(_dataRows(buildBillSummaryCsv(input)), hasLength(3));
      expect(_dataRows(buildContactSummaryCsv(input)), hasLength(3),
          reason: '名下有账单的人都要出行，哪怕已经两讫或归档');
    });

    test('建议文件名带日期后缀', () {
      expect(csvFileName('流水明细', '2026-09-05'), '流水明细_2026-09-05.csv');
    });
  });

  group('转义', () {
    test('含逗号 / 引号 / 换行的备注被正确包裹', () {
      final input = CsvInput(
        contacts: [_contact(1, '张,三')],
        bills: [_bill(10, 1, '他说"借"了', principal: 100)],
        txs: [
          _tx(100, 10, kindPrincipal, 100, '2026-01-01', note: '第一行\n第二行, 带逗号'),
        ],
      );

      final csv = buildTransactionCsv(input);
      final raw = _rawLines(csv);
      expect(raw, hasLength(1), reason: '备注里的裸 LF 不能把一行撑成两行');
      expect(raw.single, contains('"张,三"'));
      expect(raw.single, contains('"他说""借""了"'));
      expect(raw.single, contains('"第一行\n第二行, 带逗号"'));

      final cells = _parseRow(raw.single);
      expect(cells, hasLength(txCsvHeader.length));
      expect(cells[2], '张,三');
      expect(cells[3], '他说"借"了');
      expect(cells[7], '第一行\n第二行, 带逗号');
    });

    test('普通单元格不加引号', () {
      final rows = _dataRows(buildTransactionCsv(_sample()));
      expect(rows.first[0], '2026-01-01');
      expect(rows.first[6], '微信');
      expect(rows.first[7], '');
    });
  });

  group('流水明细', () {
    test('列顺序：日期/方向/借款人/账单/类型/金额/渠道/备注', () {
      final rows = _dataRows(buildTransactionCsv(_sample()));
      expect(rows.first, [
        '2026-01-01', '应收', '张三', '装修借款', '借出', '10000.00', '微信', '',
      ]);
      expect(
        rows.singleWhere((r) => r[0] == '2026-02-15'),
        ['2026-02-15', '应收', '张三', '装修借款', '还款', '2000.00', '支付宝', ''],
      );
    });

    test('按日期升序，同一天按 id 升序', () {
      final dates =
          _dataRows(buildTransactionCsv(_sample())).map((r) => r.first).toList();
      final sorted = [...dates]..sort();
      expect(dates, sorted);
    });

    test('应付账单上的本金叫「借入」，不叫「借出」', () {
      final rows = _dataRows(buildTransactionCsv(_sample()));
      final buyCar = rows.singleWhere((r) => r[3] == '买车');
      expect(buyCar[1], '应付');
      expect(buyCar[4], '借入');
    });

    test('金额列恒为正数，不带千分位也不带符号，因此可被 Excel 直接求和', () {
      final input = CsvInput(
        contacts: [_contact(1, '张三')],
        bills: [_bill(10, 1, '借款', principal: 123456789, payment: 1)],
        txs: [
          _tx(100, 10, kindPrincipal, 123456789, '2026-01-01'),
          _tx(101, 10, kindPayment, 1, '2026-01-02'),
        ],
      );
      final amounts =
          _dataRows(buildTransactionCsv(input)).map((r) => r[5]).toList();
      expect(amounts, ['1234567.89', '0.01']);
      for (final a in amounts) {
        expect(a, isNot(contains(',')));
        expect(a, isNot(contains('-')));
      }
    });
  });

  group('账单汇总', () {
    test('每行给出一条账单的完整口径', () {
      final rows = _dataRows(buildBillSummaryCsv(_sample()));
      final zhang = rows.singleWhere((r) => r[1] == '张三');
      expect(zhang, [
        '应收', '张三', '装修借款', '10000.00', '2000.00', '8000.00',
        '未结清', '对方还欠我', '2', '2026-01-01', '2026-02-15',
      ]);
      final li = rows.singleWhere((r) => r[1] == '李四');
      expect(li[6], '未结清');
      expect(li[7], '我还欠对方');
    });

    test('笔数与首末日期由流水现算，不信任模型上带的值', () {
      final rows = _dataRows(buildBillSummaryCsv(_sample()));
      final settled = rows.singleWhere((r) => r[2] == '已清');
      expect(settled[5], '0.00');
      expect(settled[6], '已结清');
      expect(settled[7], '已结清');
      expect(settled[8], '2');
      expect(settled[9], '2026-01-05');
      expect(settled[10], '2026-04-01');
    });

    test('无流水的空账单，笔数为 0 且日期留空', () {
      final input = CsvInput(
        contacts: [_contact(1, '张三')],
        bills: [_bill(10, 1, '刚建')],
        txs: const [],
      );
      final row = _dataRows(buildBillSummaryCsv(input)).single;
      expect(row[8], '0');
      expect(row[9], '');
      expect(row[10], '');
    });

    test('超收与多付在状态列区分开', () {
      final input = CsvInput(
        contacts: [_contact(1, '甲'), _contact(2, '乙')],
        bills: [
          _bill(10, 1, '超收', principal: 100, payment: 500),
          _bill(11, 2, '多付',
              direction: directionOut, principal: 100, payment: 500),
        ],
        txs: const [],
      );
      final rows = _dataRows(buildBillSummaryCsv(input));
      expect(rows.singleWhere((r) => r[2] == '超收').sublist(5, 8),
          ['-4.00', '已多收', '对方多还了']);
      expect(rows.singleWhere((r) => r[2] == '多付').sublist(5, 8),
          ['-4.00', '已多付', '对方多付给我']);
    });

    test('先按借款人姓名排，再按 id 排', () {
      final names =
          _dataRows(buildBillSummaryCsv(_sample())).map((r) => r[1]).toList();
      final sorted = [...names]..sort();
      expect(names, sorted);
    });
  });

  group('人员汇总', () {
    test('每人给出应收/应付/净差，按净差降序', () {
      final rows = _dataRows(buildContactSummaryCsv(_sample()));
      expect(rows.first[0], '张三');
      expect(rows.first.sublist(2, 5), ['8000.00', '0.00', '8000.00']);
      expect(rows.last[0], '李四');
      expect(rows.last.sublist(2, 5), ['0.00', '3000.00', '-3000.00']);
    });

    test('账单数/流水数/最近活动/状态各列齐备', () {
      final zhang = _dataRows(buildContactSummaryCsv(_sample())).first;
      expect(zhang[5], '1');
      expect(zhang[6], '2');
      expect(zhang[7], '2026-02-15');
      expect(zhang[8], '有欠款');
      expect(zhang[9], '老同学');
    });

    test('应收应付都为零的人标为已结清', () {
      final input = CsvInput(
        contacts: [_contact(1, '张三')],
        bills: [_bill(10, 1, '结清', principal: 500, payment: 500)],
        txs: const [],
      );
      final row = _dataRows(buildContactSummaryCsv(input)).single;
      expect(row.sublist(2, 5), ['0.00', '0.00', '0.00']);
      expect(row[8], '已结清');
    });

    test('人员表的条数等于有账单的人数', () {
      expect(_dataRows(buildContactSummaryCsv(_sample())), hasLength(3));
    });
  });

  group('空账本', () {
    test('没有任何数据时只输出表头，不抛异常', () {
      final empty = CsvInput(
          contacts: const [], bills: const [], txs: const []);
      expect(_dataRows(buildTransactionCsv(empty)), isEmpty);
      expect(_dataRows(buildBillSummaryCsv(empty)), isEmpty);
      expect(_dataRows(buildContactSummaryCsv(empty)), isEmpty);
      expect(buildTransactionCsv(empty),
          '$_bomChar${txCsvHeader.join(',')}\r\n');
    });

    test('有人但一分钱账都没有', () {
      final input = CsvInput(
          contacts: [_contact(1, '张三')],
          bills: const [],
          txs: const []);
      expect(_dataRows(buildContactSummaryCsv(input)), isEmpty);
    });
  });
}
