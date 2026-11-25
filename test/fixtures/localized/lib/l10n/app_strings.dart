import 'app_strings_en.dart';

abstract class AppStrings {
  String get hello;
}

AppStrings lookupStrings() => AppStringsEn();

/// Dead, but in gen-l10n output → not reported.
int _unusedInGenerated() => 0;
