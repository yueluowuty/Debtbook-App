/// 数据层测试。跑的是开发机上的真实 SQLite（sqflite_common_ffi），
/// 因此外键、CHECK 约束、SUM 重算、事务回滚都是实际行为而非模拟。
library;

import 'dart:convert';
import 'dart:io';

import 'package:debtbook/db/helper.dart';
import 'package:debtbook/db/repo.dart';
import 'package:debtbook/domain/models.dart';
import 'package:debtbook/domain/snapshot.dart';
import 'package:debtbook/domain/validate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'helpers.dart';

void main() {
  late Directory tempRoot;
  final opened = <Database>[];

  setUpAll(() {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  });

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('debtbook_test'));

  tearDown(() async {
    // 用例失败时 body 里的 db.close() 不会执行，Windows 会因此锁住临时目录，
    // 把真正的断言失败盖成 PathAccessException。这里兜底关干净。
    for (final db in opened) {
      try {
        await db.close();
      } on Exception {
        // 已经关过的再次 close 是良性的。
      }
    }
    opened.clear();
    tempRoot.deleteSync(recursive: true);
  });

  /// 每个用例一个独立库文件，避免 sqflite 的 singleInstance 缓存串味。
  Future<(Database, LedgerRepo)> open(String name) async {
    final path = '${tempRoot.path}${Platform.pathSeparator}$name';
    final db = await openLedgerDatabase(path);
    opened.add(db);
    return (db, LedgerRepo(db));
  }

  Future<Map<String, Object?>> billRowOf(Database db, int id) async =>
      (await db.query(kTableBills, where: 'id = ?', whereArgs: [id])).single;

  Future<void> seed(LedgerRepo repo, int billId,
      List<(String kind, int cents, String date)> entries) async {
    for (final (kind, cents, date) in entries) {
      await repo.insertTx(
          billId: billId,
          kind: kind,
          amountCents: cents,
          occurredDate: date);
    }
  }

  Future<int> newBill(LedgerRepo repo, int contactId,
          {String title = '借款', String direction = directionIn}) =>
      repo.insertBill(
          contactId: contactId, title: title, direction: direction);

  // ================================================================ 约束
  group('库级约束', () {
    test('PRAGMA foreign_keys 确实开着', () async {
      final (db, _) = await open('fk');
      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.single.values.first, 1);
      await db.close();
    });

    test('账单指向不存在的借款人被外键拦住', () async {
      final (db, _) = await open('fk_contact');
      await expectLater(
        db.insert(kTableBills, {
          'contact_id': 999,
          'title': '幽灵借款',
          'direction': directionIn,
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('流水指向不存在的账单被外键拦住', () async {
      final (db, _) = await open('fk_bill');
      await expectLater(
        db.insert(kTableTransactions, {
          'bill_id': 999,
          'kind': kindPrincipal,
          'amount_cents': 100,
          'occurred_date': '2026-01-01',
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('金额必须为正：0 与负数被 CHECK 拦住', () async {
      final (db, repo) = await open('check_amount');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      for (final amount in [0, -100]) {
        await expectLater(
          db.insert(kTableTransactions, {
            'bill_id': bid,
            'kind': kindPrincipal,
            'amount_cents': amount,
            'occurred_date': '2026-01-01',
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'amount_cents=$amount 不该写进去',
        );
      }
      await db.close();
    });

    test('kind 与 direction 枚举由 CHECK 兜住', () async {
      final (db, repo) = await open('check_enum');
      final cid = await repo.insertContact(name: '张三');
      await expectLater(
        db.insert(kTableBills, {
          'contact_id': cid,
          'title': 'x',
          'direction': 'both',
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
      final bid = await newBill(repo, cid);
      await expectLater(
        db.insert(kTableTransactions, {
          'bill_id': bid,
          'kind': 'gift',
          'amount_cents': 100,
          'occurred_date': '2026-01-01',
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('直接删除仍有账单的借款人被 RESTRICT 拦住', () async {
      final (db, repo) = await open('restrict');
      final cid = await repo.insertContact(name: '张三');
      await newBill(repo, cid);
      await expectLater(
        db.delete(kTableContacts, where: 'id = ?', whereArgs: [cid]),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });
  });

  // ================================================================ 重算
  group('派生列重算', () {
    test('借款 → 还款 → 再借款，三列始终由流水推导', () async {
      final (db, repo) = await open('recompute_flow');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid, title: '装修借款');

      await seed(repo, bid, [(kindPrincipal, 500000, '2026-01-01')]);
      var row = await billRowOf(db, bid);
      expect(row['principal_cents'], 500000);
      expect(row['payment_cents'], 0);
      expect(row['balance_cents'], 500000);

      await seed(repo, bid, [(kindPayment, 200000, '2026-02-01')]);
      row = await billRowOf(db, bid);
      expect(row['principal_cents'], 500000);
      expect(row['payment_cents'], 200000);
      expect(row['balance_cents'], 300000);

      await seed(repo, bid, [(kindPrincipal, 100000, '2026-03-01')]);
      row = await billRowOf(db, bid);
      expect(row['principal_cents'], 600000, reason: '再借款要累加进本金');
      expect(row['payment_cents'], 200000);
      expect(row['balance_cents'], 400000);
      await db.close();
    });

    test('改流水金额后重算', () async {
      final (db, repo) = await open('recompute_amount');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      final txId = await repo.insertTx(
          billId: bid,
          kind: kindPrincipal,
          amountCents: 500000,
          occurredDate: '2026-01-01');

      await repo.updateTx(id: txId, amountCents: 123456);
      final row = await billRowOf(db, bid);
      expect(row['principal_cents'], 123456);
      expect(row['balance_cents'], 123456);
      await db.close();
    });

    test('流水类型从借款改成还款，金额要在两列之间搬走', () async {
      final (db, repo) = await open('recompute_kind');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      final txId = await repo.insertTx(
          billId: bid,
          kind: kindPrincipal,
          amountCents: 300000,
          occurredDate: '2026-01-01');

      await repo.updateTx(id: txId, kind: kindPayment);
      final row = await billRowOf(db, bid);
      expect(row['principal_cents'], 0);
      expect(row['payment_cents'], 300000);
      expect(row['balance_cents'], -300000);
      await db.close();
    });

    test('改日期只动首末日期，不影响金额', () async {
      final (db, repo) = await open('recompute_date');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      final txId = await repo.insertTx(
          billId: bid,
          kind: kindPrincipal,
          amountCents: 123456,
          occurredDate: '2026-01-01');

      await repo.updateTx(id: txId, occurredDate: '2025-12-31');
      final bill = await repo.requireBill(bid);
      expect(bill.firstDate, '2025-12-31');
      expect(bill.balanceCents, 123456);
      await db.close();
    });

    test('删除最后一笔流水后账单归零（账单本身保留）', () async {
      final (db, repo) = await open('recompute_delete');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      final txId = await repo.insertTx(
          billId: bid,
          kind: kindPrincipal,
          amountCents: 300000,
          occurredDate: '2026-01-01');

      await repo.deleteTx(txId);
      final row = await billRowOf(db, bid);
      expect(row['principal_cents'], 0);
      expect(row['balance_cents'], 0);
      expect((await repo.requireBill(bid)).isSettled, isTrue);
      await db.close();
    });

    test('删除不存在的流水是空操作，不报错也不改账', () async {
      final (db, repo) = await open('recompute_delete_missing');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [(kindPrincipal, 100000, '2026-01-01')]);

      await repo.deleteTx(9999);
      expect((await billRowOf(db, bid))['balance_cents'], 100000);
      await db.close();
    });

    test('跨账单挪流水：新旧两个账单都要重算（漏一个就算错）', () async {
      final (db, repo) = await open('recompute_move');
      final cid = await repo.insertContact(name: '张三');
      final from = await newBill(repo, cid, title: 'A 账单');
      final to = await newBill(repo, cid, title: 'B 账单');

      final txId = await repo.insertTx(
          billId: from,
          kind: kindPrincipal,
          amountCents: 400000,
          occurredDate: '2026-01-01');
      await seed(repo, to, [
        (kindPrincipal, 100000, '2026-01-02'),
        (kindPayment, 40000, '2026-01-03'),
      ]);

      await repo.updateTx(id: txId, billId: to);

      final a = await billRowOf(db, from);
      final b = await billRowOf(db, to);
      expect(a['principal_cents'], 0, reason: '旧账单必须被拉平');
      expect(a['balance_cents'], 0);
      expect(b['principal_cents'], 500000);
      expect(b['payment_cents'], 40000);
      expect(b['balance_cents'], 460000);
      await db.close();
    });

    test('超付时余额为负，标记为多收而不是结清', () async {
      final (db, repo) = await open('recompute_overpay');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [
        (kindPrincipal, 100000, '2026-01-01'),
        (kindPayment, 150000, '2026-02-01'),
      ]);

      final bill = await repo.requireBill(bid);
      expect(bill.balanceCents, -50000);
      expect(bill.isSettled, isFalse);
      expect(bill.isOverpaid, isTrue);
      await db.close();
    });

    test('已结清的账单再借一笔，状态自动回到未结清', () async {
      final (db, repo) = await open('recompute_reopen');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [
        (kindPrincipal, 100000, '2026-01-01'),
        (kindPayment, 100000, '2026-02-01'),
      ]);
      expect((await repo.requireBill(bid)).isSettled, isTrue);

      await seed(repo, bid, [(kindPrincipal, 5000, '2026-03-01')]);
      final bill = await repo.requireBill(bid);
      expect(bill.balanceCents, 5000);
      expect(bill.isSettled, isFalse);
      await db.close();
    });

    test('手工把派生列改脏后，recomputeBills 能完全纠正', () async {
      final (db, repo) = await open('recompute_authority');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [
        (kindPrincipal, 700000, '2026-01-01'),
        (kindPayment, 200000, '2026-01-05'),
      ]);

      await db.update(kTableBills,
          {'principal_cents': 1, 'payment_cents': 2, 'balance_cents': 3},
          where: 'id = ?', whereArgs: [bid]);
      expect((await billRowOf(db, bid))['balance_cents'], 3);

      await recomputeBills(db, {bid});
      final row = await billRowOf(db, bid);
      expect(row['principal_cents'], 700000);
      expect(row['payment_cents'], 200000);
      expect(row['balance_cents'], 500000,
          reason: 'balance 走独立 CASE 子查询，不引用同行旧值');
      await db.close();
    });

    test('SQL 重算与校验器里的纯 Dart 重算结果一致', () async {
      final (db, repo) = await open('recompute_parity');
      final bills = [
        billRow(10, 1, direction: directionIn),
        billRow(11, 1, direction: directionOut),
        billRow(12, 2, direction: directionIn),
      ];
      final txs = [
        txRow(100, 10, amountCents: 500000, occurredDate: '2026-01-01'),
        txRow(101, 10,
            kind: kindPayment, amountCents: 100000, occurredDate: '2026-01-02'),
        txRow(102, 11, amountCents: 300000, occurredDate: '2026-01-03'),
        txRow(103, 11,
            kind: kindPayment, amountCents: 350000, occurredDate: '2026-01-04'),
        txRow(104, 12, amountCents: 1, occurredDate: '2026-01-05'),
      ];
      final validated = validateSnapshot(consistentSnapshot(
          contacts: [contactRow(1), contactRow(2, name: '李四')],
          bills: bills,
          transactions: txs));
      expect(validated.ok, isTrue, reason: validated.errors.join('\n'));
      await repo.replaceAll(validated.data!);

      for (final row in await db.query(kTableBills, orderBy: 'id ASC')) {
        final id = row['id'] as int;
        var principal = 0, payment = 0;
        for (final t in txs) {
          if (t['bill_id'] != id) continue;
          if (t['kind'] == kindPrincipal) {
            principal += t['amount_cents'] as int;
          } else {
            payment += t['amount_cents'] as int;
          }
        }
        expect(row['principal_cents'], principal, reason: 'bill $id principal');
        expect(row['payment_cents'], payment, reason: 'bill $id payment');
        expect(row['balance_cents'], principal - payment,
            reason: 'bill $id balance');
      }
      await db.close();
    });
  });

  // ================================================================ 查询
  group('汇总查询', () {
    test('totals 把应收/应付分开加，净差是两者之差', () async {
      final (db, repo) = await open('totals');
      final a = await repo.insertContact(name: '张三');
      final b = await repo.insertContact(name: '李四');
      final in1 =
          await newBill(repo, a, title: '借出', direction: directionIn);
      final in2 =
          await newBill(repo, b, title: '借出2', direction: directionIn);
      final out1 =
          await newBill(repo, a, title: '借入', direction: directionOut);

      await seed(repo, in1, [(kindPrincipal, 1000000, '2026-01-01')]);
      await seed(repo, in2, [
        (kindPrincipal, 300000, '2026-01-01'),
        (kindPayment, 100000, '2026-01-02'),
      ]);
      await seed(repo, out1, [(kindPrincipal, 200000, '2026-01-01')]);

      final totals = await repo.totals();
      expect(totals.receivableCents, 1200000);
      expect(totals.payableCents, 200000);
      expect(totals.netCents, 1000000);
      await db.close();
    });

    test('空库汇总为 0 而不是 null', () async {
      final (db, repo) = await open('totals_empty');
      final totals = await repo.totals();
      expect(totals.isEmpty, isTrue);
      expect(totals.receivableCents, 0);
      expect(totals.netCents, 0);
      expect(await repo.contactCount(), 0);
      expect(await repo.listContacts(), isEmpty);
      await db.close();
    });

    test('人员列表带出应收/应付/账单数/流水数/最近活动', () async {
      final (db, repo) = await open('list_contacts');
      final cid = await repo.insertContact(name: '张三');
      final b1 = await newBill(repo, cid, title: 'A');
      final b2 = await newBill(repo, cid, title: 'B', direction: directionOut);
      await seed(repo, b1, [
        (kindPrincipal, 500000, '2026-03-01'),
        (kindPayment, 200000, '2026-05-20'),
      ]);
      await seed(repo, b2, [(kindPrincipal, 100000, '2026-04-10')]);

      final contact = (await repo.listContacts()).single;
      expect(contact.name, '张三');
      expect(contact.receivableCents, 300000);
      expect(contact.payableCents, 100000);
      expect(contact.netCents, 200000);
      expect(contact.billCount, 2);
      expect(contact.txCount, 3);
      expect(contact.lastActivity, '2026-05-20');
      await db.close();
    });

    test('没有流水的人也要出现在列表里，各项为 0', () async {
      final (db, repo) = await open('list_zero_person');
      await repo.insertContact(name: '张三');
      final contact = (await repo.listContacts()).single;
      expect(contact.receivableCents, 0);
      expect(contact.billCount, 0);
      expect(contact.txCount, 0);
      expect(contact.lastActivity, isNull);
      await db.close();
    });

    test('搜索命中姓名与手机号子串', () async {
      final (db, repo) = await open('search');
      await repo.insertContact(name: '张三', phone: '13800000001');
      await repo.insertContact(name: '王五', phone: '13900000002');
      expect((await repo.listContacts(search: '张')).map((c) => c.name), ['张三']);
      expect((await repo.listContacts(search: '00002')).map((c) => c.name),
          ['王五']);
      expect(await repo.listContacts(search: '不存在的人'), isEmpty);
      await db.close();
    });

    test('按方向筛选只留下该方向上还有余额的人', () async {
      final (db, repo) = await open('filter_direction');
      final lender = await repo.insertContact(name: '欠我钱的人');
      final borrower = await repo.insertContact(name: '我欠钱的人');
      final settled = await repo.insertContact(name: '两清的人');

      final l1 = await newBill(repo, lender, title: 'A');
      final b1 = await newBill(repo, borrower,
          title: 'B', direction: directionOut);
      final s1 = await newBill(repo, settled, title: 'C');

      await seed(repo, l1, [(kindPrincipal, 100000, '2026-01-01')]);
      await seed(repo, b1, [(kindPrincipal, 100000, '2026-01-01')]);
      await seed(repo, s1, [
        (kindPrincipal, 100000, '2026-01-01'),
        (kindPayment, 100000, '2026-01-02'),
      ]);

      final receivers =
          (await repo.listContacts(direction: directionIn)).map((c) => c.name);
      expect(receivers, contains('欠我钱的人'));
      expect(receivers, isNot(contains('两清的人')));
      expect(receivers, isNot(contains('我欠钱的人')));
      expect(
          (await repo.listContacts(direction: directionOut)).map((c) => c.name),
          ['我欠钱的人']);
      await db.close();
    });

    test('归档的人默认不出现，includeArchived 才能看到', () async {
      final (db, repo) = await open('archived');
      final keep = await repo.insertContact(name: '在册');
      final gone = await repo.insertContact(name: '已归档');
      await repo.setContactArchived(gone, true);

      expect((await repo.listContacts()).map((c) => c.name), ['在册']);
      expect(await repo.contactCount(), 1);
      expect(await repo.contactCount(includeArchived: true), 2);
      expect((await repo.listContacts(includeArchived: true)).length, 2);
      expect((await repo.requireContact(keep)).archived, isFalse);
      expect((await repo.requireContact(gone)).archived, isTrue);
      await db.close();
    });

    test('账单查询带出笔数与首末日期，按方向字典序再按 id 排序', () async {
      final (db, repo) = await open('bills_of_contact');
      final cid = await repo.insertContact(name: '张三');
      final in1 = await newBill(repo, cid, title: '借出A');
      await newBill(repo, cid, title: '借入B', direction: directionOut);
      await seed(repo, in1, [
        (kindPrincipal, 100000, '2026-06-01'),
        (kindPayment, 30000, '2026-02-01'),
      ]);

      final bills = await repo.billsOfContact(cid);
      expect(bills.map((b) => b.title), ['借出A', '借入B'],
          reason: "字典序 'in' < 'out'");
      expect(bills.first.txCount, 2);
      expect(bills.first.firstDate, '2026-02-01');
      expect(bills.first.lastDate, '2026-06-01');
      expect(bills.last.txCount, 0);
      expect(bills.last.firstDate, isNull);
      await db.close();
    });

    test('流水列表按日期倒序，同一天按 id 倒序', () async {
      final (db, repo) = await open('tx_order');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [
        (kindPrincipal, 100000, '2026-01-01'),
        (kindPayment, 10000, '2026-03-01'),
        (kindPrincipal, 20000, '2026-01-01'),
      ]);

      final list = await repo.txsOfBill(bid);
      expect(list.map((t) => t.occurredDate),
          ['2026-03-01', '2026-01-01', '2026-01-01']);
      expect(list[1].amountCents, 20000, reason: '同日内后写入的在前');
      expect(list[2].amountCents, 100000);
      await db.close();
    });

    test('人员时间线跨账单汇总该人全部流水', () async {
      final (db, repo) = await open('txs_of_contact');
      final cid = await repo.insertContact(name: '张三');
      final other = await repo.insertContact(name: '李四');
      final b1 = await newBill(repo, cid, title: 'A');
      final b2 = await newBill(repo, cid, title: 'B');
      final b3 = await newBill(repo, other, title: 'C');
      await seed(repo, b1, [(kindPrincipal, 100000, '2026-01-01')]);
      await seed(repo, b2, [(kindPayment, 5000, '2026-02-01')]);
      await seed(repo, b3, [(kindPrincipal, 90000, '2026-03-01')]);

      final list = await repo.txsOfContact(cid);
      expect(list, hasLength(2));
      expect(list.map((t) => t.occurredDate), ['2026-02-01', '2026-01-01']);
      await db.close();
    });

    test('查不存在的人/账单给出可读的 LedgerFailure', () async {
      final (db, repo) = await open('require_missing');
      await expectLater(
          repo.requireContact(1), throwsA(isA<LedgerFailure>()));
      await expectLater(repo.requireBill(1), throwsA(isA<LedgerFailure>()));
      await db.close();
    });
  });

  // ================================================================ 禁令
  group('v1 业务禁令', () {
    test('有流水的账单禁止改方向', () async {
      final (db, repo) = await open('direction_locked');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [(kindPrincipal, 100000, '2026-01-01')]);

      await expectLater(repo.changeBillDirection(bid, directionOut),
          throwsA(isA<LedgerFailure>()));
      expect((await repo.requireBill(bid)).direction, directionIn);
      await db.close();
    });

    test('没有流水的账单允许改方向，非法值仍被拒', () async {
      final (db, repo) = await open('direction_open');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await repo.changeBillDirection(bid, directionOut);
      expect((await repo.requireBill(bid)).direction, directionOut);
      await expectLater(repo.changeBillDirection(bid, 'both'),
          throwsA(isA<LedgerFailure>()));
      await db.close();
    });

    test('有流水的账单禁止删除', () async {
      final (db, repo) = await open('bill_delete');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [(kindPrincipal, 100000, '2026-01-01')]);
      await expectLater(
          repo.deleteBill(bid), throwsA(isA<LedgerFailure>()));
      expect(await db.query(kTableBills), hasLength(1));
      await db.close();
    });

    test('无流水的账单可以删除，也不影响别人', () async {
      final (db, repo) = await open('bill_delete_ok');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid, title: '误建');
      await newBill(repo, cid, title: '保留');
      await repo.deleteBill(bid);
      expect((await repo.allBills()).map((b) => b.title), ['保留']);
      expect(await repo.contactCount(), 1);
      await db.close();
    });

    test('名下有账单时禁止直接删人', () async {
      final (db, repo) = await open('contact_delete');
      final cid = await repo.insertContact(name: '张三');
      await newBill(repo, cid);
      await expectLater(
          repo.deleteContact(cid), throwsA(isA<LedgerFailure>()));
      expect(await repo.contactCount(includeArchived: true), 1);
      await db.close();
    });

    test('名下无账单时可以直接删人', () async {
      final (db, repo) = await open('contact_delete_ok');
      final cid = await repo.insertContact(name: '误建');
      await repo.deleteContact(cid);
      expect(await repo.contactCount(includeArchived: true), 0);
      await db.close();
    });

    test('空白姓名 / 空白账单名 / 非法方向被拒', () async {
      final (db, repo) = await open('blank_names');
      await expectLater(
          repo.insertContact(name: '   '), throwsA(isA<LedgerFailure>()));
      final cid = await repo.insertContact(name: '张三');
      await expectLater(newBill(repo, cid, title: ' '),
          throwsA(isA<LedgerFailure>()));
      await expectLater(
        repo.insertBill(
            contactId: cid, title: '正常', direction: 'sideways'),
        throwsA(isA<LedgerFailure>()),
      );
      await db.close();
    });

    test('可选字段前后空白被裁掉，纯空白存成 null', () async {
      final (db, repo) = await open('cleaning');
      final cid = await repo.insertContact(
          name: '  张三  ', phone: '  ', note: ' 备注 ');
      final contact = await repo.requireContact(cid);
      expect(contact.name, '张三');
      expect(contact.phone, isNull);
      expect(contact.note, '备注');
      await db.close();
    });

    test('流水的非法 kind / 金额 / 日期都被挡在写库之前', () async {
      final (db, repo) = await open('bad_tx');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await expectLater(
        repo.insertTx(
            billId: bid,
            kind: 'gift',
            amountCents: 100000,
            occurredDate: '2026-01-01'),
        throwsA(isA<LedgerFailure>()),
      );
      for (final amount in [0, -100]) {
        await expectLater(
          repo.insertTx(
              billId: bid,
              kind: kindPrincipal,
              amountCents: amount,
              occurredDate: '2026-01-01'),
          throwsA(isA<LedgerFailure>()),
          reason: 'amountCents=$amount',
        );
      }
      for (final date in ['2026-02-30', '2026-1-1', '', '20260101']) {
        await expectLater(
          repo.insertTx(
              billId: bid,
              kind: kindPrincipal,
              amountCents: 100000,
              occurredDate: date),
          throwsA(isA<LedgerFailure>()),
          reason: 'date=$date',
        );
      }
      expect(await repo.allTxs(), isEmpty);
      await db.close();
    });

    test('连带删除：人、账单、流水一起走，不留悬空引用', () async {
      final (db, repo) = await open('cascade');
      final keep = await repo.insertContact(name: '留下的人');
      final gone = await repo.insertContact(name: '走的人');
      final keepBill = await newBill(repo, keep, title: '保留');
      final goneBill = await newBill(repo, gone, title: '连带');
      await seed(repo, keepBill, [(kindPrincipal, 100000, '2026-01-01')]);
      await seed(repo, goneBill, [
        (kindPrincipal, 200000, '2026-01-01'),
        (kindPayment, 50000, '2026-01-02'),
      ]);

      final counts = await repo.contactRecordCounts(gone);
      expect(counts.bills, 1);
      expect(counts.transactions, 2);

      await repo.deleteContactWithRecords(gone);

      expect((await repo.listContacts(includeArchived: true)).map((c) => c.id),
          [keep]);
      expect(await db.query(kTableBills, where: 'contact_id = ?', whereArgs: [gone]),
          isEmpty);
      expect(await db.query(kTableTransactions, where: 'bill_id = ?', whereArgs: [goneBill]),
          isEmpty);
      expect((await billRowOf(db, keepBill))['balance_cents'], 100000,
          reason: '删除不该动到别人的账');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('无账单的人计数为 0，连带删除也能干净退出', () async {
      final (db, repo) = await open('cascade_empty');
      final cid = await repo.insertContact(name: '张三');
      final counts = await repo.contactRecordCounts(cid);
      expect(counts.bills, 0);
      expect(counts.transactions, 0);
      await repo.deleteContactWithRecords(cid);
      expect(await repo.contactCount(includeArchived: true), 0);
      await db.close();
    });
  });

  // ================================================================ 导入
  group('全量覆盖导入', () {
    test('导入前库内的旧数据全部消失，且派生列按库内求和为准', () async {
      final (db, repo) = await open('import_ok');
      final old = await repo.insertContact(name: '旧人');
      await newBill(repo, old, title: '旧账单');
      await repo.setContactArchived(old, true);

      final validated = validateSnapshot(consistentSnapshot(
        contacts: [contactRow(7, name: '新人')],
        bills: [billRow(70, 7, direction: directionIn)],
        transactions: [
          txRow(700, 70, amountCents: 500000, occurredDate: '2026-01-01'),
          txRow(701, 70,
              kind: kindPayment,
              amountCents: 200000,
              occurredDate: '2026-02-01'),
        ],
      ));
      expect(validated.ok, isTrue, reason: validated.errors.join('\n'));

      await repo.replaceAll(validated.data!);

      expect(await repo.allContacts(), hasLength(1));
      expect((await repo.allContacts()).single.name, '新人');
      expect((await repo.requireBill(70)).balanceCents, 300000);
      expect((await repo.totals()).receivableCents, 300000);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('导入保留原有 id，不重新编号', () async {
      final (db, repo) = await open('import_ids');
      await repo.replaceAll(validateSnapshot(consistentSnapshot(
        contacts: [contactRow(5, name: '甲'), contactRow(9, name: '乙')],
        bills: [billRow(20, 5), billRow(31, 9, direction: directionOut)],
        transactions: [
          txRow(500, 20, amountCents: 100000, occurredDate: '2026-01-01'),
          txRow(600, 31, amountCents: 200000, occurredDate: '2026-01-01'),
        ],
      )).data!);

      expect((await repo.allContacts()).map((c) => c.id), [5, 9]);
      expect((await repo.allBills()).map((b) => b.id), [20, 31]);
      expect((await repo.allTxs()).map((t) => t.id), [500, 600]);
      await db.close();
    });

    test('导入后新增记录不会复用已占用的 id', () async {
      final (db, repo) = await open('import_sequence');
      await repo.replaceAll(validateSnapshot(consistentSnapshot(
        contacts: [contactRow(10, name: '张三')],
        bills: const [],
        transactions: const [],
      )).data!);

      final newId = await repo.insertContact(name: '新人');
      expect(newId, greaterThan(10),
          reason: 'AUTOINCREMENT 必须跳过快照里占用的 id，否则覆盖旧记录');
      expect(await repo.requireContact(newId), isNotNull);
      await db.close();
    });

    test('文件里的派生列是错的，导入以库内重算结果纠正', () async {
      final (db, repo) = await open('import_stale');
      final snapshot = <String, Object?>{
        'schemaVersion': kSchemaVersion,
        'appVersion': '1.0.0',
        'exportedAt': '2026-09-05T22:00:00.000',
        'data': <String, Object?>{
          'contacts': [contactRow(1)],
          'bills': [
            billRow(10, 1, principalCents: 999, paymentCents: 999, balanceCents: 999)
          ],
          'transactions': [
            txRow(100, 10, amountCents: 800000, occurredDate: '2026-01-01'),
            txRow(101, 10,
                kind: kindPayment,
                amountCents: 300000,
                occurredDate: '2026-02-01'),
          ],
        },
      };
      final validated = validateSnapshot(snapshot);
      expect(validated.ok, isTrue, reason: validated.errors.join('\n'));
      expect(validated.data!.warnings, isNotEmpty,
          reason: '派生列对不上应当告警');

      await repo.replaceAll(validated.data!);
      final bill = await repo.requireBill(10);
      expect(bill.principalCents, 800000);
      expect(bill.paymentCents, 300000);
      expect(bill.balanceCents, 500000);
      await db.close();
    });

    test('绕过校验器的脏数据被拒绝，且失败后旧库完好无损', () async {
      final (db, repo) = await open('import_dangling');
      await repo.replaceAll(validateSnapshot(consistentSnapshot(
        contacts: [contactRow(1, name: '在册')],
      )).data!);
      expect(await repo.contactCount(), 1);

      // 外键是开的、删插顺序是先子表后父表，所以悬空引用在 INSERT 那一刻就被
      // SQLite 拒了；事务末尾的 PRAGMA foreign_key_check 是第二道网。
      await expectLater(repo.replaceAll(_danglingSnapshot()), throwsA(anything));

      expect((await repo.allContacts()).map((c) => c.name), ['在册'],
          reason: '失败必须整体回滚，不能留下清空后的空库');
      expect((await db.query(kTableBills)).single['contact_id'], 1,
          reason: '回滚后留下的必须还是原来那条账单，而不是脏数据的一部分');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('导入空快照等于清空全库', () async {
      final (db, repo) = await open('import_empty');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [(kindPrincipal, 100000, '2026-01-01')]);

      final empty = validateSnapshot(consistentSnapshot(
        contacts: const [],
        bills: const [],
        transactions: const [],
      ));
      expect(empty.ok, isTrue, reason: empty.errors.join('\n'));
      await repo.replaceAll(empty.data!);

      expect(await repo.contactCount(includeArchived: true), 0);
      expect(await repo.allBills(), isEmpty);
      expect(await repo.allTxs(), isEmpty);
      expect((await repo.totals()).isEmpty, isTrue);
      await db.close();
    });

    test('导出 → 导入 → 再导出，三份 dump 完全相同（往返无损）', () async {
      final (db, repo) = await open('roundtrip');
      final a = await repo.insertContact(name: '张三', phone: '138', note: '老同学');
      final b = await repo.insertContact(name: '李四');
      final billA = await newBill(repo, a, title: '装修');
      final billB = await newBill(repo, b,
          title: '买车', direction: directionOut);
      await seed(repo, billA, [
        (kindPrincipal, 1000000, '2026-01-01'),
        (kindPayment, 100000, '2026-02-01'),
        (kindPrincipal, 50000, '2026-03-01'),
      ]);
      await seed(repo, billB, [(kindPrincipal, 300000, '2026-04-01')]);

      Future<Map<String, List<Map<String, Object?>>>> dump() async => {
            for (final table in [
              kTableContacts,
              kTableBills,
              kTableTransactions
            ])
              table: await repo.dumpTable(table),
          };

      final first = await dump();
      final snapshot = buildSnapshot(
        contacts: first[kTableContacts]!,
        bills: first[kTableBills]!,
        transactions: first[kTableTransactions]!,
        appVersion: '1.0.0',
        exportedAt: '2026-09-05T22:00:00.000',
      );

      final validated = validateSnapshot(jsonDecodeSnapshot(snapshot));
      expect(validated.ok, isTrue, reason: validated.errors.join('\n'));
      await repo.replaceAll(validated.data!);
      final second = await dump();

      expect(second, first, reason: '导入自身导出必须逐格不变');

      await repo.replaceAll(
          validateSnapshot(jsonDecodeSnapshot(snapshot)).data!);
      expect(await dump(), first, reason: '再走一遍仍然不变，说明幂等');
      await db.close();
    });

    test('清空全库', () async {
      final (db, repo) = await open('clear');
      final cid = await repo.insertContact(name: '张三');
      final bid = await newBill(repo, cid);
      await seed(repo, bid, [(kindPrincipal, 100000, '2026-01-01')]);

      await repo.clearEverything();
      expect(await repo.contactCount(includeArchived: true), 0);
      expect(await repo.allBills(), isEmpty);
      expect(await repo.allTxs(), isEmpty);
      await db.close();
    });
  });
}

/// 手工拼一个 bills 引用不存在 contact 的快照，**绕开校验器**，
/// 直接验导入器自己的两道防线：外键约束与事务整体回滚。
SnapshotData _danglingSnapshot() => SnapshotData(
      schemaVersion: kSchemaVersion,
      contacts: [contactRow(1)],
      bills: [billRow(10, 2)],
      transactions: const [],
      warnings: const [],
    );

/// 快照先按缩进编码再解码，才能模拟「从文件读回来」的真实形状：
/// 数字变成 num、未知键被丢弃之前的形态。
Object? jsonDecodeSnapshot(Map<String, Object?> snapshot) =>
    jsonDecode(encodeSnapshot(snapshot));


