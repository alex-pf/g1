import 'package:flutter_test/flutter_test.dart';

import 'package:g1/main.dart';

void main() {
  testWidgets('G1 hello world smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const G1App());

    // Заголовок приложения и приветствие на месте, дефолтного счётчика нет.
    expect(find.text('G1'), findsOneWidget);
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
