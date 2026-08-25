import 'package:flutter_test/flutter_test.dart';
import 'package:tadu_cloud_ai_agent_mobile/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TaduCloudAiAgentApp());
    expect(find.byType(TaduCloudAiAgentApp), findsOneWidget);
  });
}
