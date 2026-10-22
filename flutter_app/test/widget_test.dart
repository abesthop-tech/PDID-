import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:daily_concierge/main.dart';
import 'package:daily_concierge/services/api_service.dart';

void main() {
  testWidgets('DailyConciergeApp renders navigation shell and Today screen', (WidgetTester tester) async {
    final state = ConciergeState();

    await tester.pumpWidget(
      ChangeNotifierProvider<ConciergeState>.value(
        value: state,
        child: const DailyConciergeApp(),
      ),
    );

    expect(find.text('Daily Concierge'), findsOneWidget);
    expect(find.textContaining('やるメモ.md'), findsWidgets);
  });
}
