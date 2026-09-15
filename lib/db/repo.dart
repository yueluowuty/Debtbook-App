/// 台账数据访问层。
///
/// 唯一的写入不变量：**任何改动 transactions 的操作，都必须在同一个事务里
/// 调用 [recomputeBills]，并且把受影响的新旧 billId 全部传进去**。
/// 漏传旧 billId 是唯一会让账单余额算错的代码路径。
library;

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/validate.dart';
import 'helper.dart';

/// 面向用户的错误，message 直接进 SnackBar / 对话框，不做二次翻译。
class LedgerFailure implements Exception {
  const LedgerFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class LedgerTotals {
  const LedgerTotals({required this.receivableCents, required this.payableCents});

  final int receivableCents;
  final int payableCents;

  int get netCents => receivableCents - payableCents;
  bool get isEmpty => receivableCents == 0 && payableCents == 0;
}

/// 把账单的派生金额列按流水重算回写。
///
/// 三个列各自用独立子查询从 transactions 求和，其中 balance 直接用一个
/// CASE 求和得到，而不是引用同行的 principal/payment —— 同一条 UPDATE 里
/// 各 SET 子句读到的都是更新前的旧值，靠列相减会算错。
Future<void> recomputeBills(
  DatabaseExecutor db,
  Set<int> billIds, {
  String? stampedAt,
}) async {
  if (billIds.isEmpty) return;
  final placeholders = List.filled(billIds.length, '?').join(',');
  await db.rawUpdate('''
    UPDATE $kTableBills SET
      principal_cents = (
        SELECT COALESCE(SUM(amount_cents), 0) FROM $kTableTransactions
        WHERE bill_id = $kTableBills.id AND kind = 'principal'),
      payment_cents = (
        SELECT COALESCE(SUM(amount_cents), 0) FROM $kTableTransactions
        WHERE bill_id = $kTableBills.id AND kind = 'payment'),
      balance_cents = (
        SELECT COALESCE(SUM(
          CASE WHEN kind = 'principal' THEN amount_cents ELSE -amount_cents END), 0)
        FROM $kTableTransactions WHERE bill_id = $kTableBills.id),
      updated_at = COALESCE(?, updated_at)
    WHERE id IN ($placeholders)
  ''', [stampedAt, ...billIds]);
}

String _now() => DateTime.now().toIso8601String();

/// 可选文本字段统一归一：空白存 null，避免界面判空要同时防 '' 和 null。
String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

class LedgerRepo {
  LedgerRepo(this.db);

  final Database db;

  // --------------------------------------------------------------- 查询

