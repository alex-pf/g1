import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:g1/game/health/planet_health.dart';
import 'package:g1/main.dart';
import 'package:g1/ui/earth_view.dart';
import 'package:g1/ui/game_screen.dart';
import 'package:g1/ui/lives_indicator.dart';

void main() {
  testWidgets('G1 smoke test: экран игры с индикатором и Землёй',
      (WidgetTester tester) async {
    await tester.pumpWidget(const G1App());

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(LivesIndicator), findsOneWidget);
    expect(find.byType(EarthView), findsOneWidget);
    for (var i = 0; i < PlanetHealth.maxStars; i++) {
      expect(find.byKey(Key('lives-star-$i')), findsOneWidget);
    }
  });

  testWidgets('отладочные кнопки применяют урон и лечение',
      (WidgetTester tester) async {
    final health = PlanetHealth();
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(health: health)),
    );

    await tester.tap(find.byKey(const Key('debug-fragment')));
    await tester.pump();
    expect(health.quarters, 19);
    expect(health.events.single.kind.name, 'fragment');

    await tester.tap(find.byKey(const Key('debug-capsule')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(health.quarters, 20);
  });

  testWidgets('критическое состояние и поражение не ломают рендер',
      (WidgetTester tester) async {
    final health = PlanetHealth(initialQuarters: 5);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(health: health)),
    );

    await tester.tap(find.byKey(const Key('debug-fragment')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(health.isCritical, isTrue);

    await tester.tap(find.byKey(const Key('debug-bolid')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(health.isDestroyed, isTrue);
    expect(health.stage, EarthStage.debris);

    // Дожидаемся завершения отложенных эффектов и таймеров оверлея.
    await tester.pump(const Duration(milliseconds: 1200));
  });
}
