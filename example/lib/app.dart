import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/home/feed_credit_balance.dart';
import 'features/home/home_page.dart';
import 'localization/xlab_localization.dart';
import 'ui/xlab_theme.dart';

class XLabApp extends StatefulWidget {
  const XLabApp({this.creditBalanceQueryFactory, super.key});

  final FeedCreditBalanceQueryFactory? creditBalanceQueryFactory;

  @override
  State<XLabApp> createState() => _XLabAppState();
}

class _XLabAppState extends State<XLabApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(XLabLocalization.shared.load());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    XLabLocalization.shared.systemLocaleDidChange();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: XLabLocalization.shared,
      builder: (context, _) => MaterialApp(
        locale: XLabLocalization.shared.locale,
        supportedLocales: const <Locale>[Locale('en'), Locale('zh')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        title: 'XLab',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: XLabPalette.mint,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: XLabPalette.background,
          cardTheme: const CardThemeData(
            color: XLabPalette.surface,
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          useMaterial3: true,
        ),
        home: HomePage(
          creditBalanceQueryFactory: widget.creditBalanceQueryFactory,
        ),
      ),
    );
  }
}
