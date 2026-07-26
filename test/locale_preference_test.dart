import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';

void main() {
  test('localeFromPreference:system→null,zh/en→对应 Locale,未知值→null', () {
    expect(localeFromPreference(null), isNull);
    expect(localeFromPreference('system'), isNull);
    expect(localeFromPreference('zh'), const Locale('zh'));
    expect(localeFromPreference('en'), const Locale('en'));
    expect(localeFromPreference('klingon'), isNull);
  });
}
