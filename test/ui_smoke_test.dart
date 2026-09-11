/// UI 冒烟测试。没有设备也没有模拟器，这几条是界面层唯一的验证手段。
///
/// 能测的边界（踩过坑，写下来免得再试一遍）：
/// 1. testWidgets 跑在 FakeAsync 里，而 sqflite_common_ffi 的真实 IO 走 isolate，
///    在 fake zone 内 await 永不 complete。所以建库/读写都要包在 runAsync 里。
/// 2. 页面 initState 里发起的加载是在 fake zone 创建的，之后进 runAsync 也救不回来。
///    因此 **PersonPage / BillPage 的加载后界面在这里测不了**，只能靠装 APK 人工确认；
///    它们的算账正确性由 test/repo_test.dart 在真实 SQLite 上覆盖。
/// 3. CircularProgressIndicator 是无限动画，pumpAndSettle 等不到静止，只会超时。
library;

import 'dart:io';

import 'package:debtbook/db/helper.dart';
import 'package:debtbook/db/repo.dart';
import 'package:debtbook/domain/models.dart';
import 'package:debtbook/state/store.dart';
import 'package:debtbook/ui/home/home_page.dart';
import 'package:debtbook/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() {
  late Directory tempRoot;
  late LedgerStore store;
  final opened = <Database>[];
  final tempDirs = <Directory>[];
  var dbIndex = 0;

  ffi.sqfliteFfiInit();

  setUp(() async {
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    tempRoot = Directory.systemTemp.createTempSync('debtbook_ui');
    tempDirs.add(tempRoot);
    // 走真实建库代码，不在测试里手抄 schema —— 否则 schema 改了测试还能全绿。
    final db = await openLedgerDatabase(
        '${tempRoot.path}${Platform.pathSeparator}db${dbIndex++}');
    opened.add(db);
    store = LedgerStore(LedgerRepo(db), tempRoot.path);
    await store.reload();
  });

  tearDown(() {
    // 这里绝不关库：可能还有在途查询，关了就变成 "database has already been
    // closed" 并把后面的用例一起拖坏。
    _tryDelete(tempRoot);
  });

  tearDownAll(() async {
    for (final db in opened) {
      try {
        await db.close();
      } on Exception {
        // 已关闭的再次 close 是良性的。
      }
    }
    opened.clear();
    for (final d in tempDirs) {
      _tryDelete(d);
    }
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(
        // 用交付时那份主题：界面测试跑默认主题的话，主题里的语义色、
        // 字号层级、以及 LedgerPalette 这个 ThemeExtension 都不在覆盖范围内。
        theme: buildDebtBookTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: page,
      ),
    ));
    // 不用 pumpAndSettle：只要界面上还有一个无限旋转的进度条就永远等不到静止。
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// 在真实 async zone 里做界面交互与数据库读写。
  Future<void> act(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
  }

  testWidgets('空账本给出下一步动作，而不是一片空白', (tester) async {
    await pump(tester, const HomePage());
    expect(find.textContaining('还没有任何记录'), findsOneWidget);
    expect(find.text('添加第一个借款人'), findsOneWidget);
  });

  testWidgets('顶部三块统计卡渲染出来，不溢出也不塌陷', (tester) async {
    await pump(tester, const HomePage());
    expect(find.text('别人欠我'), findsOneWidget);
    expect(find.text('我欠别人'), findsOneWidget);
    expect(find.text('净差'), findsOneWidget);
    // 溢出这类问题在这里以异常形式浮出，之前 stretch Row 就把整棵树打崩过。
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计卡金额再长也只是缩小，不许出现省略号', (tester) async {
    // 三块卡各占屏宽三分之一。模拟器实跑时 ¥1,500.00 就被截成了「¥1,500....」，
    // 而上面那条用例是空账本 ¥0.00，永远碰不到这个宽度，所以必须造真实大额。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await act(tester, () async {
      final cid = await store.repo.insertContact(name: '大额');
      final bid = await store.repo
          .insertBill(contactId: cid, title: 't', direction: directionIn);
      await store.repo.insertTx(
        billId: bid,
        kind: kindPrincipal,
        amountCents: 12345678,
        occurredDate: '2026-09-01',
      );
      await store.reload();
    });
    await pump(tester, const HomePage());

    // 大额先被压成「12.35万」，压完也仍然不许再被省略号截断。
    // 同一个数会同时出现在「别人欠我」和「净差」两块卡上，两块都得查。
    // didExceedMaxLines 就是「这段文字被截断/加省略号了吗」。
    final paragraphs =
        tester.renderObjectList<RenderParagraph>(find.text('¥12.35万'));
    expect(paragraphs, hasLength(2));
    for (final paragraph in paragraphs) {
      expect(paragraph.didExceedMaxLines, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统字号放大时统计条与列表行都不溢出', (tester) async {
    // 用户真机上满屏红色 BOTTOM OVERFLOWED 条幅，三块卡各溢出 3~4px：
    // 根因是统计条写死 92 高。模拟器字号偏小，所以之前所有用例都测不到这件事。
    // 这条**必须带数据**跑：空账本时 ListView 一行都没有，列表行那个
    // 「trailing 被 ListTile 恒定卡在 56 逻辑像素」的溢出就测不出来（真机上正是它）。
    await act(tester, () async {
      final cid = await store.repo.insertContact(
        name: '大字号借款人',
        phone: '13800000000',
      );
      final bid = await store.repo.insertBill(
          contactId: cid, title: '装修借款', direction: directionIn);
      await store.repo.insertTx(
          billId: bid,
          kind: kindPrincipal,
          amountCents: 12345678,
          occurredDate: '2026-09-01');
      await store.reload();
    });

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pump(tester, const HomePage());
    expect(find.text('大字号借款人'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('姓名留空时不允许提交', (tester) async {
    await pump(tester, const HomePage());
    await tester.tap(find.text('添加第一个借款人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.text('姓名不能为空'), findsOneWidget);
  });

  testWidgets('点添加借款人 → 填姓名 → 保存，首页能看到这个人', (tester) async {
    await pump(tester, const HomePage());
    await tester.tap(find.text('添加第一个借款人'));
    await tester.pumpAndSettle();

    await act(tester, () async {
      await tester.enterText(find.widgetWithText(TextFormField, '姓名'), '张三');
      await tester.tap(find.text('添加'));
      // 不赌固定延时：轮询到界面真的反映出新记录为止，最多 5 秒。
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (store.contacts.any((c) => c.name == '张三')) break;
      }
    });

    expect(store.contacts.map((c) => c.name), contains('张三'));
    // 面板退场动画期间输入框里还留着一份「张三」，所以只要求出现，不要求唯一。
    expect(find.text('张三'), findsWidgets);
  });

  testWidgets('首页金额：满 1 万转「万」，不足则保留精确千分位', (tester) async {
    await act(tester, () async {
      final repo = store.repo;
      final contactId = await repo.insertContact(name: '李四');
      final receivable = await repo.insertBill(
          contactId: contactId, title: '装修借款', direction: directionIn);
      await repo.insertTx(
          billId: receivable,
          kind: kindPrincipal,
          amountCents: 1234500,
          occurredDate: '2026-08-01');
      // 反向也记一笔，验证应收/应付不会互相污染
      final payable = await repo.insertBill(
          contactId: contactId, title: '我借的', direction: directionOut);
      await repo.insertTx(
          billId: payable,
          kind: kindPrincipal,
          amountCents: 20000,
          occurredDate: '2026-08-02');
      await store.reload();
    });

    await pump(tester, const HomePage());
    // 大号金额满 1 万就转单位：应收 1,234.50 元、净差 1,214.50 元。
    expect(find.text('¥1.23万'), findsWidgets);
    expect(find.text('¥1.21万'), findsWidgets);
    // 应付只有 200 元，不足 1 万，必须仍然是精确千分位。
    expect(find.text('¥200.00'), findsWidgets);
    expect(tester.takeException(), isNull);

    expect(store.totals.receivableCents, 1234500);
    expect(store.totals.payableCents, 20000);
    expect(store.totals.netCents, 1214500);
  });

  testWidgets('按方向筛选只留下该方向上还有余额的人', (tester) async {
    await act(tester, () async {
      final repo = store.repo;
      final owes = await repo.insertContact(name: '欠我钱的');
      await repo.insertBill(
          contactId: owes, title: '借款', direction: directionIn);
      await repo.insertTx(
          billId: (await repo.billsOfContact(owes)).single.id,
          kind: kindPrincipal,
          amountCents: 100,
          occurredDate: '2026-08-01');
      final clean = await repo.insertContact(name: '已结清的');
      final billId = await repo.insertBill(
          contactId: clean, title: '已结清', direction: directionIn);
      await repo.insertTx(
          billId: billId,
          kind: kindPrincipal,
          amountCents: 100,
          occurredDate: '2026-08-01');
      await repo.insertTx(
          billId: billId,
          kind: kindPayment,
          amountCents: 100,
          occurredDate: '2026-08-05');
      await store.reload();
    });

    expect(store.contacts.length, 2);
    await pump(tester, const HomePage());
    await tester.tap(find.text('我欠别人'));
    await act(tester, () async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (store.contacts.length == 1) break;
      }
    });

    expect(store.filter, HomeFilter.payable);
    expect(store.contacts, isEmpty);
  });
}

void _tryDelete(Directory d) {
  if (!d.existsSync()) return;
  try {
    d.deleteSync(recursive: true);
  } on FileSystemException {
    // Windows 上被占用就留给系统回收 temp。
  }
}
