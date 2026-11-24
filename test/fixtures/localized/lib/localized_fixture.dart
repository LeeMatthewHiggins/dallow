import 'l10n/app_strings.dart';
import 'l10n/app_strings_helpers.dart';

String greet() => '${lookupStrings().hello} ${shout('x')}';
