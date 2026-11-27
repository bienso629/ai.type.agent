import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tadu_cloud_ai_agent_mobile/screens/aitype_admin/aitype_admin_screen.dart';

void main() {
  testWidgets('AiTypeAdminScreen renders email and password login form', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const AiTypeAdminScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin_api_url_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_email_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_password_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_login_submit_button')), findsOneWidget);

    expect(find.byKey(const ValueKey('admin_token_input')), findsNothing);
    expect(find.text('Secret / Token'), findsNothing);
  });
}
