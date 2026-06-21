import 'package:flutter_test/flutter_test.dart';
import 'package:spectrum_ui/main.dart';

void main() {
  testWidgets('App builds without crashing', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Press Start to begin'), findsOneWidget);
  });
}
