// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:layrz_push/layrz_push.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getSubscriptions test', (WidgetTester tester) async {
    final LayrzPush plugin = LayrzPush();
    // Fresh install, no subscriptions yet — just assert the native side answers.
    final List<String> subscriptions = await plugin.getSubscriptions();
    expect(subscriptions, isA<List<String>>());
  });
}
