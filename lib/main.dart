import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'db/helper.dart';
import 'db/repo.dart';
import 'state/store.dart';
import 'ui/home/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DebtBookApp());
}

class DebtBookApp extends StatefulWidget {
  const DebtBookApp({super.key});

  @override
  State<DebtBookApp> createState() => _DebtBookAppState();
}

class _DebtBookAppState extends State<DebtBookApp> {
  LedgerStore? _store;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final db = await openLedgerDatabase(dir.path);
      final store = LedgerStore(LedgerRepo(db), dir.path);
      await store.reload();
      if (!mounted) return;
      setState(() => _store = store);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fatalError = '数据库打不开：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildDebtBookTheme();

    final failure = _fatalError;
    if (failure != null) {
      return MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(failure, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }

    final store = _store;
    if (store == null) {
      return MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return StoreScope(
      store: store,
      child: MaterialApp(
        title: '欠款台账',
        debugShowCheckedModeBanner: false,
        theme: theme,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        locale: const Locale('zh', 'CN'),
        home: const HomePage(),
      ),
    );
  }
}
