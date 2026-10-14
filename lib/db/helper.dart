/// 建库、升级与外键开关。
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

const String kDatabaseName = 'debtbook.db';
const int kDatabaseVersion = 2;

const String kTableContacts = 'contacts';
const String kTableBills = 'bills';
const String kTableTransactions = 'transactions';

/// 打开台账数据库。
///
/// [directory] 由调用方给出（Android 上传 path_provider 的应用私有目录，
/// 测试上传临时目录），这样同一份代码能在 Dart VM 上跑真实 SQLite，
/// 不需要连手机就能验证全部读写逻辑。
Future<sqflite.Database> openLedgerDatabase(String directory) {
  return sqflite.openDatabase(
    p.join(directory, kDatabaseName),
    version: kDatabaseVersion,
    onConfigure: (db) async {
      // sqflite 默认不开外键，必须在这里显式打开，
      // 否则 ON DELETE RESTRICT 形同虚设，脏引用能静默写进去。
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, version) => _createSchema(db),
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        // v2：账单加「初始金额」列（建账时已存在但来不及记的借款本数）。
        // 新列追加在表尾，与 v2 建表语句里的位置一致，导出的列序才不会
        // 因为「全新库 / 升级库」而分叉。
        await db.execute(
            'ALTER TABLE $kTableBills ADD COLUMN initial_cents INTEGER NOT NULL DEFAULT 0');
      }
    },
  );
}

Future<void> _createSchema(sqflite.Database db) async {
  await db.execute('''
    CREATE TABLE $kTableContacts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT,
      -- 借款人备注这个功能已经砍了，但列留着：老库都有它，删列要迁移且
      -- 低版本 Android 的 SQLite 不支持 DROP COLUMN；留着还能保证
      -- 全新库和升级库导出回来的列形状一致。
      note TEXT,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE $kTableBills (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      contact_id INTEGER NOT NULL REFERENCES $kTableContacts(id) ON DELETE RESTRICT,
      title TEXT NOT NULL,
      direction TEXT NOT NULL CHECK (direction IN ('in','out')),
      note TEXT,
      principal_cents INTEGER NOT NULL DEFAULT 0,
      payment_cents INTEGER NOT NULL DEFAULT 0,
      balance_cents INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      initial_cents INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE $kTableTransactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bill_id INTEGER NOT NULL REFERENCES $kTableBills(id) ON DELETE RESTRICT,
      kind TEXT NOT NULL CHECK (kind IN ('principal','payment')),
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      occurred_date TEXT NOT NULL,
      channel TEXT,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('CREATE INDEX idx_bill_contact ON $kTableBills(contact_id)');
  await db.execute('CREATE INDEX idx_tx_bill ON $kTableTransactions(bill_id)');
  await db.execute(
      'CREATE INDEX idx_tx_date ON $kTableTransactions(occurred_date)');
}
