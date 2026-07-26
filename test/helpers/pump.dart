import 'package:flutter/material.dart';
import 'package:openmusic/l10n/app_localizations.dart';

/// 测试用的本地化外壳:默认中文,让既有的中文断言继续有效;
/// 传 Locale('en') 可验证英文界面。
Widget localizedApp(Widget home, {Locale locale = const Locale('zh')}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: home,
    );
