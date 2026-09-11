import 'dart:convert';

import 'package:debtbook/domain/models.dart';
import 'package:debtbook/domain/snapshot.dart';
import 'package:debtbook/domain/validate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('正常路径', () {
    test('一致的快照通过，且无告警', () {
      final json = consistentSnapshot(
        bills: [billRow(10, 1)],
        transactions: [
          txRow(100, 10, kind: kindPrincipal, amountCents: 500000, occurredDate: '2026-03-01'),
          txRow(101, 10, kind: kindPayment, amountCents: 200000, occurredDate: '2026-04-02'),
        ],
      );

      final result = validateSnapshot(json);

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      expect(result.data!.warnings, isEmpty);
      expect(result.data!.bills.single['balance_cents'], 300000);
      expect(result.data!.receivableCents, 300000);
      expect(result.data!.payableCents, 0);
    });

    test('导出对象的键顺序与库表列顺序一致（往返无损的前提）', () {
      final snapshot = buildSnapshot(
        contacts: [contactRow(1)],
        bills: [billRow(10, 1)],
        transactions: [txRow(100, 10)],
        appVersion: '1.0.0',
        exportedAt: '2026-09-05T22:00:00.000',
      );
      final data = snapshot['data'] as Map<String, Object?>;
      List<Map<String, Object?>> rows(String key) =>
          (data[key]! as List).cast<Map<String, Object?>>();

      expect(rows(kSnapshotKeyContacts).first.keys,
          ['id', 'name', 'phone', 'note', 'archived', 'created_at']);
      expect(rows(kSnapshotKeyBills).first.keys, [
        'id', 'contact_id', 'title', 'direction', 'note',
        'principal_cents', 'payment_cents', 'balance_cents', 'created_at', 'updated_at',
      ]);
      expect(rows(kSnapshotKeyTransactions).first.keys, [
        'id', 'bill_id', 'kind', 'amount_cents', 'occurred_date',
        'channel', 'note', 'created_at', 'updated_at',
      ]);
    });

    test('空账本导出后仍是合法快照', () {
      final snapshot = buildSnapshot(
        contacts: const [],
        bills: const [],
        transactions: const [],
        appVersion: '1.0.0',
        exportedAt: '2026-09-05T22:00:00.000',
      );
      final result = validateSnapshot(jsonDecode(encodeSnapshot(snapshot)));

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      expect(result.data!.isEmpty, isTrue);
      expect(result.data!.warnings, contains(contains('不含任何记录')));
    });
  });

  group('结构非法直接拒绝', () {
    test('非对象 / 缺 data / 缺 schemaVersion', () {
      expect(validateSnapshot([1, 2]).ok, isFalse);
      expect(validateSnapshot(null).ok, isFalse);
      expect(validateSnapshot({'schemaVersion': 1}).errors,
          contains(contains('data')));
      expect(validateSnapshot({'data': {}}).errors,
          contains(contains('schemaVersion')));
    });

    test('高于当前版本的快照要求升级 App', () {
      final result = validateSnapshot(consistentSnapshot(schemaVersion: 999));

      expect(result.ok, isFalse);
      expect(result.errors.single, allOf(contains('schemaVersion=999'), contains('升级')));
    });

    test('data 里的表不是数组', () {
      final result = validateSnapshot({
        'schemaVersion': 1,
        'data': {'contacts': {}, 'bills': [], 'transactions': []},
      });
      expect(result.errors, contains(contains('不是数组')));
    });
  });

  group('引用完整性', () {
    test('流水指向不存在的账单', () {
      final result = validateSnapshot(consistentSnapshot(
        bills: [billRow(10, 1)],
        transactions: [txRow(100, 999)],
      ));

      expect(result.ok, isFalse);
      expect(result.errors.single, allOf(contains('bill_id=999'), contains('不存在')));
    });

    test('账单指向不存在的借款人', () {
      final result = validateSnapshot(consistentSnapshot(
        contacts: [contactRow(1)],
        bills: [billRow(10, 42)],
      ));

      expect(result.ok, isFalse);
      expect(result.errors.single, contains('contact_id=42'));
    });

    test('id 重复', () {
      final result = validateSnapshot(consistentSnapshot(
        contacts: [contactRow(1), contactRow(1, name: '李四')],
      ));

      expect(result.ok, isFalse);
      expect(result.errors, contains(contains('id=1 重复')));
    });
  });

  group('字段级校验', () {
    test('金额为 0 / 负数 / 非整数都拒绝', () {
      for (final bad in [0, -100, 'abc', 12.5, null]) {
        final result = validateSnapshot(consistentSnapshot(
          bills: [billRow(10, 1)],
          transactions: [txRow(100, 10)..['amount_cents'] = bad],
        ));
        expect(result.ok, isFalse, reason: 'amount_cents=$bad 应被拒绝');
      }
    });

    test('非整数的 id 与外键拒绝（截断会让悬空引用过关）', () {
      final byBillId = validateSnapshot(consistentSnapshot(
        bills: [billRow(10, 1)],
        transactions: [txRow(100, 10)..['bill_id'] = 99.5],
      ));
      expect(byBillId.errors, contains(contains('bill_id=99.5')));

      final byContactId = validateSnapshot(consistentSnapshot(
        contacts: [contactRow(1)],
        bills: [billRow(10, 1)..['contact_id'] = 1.5],
      ));
      expect(byContactId.errors, contains(contains('contact_id=1.5')));

      final byId = validateSnapshot(consistentSnapshot(
        bills: const [],
        contacts: [contactRow(1)..['id'] = 3.7],
      ));
      expect(byId.errors, contains(contains('id 缺失或不是正整数')));
    });

    test('kind 与 direction 枚举', () {
      final byKind = validateSnapshot(consistentSnapshot(
        bills: [billRow(10, 1)],
        transactions: [txRow(100, 10)..['kind'] = 'interest'],
      ));
      expect(byKind.errors, contains(contains('kind=interest')));

      final byDirection = validateSnapshot(consistentSnapshot(
        bills: [billRow(10, 1)..['direction'] = 'up'],
      ));
      expect(byDirection.errors, contains(contains('direction=up')));
    });

    test('日期非法', () {
      final result = validateSnapshot(consistentSnapshot(
        bills: [billRow(10, 1)],
        transactions: [
          txRow(100, 10)..['occurred_date'] = '2026-02-30',
        ],
      ));
      expect(result.errors, contains(contains('occurred_date=2026-02-30')));
    });

    test('姓名为空', () {
      final result = validateSnapshot(consistentSnapshot(
        contacts: [contactRow(1, name: '   ')],
      ));
      expect(result.errors, contains(contains('姓名不能为空')));
    });
  });

  test('一次报出全部问题，而不是遇到第一个就停', () {
    final result = validateSnapshot({
      'schemaVersion': 1,
      'data': {
        'contacts': [contactRow(1, name: '')],
        'bills': [billRow(10, 99, direction: 'sideways')],
        'transactions': [
          txRow(100, 99, kind: 'x', amountCents: 0, occurredDate: 'bad'),
        ],
      },
    });

    expect(result.ok, isFalse);
    expect(result.errorCount, greaterThan(5));
    expect(result.errors.length, lessThanOrEqualTo(kMaxReportedErrors));
  });

  test('问题超过 20 条时截断展示但保留总数', () {
    final txs = [
      for (var i = 1; i <= 30; i++) txRow(100 + i, 999, occurredDate: 'bad-$i'),
    ];
    final result = validateSnapshot(consistentSnapshot(
      bills: [billRow(10, 1)],
      transactions: txs,
    ));

    expect(result.errors.length, kMaxReportedErrors);
    expect(result.errorCount, greaterThan(kMaxReportedErrors));
    expect(result.tailHint, isNotEmpty);
  });

  group('归一化', () {
    test('丢弃未知字段，避免 INSERT 因不存在的列抛错', () {
      final json = consistentSnapshot(
        contacts: [contactRow(1)..['extra_junk'] = 'x'],
        bills: [billRow(10, 1)..['legacy_col'] = 1],
      );
      final result = validateSnapshot(json);

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      expect(result.data!.contacts.single.containsKey('extra_junk'), isFalse);
      expect(result.data!.bills.single.containsKey('legacy_col'), isFalse);
    });

    test('缺失的可选列补 null、archived 补 0、时间戳回填导出时间', () {
      final json = consistentSnapshot(
        contacts: [
          {'id': 1, 'name': '张三'},
        ],
      );
      final result = validateSnapshot(json);

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      final row = result.data!.contacts.single;
      expect(row['phone'], isNull);
      expect(row['archived'], 0);
      expect(row['created_at'], '2026-09-05T22:00:00.000');
    });

    test('布尔 archived 与字符串数字都能吃下', () {
      final json = consistentSnapshot(
        contacts: [
          {'id': 1, 'name': '张三', 'archived': true},
          {'id': 2, 'name': '李四', 'archived': '1'},
        ],
      );
      final result = validateSnapshot(json);

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      expect(result.data!.contacts[0]['archived'], 1);
      expect(result.data!.contacts[1]['archived'], 1);
    });
  });

  group('派生列以流水为准', () {
    test('文件里余额写错只告警，值被按流水重算', () {
      final json = {
        'schemaVersion': 1,
        'data': {
          'contacts': [contactRow(1)],
          'bills': [
            billRow(10, 1, principalCents: 1, paymentCents: 1, balanceCents: 999999),
          ],
          'transactions': [
            txRow(100, 10, kind: kindPrincipal, amountCents: 500000),
            txRow(101, 10, kind: kindPayment, amountCents: 200000),
          ],
        },
      };
      final result = validateSnapshot(json);

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      final bill = result.data!.bills.single;
      expect(bill['principal_cents'], 500000);
      expect(bill['payment_cents'], 200000);
      expect(bill['balance_cents'], 300000);
      expect(result.data!.warnings, contains(contains('按流水重算')));
    });

    test('超付时余额重算为负数而不是被夹到零', () {
      final json = consistentSnapshot(
        bills: [billRow(10, 1)],
        transactions: [
          txRow(100, 10, kind: kindPrincipal, amountCents: 100000),
          txRow(101, 10, kind: kindPayment, amountCents: 150000),
        ],
      );
      final result = validateSnapshot(json);

      expect(result.data!.bills.single['balance_cents'], -50000);
      expect(
          billStatusLabel(directionIn, -50000), '已多收');
    });

    test('summary 与实际不符只告警', () {
      final json = consistentSnapshot(
        summary: {'contacts': 99, 'bills': 1, 'transactions': 0},
      );
      final result = validateSnapshot(json);

      expect(result.ok, isTrue);
      expect(result.data!.warnings, contains(contains('contacts=99')));
    });
  });

  test('encodeSnapshot 产物可被 validateSnapshot 原样接住', () {
    final snapshot = buildSnapshot(
      contacts: [contactRow(1, name: '王五', phone: '13800000000')],
      bills: [billRow(10, 1, title: '装修借款', direction: directionOut)],
      transactions: [
        txRow(100, 10, kind: kindPrincipal, amountCents: 3000000, occurredDate: '2026-05-06'),
        txRow(101, 10, kind: kindPayment, amountCents: 1000000, occurredDate: '2026-06-01'),
      ],
      appVersion: '1.0.0',
      exportedAt: '2026-09-05T22:00:00.000',
    );

    final result = validateSnapshot(jsonDecode(encodeSnapshot(snapshot)));

    expect(result.ok, isTrue, reason: result.errors.join('\n'));
    expect(result.data!.payableCents, 2000000);
    expect(result.data!.warnings, isEmpty);
  });
}