  Future<LedgerTotals> totals() async {
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN direction = 'in'  THEN balance_cents ELSE 0 END), 0) AS receivable,
        COALESCE(SUM(CASE WHEN direction = 'out' THEN balance_cents ELSE 0 END), 0) AS payable
      FROM $kTableBills
    ''');
    final row = rows.first;
    return LedgerTotals(
      receivableCents: asIntOrNull(row['receivable']) ?? 0,
      payableCents: asIntOrNull(row['payable']) ?? 0,
    );
  }

  Future<int> contactCount({bool includeArchived = false}) async {
    final rows = await db
        .rawQuery('SELECT COUNT(*) AS n FROM $kTableContacts'
            '${includeArchived ? '' : ' WHERE archived = 0'}');
    return asIntOrNull(rows.first['n']) ?? 0;
  }

  /// 首页人员列表：一次带出应收/应付/账单数，再用一条分组查询补流水数与最近活动。
  Future<List<Contact>> listContacts({
    String? search,
    String? direction,
    bool includeArchived = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('c.archived = 0');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(c.name LIKE ? OR c.phone LIKE ?)');
      final like = '%${search.trim()}%';
      args.addAll([like, like]);
    }
    if (direction != null) {
      where.add('''
        EXISTS (SELECT 1 FROM $kTableBills ob
                WHERE ob.contact_id = c.id
                  AND ob.direction = ?
                  AND ob.balance_cents != 0)''');
      args.add(direction);
    }
    final clause = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.phone, c.note, c.archived, c.created_at,
             COALESCE(SUM(CASE WHEN b.direction = 'in'
                               THEN b.balance_cents ELSE 0 END), 0) AS receivable_cents,
             COALESCE(SUM(CASE WHEN b.direction = 'out'
                               THEN b.balance_cents ELSE 0 END), 0) AS payable_cents,
             COUNT(b.id) AS bill_count
      FROM $kTableContacts c
      LEFT JOIN $kTableBills b ON b.contact_id = c.id
      $clause
      GROUP BY c.id
      ORDER BY ABS(receivable_cents - payable_cents) DESC, c.name ASC
    ''', args);

    final activityRows = await db.rawQuery('''
      SELECT b.contact_id AS contact_id,
             COUNT(t.id) AS tx_count,
             MAX(t.occurred_date) AS last_activity
      FROM $kTableBills b
      JOIN $kTableTransactions t ON t.bill_id = b.id
      GROUP BY b.contact_id
    ''');
    final activity = <int, List<Object?>>{
      for (final r in activityRows)
        asIntOrNull(r['contact_id'])!: [r['tx_count'], r['last_activity']],
    };

    return [
      for (final r in rows)
        Contact.fromRow({
          ...r,
          'tx_count': activity[asIntOrNull(r['id'])]?.first,
          'last_activity': activity[asIntOrNull(r['id'])]?.last,
        }),
    ];
  }

  Future<Contact> requireContact(int id) async {
    final rows = await db.query(kTableContacts, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw const LedgerFailure('这个借款人已被删除');
    return Contact.fromRow(rows.first);
  }

  Future<List<Bill>> billsOfContact(int contactId) async {
    final rows = await db.rawQuery('''
      SELECT b.*,
             (SELECT COUNT(*) FROM $kTableTransactions t
               WHERE t.bill_id = b.id) AS tx_count,
             (SELECT MIN(t.occurred_date) FROM $kTableTransactions t
               WHERE t.bill_id = b.id) AS first_date,
             (SELECT MAX(t.occurred_date) FROM $kTableTransactions t
               WHERE t.bill_id = b.id) AS last_date
      FROM $kTableBills b
      WHERE b.contact_id = ?
      ORDER BY b.direction ASC, b.id ASC
    ''', [contactId]);
    return rows.map(Bill.fromRow).toList();
  }

  Future<Bill> requireBill(int id) async {
    final rows = await db.rawQuery('''
      SELECT b.*,
             (SELECT COUNT(*) FROM $kTableTransactions t
               WHERE t.bill_id = b.id) AS tx_count,
             (SELECT MIN(t.occurred_date) FROM $kTableTransactions t
               WHERE t.bill_id = b.id) AS first_date,
             (SELECT MAX(t.occurred_date) FROM $kTableTransactions t
               WHERE t.bill_id = b.id) AS last_date
      FROM $kTableBills b WHERE b.id = ?
    ''', [id]);
    if (rows.isEmpty) throw const LedgerFailure('这个账单已被删除');
    return Bill.fromRow(rows.first);
  }

  Future<List<Tx>> txsOfBill(int billId) async {
    final rows = await db.query(kTableTransactions,
        where: 'bill_id = ?',
        whereArgs: [billId],
        orderBy: 'occurred_date DESC, id DESC',
        limit: 3000);
    return rows.map(Tx.fromRow).toList(growable: false);
  }

  Future<List<Tx>> txsOfContact(int contactId) async {
    final rows = await db.rawQuery('''
      SELECT t.* FROM $kTableTransactions t
      JOIN $kTableBills b ON b.id = t.bill_id
      WHERE b.contact_id = ?
      ORDER BY t.occurred_date DESC, t.id DESC
      LIMIT 3000
    ''', [contactId]);
    return rows.map(Tx.fromRow).toList();
  }

  Future<List<Tx>> allTxs() async {
    final rows = await db.query(kTableTransactions,
        orderBy: 'occurred_date ASC, id ASC', limit: 20000);
    return rows.map(Tx.fromRow).toList();
  }

  Future<List<Contact>> allContacts() async {
    final rows =
        await db.query(kTableContacts, orderBy: 'id ASC', limit: 20000);
    return rows.map(Contact.fromRow).toList();
  }

  Future<List<Bill>> allBills() async {
    final rows = await db.query(kTableBills, orderBy: 'id ASC', limit: 20000);
    return rows.map(Bill.fromRow).toList();
  }

  /// 导出用的原始行，列名与库内完全一致，保证导入导出往返无损。
  Future<List<Map<String, Object?>>> dumpTable(String table) =>
      db.query(table, orderBy: 'id ASC');

  // --------------------------------------------------------------- 借款人

  Future<int> insertContact({
    required String name,
    String? phone,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const LedgerFailure('姓名不能为空');
    return db.insert(kTableContacts, {
      'name': trimmed,
      'phone': _clean(phone),
      'note': _clean(note),
      'archived': 0,
      'created_at': _now(),
    });
  }

  Future<void> updateContact({
    required int id,
    required String name,
    String? phone,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const LedgerFailure('姓名不能为空');
    await db.update(kTableContacts, {
      'name': trimmed,
      'phone': _clean(phone),
      'note': _clean(note),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setContactArchived(int id, bool archived) =>
      db.update(kTableContacts, {'archived': archived ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);

  /// 仅在没有账单时允许直接删除，否则提示改用归档或连带删除。
  Future<void> deleteContact(int id) async {
    final bills = await db.query(kTableBills,
        columns: ['id'],
        where: 'contact_id = ?',
        whereArgs: [id],
        limit: 1);
    if (bills.isNotEmpty) {
      throw const LedgerFailure('这个借款人名下还有账单，无法直接删除。'
          '可以选择「归档」，或连带删除其全部账单与流水。');
    }
    await db.delete(kTableContacts, where: 'id = ?', whereArgs: [id]);
  }

  Future<({int bills, int transactions})> contactRecordCounts(int id) async {
    final billIds = (await db.query(kTableBills,
                columns: ['id'], where: 'contact_id = ?', whereArgs: [id]))
            .map((r) => asIntOrNull(r['id'])!)
            .toList(growable: false);
    if (billIds.isEmpty) return (bills: 0, transactions: 0);
    final ph = List.filled(billIds.length, '?').join(',');
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $kTableTransactions WHERE bill_id IN ($ph)',
        billIds);
    return (bills: billIds.length, transactions: asIntOrNull(rows.first['n']) ?? 0);
  }

  /// 连带删除。顺序保证外键不被触发：先子表，再账单，最后人。
  Future<void> deleteContactWithRecords(int id) =>
      db.transaction((txn) => _deleteContactWithRecords(txn, id));

  Future<void> _deleteContactWithRecords(DatabaseExecutor txn, int id) async {
    final billIds = (await txn.query(kTableBills,
            columns: ['id'], where: 'contact_id = ?', whereArgs: [id]))
        .map((r) => asIntOrNull(r['id'])!)
        .toList(growable: false);
    if (billIds.isNotEmpty) {
      final ph = List.filled(billIds.length, '?').join(',');
      await txn.rawDelete('DELETE FROM $kTableTransactions WHERE bill_id IN ($ph)',
          billIds);
      await txn.rawDelete('DELETE FROM $kTableBills WHERE id IN ($ph)', billIds);
    }
    await txn.delete(kTableContacts, where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------------- 账单

  Future<int> insertBill({
    required int contactId,
    required String title,
    required String direction,
    String? note,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw const LedgerFailure('账单名称不能为空');
    if (!isDirection(direction)) {
      throw const LedgerFailure("方向非法，只能是「别人欠我」或「我欠别人」");
    }
    final now = _now();
    return db.insert(kTableBills, {
      'contact_id': contactId,
      'title': trimmed,
      'direction': direction,
      'note': _clean(note),
      'principal_cents': 0,
      'payment_cents': 0,
      'balance_cents': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateBill({
    required int id,
    required String title,
    String? note,
    String? direction,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw const LedgerFailure('账单名称不能为空');
    final values = <String, Object?>{
      'title': trimmed,
      'note': _clean(note),
      'updated_at': _now(),
    };
    if (direction != null) {
      if (!isDirection(direction)) {
        throw const LedgerFailure("方向非法，只能是「别人欠我」或「我欠别人」");
      }
      values['direction'] = direction;
    }
    await db.update(kTableBills, values, where: 'id = ?', whereArgs: [id]);
  }

  /// 改方向只在账单还没有流水时开放：已有流水时 kind 的含义会整体反转，
  /// 等于静默把账算反。
  Future<void> changeBillDirection(int id, String direction) async {
    if (!isDirection(direction)) {
      throw const LedgerFailure("方向非法，只能是「别人欠我」或「我欠别人」");
    }
    final bill = await requireBill(id);
    if (bill.hasTransactions) {
      throw const LedgerFailure('这个账单下已有流水记录，改方向会让借款与还款的含义整体反转。'
          '请先删除或转移流水，或直接新建一个正确方向的账单。');
    }
    await db.update(kTableBills,
        {'direction': direction, 'updated_at': _now()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBill(int id) async {
    final bill = await requireBill(id);
    if (bill.hasTransactions) {
      throw LedgerFailure('这个账单下还有 ${bill.txCount} 笔流水，'
          '请先逐笔删除流水，再删除账单。');
    }
    await db.delete(kTableBills, where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------------- 流水

  Future<int> insertTx({
    required int billId,
    required String kind,
    required int amountCents,
    required String occurredDate,
    String? channel,
    String? note,
  }) async {
    if (!isKind(kind)) throw const LedgerFailure('类型非法');
    if (amountCents <= 0) throw const LedgerFailure('金额必须大于 0');
    if (!isValidDateIso(occurredDate)) {
      throw const LedgerFailure('日期格式非法');
    }
    final now = _now();
    return db.transaction((txn) async {
      final id = await txn.insert(kTableTransactions, {
        'bill_id': billId,
        'kind': kind,
        'amount_cents': amountCents,
        'occurred_date': occurredDate,
        'channel': _clean(channel),
        'note': _clean(note),
        'created_at': now,
        'updated_at': now,
      });
      await recomputeBills(txn, {billId}, stampedAt: now);
      return id;
    });
  }

  /// [billId] 传 null 表示不挪动。跨账单挪流水时新旧两个账单都要重算。
  Future<void> updateTx({
    required int id,
    String? kind,
    int? amountCents,
    String? occurredDate,
    String? channel,
    String? note,
    int? billId,
  }) async {
    if (kind != null && !isKind(kind)) throw const LedgerFailure('类型非法');
    if (amountCents != null && amountCents <= 0) {
      throw const LedgerFailure('金额必须大于 0');
    }
    if (occurredDate != null && !isValidDateIso(occurredDate)) {
      throw const LedgerFailure('日期格式非法');
    }

    await db.transaction((txn) async {
      final rows = await txn.query(kTableTransactions,
          columns: ['bill_id'], where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const LedgerFailure('这笔流水已被删除');
      final oldBillId = asIntOrNull(rows.first['bill_id'])!;
      final now = _now();

      final values = <String, Object?>{'updated_at': now};
      if (kind != null) values['kind'] = kind;
      if (amountCents != null) values['amount_cents'] = amountCents;
      if (occurredDate != null) values['occurred_date'] = occurredDate;
      if (channel != null) {
        values['channel'] = channel.trim().isEmpty ? null : channel.trim();
      }
      if (note != null) values['note'] = note.trim().isEmpty ? null : note.trim();

      final affected = <int>{oldBillId};
      if (billId != null) {
        values['bill_id'] = billId;
        affected.add(billId);
      }

      await txn.update(kTableTransactions, values,
          where: 'id = ?', whereArgs: [id]);
      await recomputeBills(txn, affected, stampedAt: now);
    });
  }

  Future<void> deleteTx(int id) => db.transaction((txn) async {
        final rows = await txn.query(kTableTransactions,
            columns: ['bill_id'], where: 'id = ?', whereArgs: [id]);
        if (rows.isEmpty) return;
        final billId = asIntOrNull(rows.first['bill_id'])!;
        await txn.delete(kTableTransactions, where: 'id = ?', whereArgs: [id]);
        await recomputeBills(txn, {billId}, stampedAt: _now());
      });

  // ------------------------------------------------------------- 全量恢复

  /// 导入 = 全量覆盖。删插顺序天然满足外键，因此不需要（也不能）在事务里
  /// 切换 PRAGMA foreign_keys —— SQLite 会忽略事务内的该开关。
  Future<void> replaceAll(SnapshotData snapshot) async {
    await db.transaction((txn) async {
      await txn.delete(kTableTransactions);
      await txn.delete(kTableBills);
      await txn.delete(kTableContacts);

      for (final row in snapshot.contacts) {
        await txn.insert(kTableContacts, row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in snapshot.bills) {
        await txn.insert(kTableBills, row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in snapshot.transactions) {
        await txn.insert(kTableTransactions, row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // 校验器已按流水重算过派生列，这里以库内实际求和为最终权威再算一遍。
      final importedBillIds = <int>{};
      for (final row in snapshot.bills) {
        final id = asIntOrNull(row['id']);
        if (id != null && id > 0) importedBillIds.add(id);
      }
      // 不传 stampedAt：导入是恢复，不是编辑。盖成导入时刻会让「导出→导入→
      // 再导出」无法逐字节相同，也等于用一次备份恢复篡改了用户的修改时间。
      await recomputeBills(txn, importedBillIds);

      final broken = await txn.rawQuery('PRAGMA foreign_key_check');
      if (broken.isNotEmpty) {
        throw LedgerFailure('导入后存在 ${broken.length} 条悬空引用，已整体回滚');
      }
    });
  }
}
