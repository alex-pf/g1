/// Виджет-тесты экранов раундов (US-01, issue #4; US-02, issue #5):
/// smoke, жест отбивания, мультитач двумя пальцами, поражение после
/// 5 попаданий с рестартом, победа по таймеру.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:g1/game/health/planet_health.dart';
import 'package:g1/game/pacing/round_pacing.dart';
import 'package:g1/game/round1/round_one_controller.dart';
import 'package:g1/game/round2/round_two_controller.dart';
import 'package:g1/main.dart';
import 'package:g1/ui/earth_view.dart';
import 'package:g1/ui/game_screen.dart';
import 'package:g1/ui/lives_indicator.dart';
import 'package:g1/ui/round_two_layer.dart';
import 'package:g1/ui/round_two_screen.dart';

/// Экран «планшет» 800×600 (field: высота 1.0 = 600 px).
Future<RoundOneController> pumpGame(
  WidgetTester tester, {
  PlanetHealth? health,
  RoundPacing? pacing,
  int seed = 3,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = RoundOneController(
    health: health ?? PlanetHealth(),
    pacing: pacing,
    rng: math.Random(seed),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(health: controller.health, controller: controller),
    ),
  );
  return controller;
}

/// Ставит астероид на гарантированный курс в Землю с близкой дистанции.
void aimAtEarth(RoundOneController controller) {
  final sim = controller.sim;
  sim.position = Offset(sim.earthCenter.dx - 0.3, sim.earthCenter.dy);
  sim.velocity = Offset(sim.targetSpeed, 0);
}

/// Пампит кадры, пока не выполнится условие (или выйдет лимит).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxFrames = 100,
}) async {
  for (var i = 0; i < maxFrames && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('smoke: Земля, звёзды, таймер и астероиды раунда 2 на экране',
      (tester) async {
    await tester.pumpWidget(const G1App());

    expect(find.byType(RoundTwoScreen), findsOneWidget);
    expect(find.byType(LivesIndicator), findsOneWidget);
    expect(find.byType(EarthView), findsOneWidget);
    expect(find.byType(RoundTwoLayer), findsOneWidget);
    for (var i = 0; i < PlanetHealth.maxStars; i++) {
      expect(find.byKey(Key('lives-star-$i')), findsOneWidget);
    }
    // Таймер раунда 2 — 50 секунд (конфигурация issue #16).
    expect(find.byKey(const Key('round-timer')), findsOneWidget);
    expect(find.text('0:50'), findsOneWidget);
  });

  testWidgets('мультитач: два пальца отбивают два астероида (US-02, критерий 1)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = RoundTwoController(
      health: PlanetHealth(),
      rng: math.Random(5),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RoundTwoScreen(health: controller.health, controller: controller),
      ),
    );

    // Два астероида в известных точках поля: (0.3, 0.5) → (180, 300) px,
    // (1.1, 0.5) → (660, 300) px (высота поля 1.0 = 600 px).
    final first = controller.asteroids[0].sim;
    final second = controller.asteroids[1].sim;
    first.position = const Offset(0.3, 0.5);
    first.velocity = Offset(first.targetSpeed, 0);
    second.position = const Offset(1.1, 0.5);
    second.velocity = Offset(second.targetSpeed, 0);

    // Два одновременных касания: палец 1 свайпает вверх, палец 2 — вниз.
    final finger1 = await tester.startGesture(const Offset(180, 300), pointer: 1);
    final finger2 = await tester.startGesture(const Offset(660, 300), pointer: 2);
    await finger1.moveBy(const Offset(0, -80));
    await finger2.moveBy(const Offset(0, 80));
    await tester.pump();

    expect(controller.deflections, 2);
    expect(first.velocity.dy, lessThan(0)); // первый полетел вверх
    expect(second.velocity.dy, greaterThan(0)); // второй — вниз

    await finger1.up();
    await finger2.up();
  });

  testWidgets('экран раунда 1: свайп по астероиду меняет его направление '
      '(критерий 2)', (tester) async {
    final controller = await pumpGame(tester);
    final sim = controller.sim;
    // Известная позиция: x=0.3, y=0.5 поля → (180, 300) px.
    sim.position = const Offset(0.3, 0.5);
    sim.velocity = Offset(sim.targetSpeed, 0);
    final before = sim.velocity;

    await tester.timedDragFrom(
      const Offset(180, 300),
      const Offset(0, -120),
      const Duration(milliseconds: 200),
    );

    expect(controller.deflections, 1);
    expect(sim.velocity.dy, lessThan(0)); // полетел вверх за пальцем
    // Курс — почти вертикально вверх (гравитация за кадры драга
    // слегка догибает вектор, поэтому не строгий ноль по dx).
    expect(sim.velocity.dx.abs(),
        lessThan(sim.velocity.distance * 0.25));
    expect(sim.velocity.distance, closeTo(before.distance, 1e-3));
  });

  testWidgets('5 попаданий → осколки и оверлей поражения, рестарт (критерий 3)',
      (tester) async {
    final controller = await pumpGame(tester);
    final health = controller.health;

    for (var hit = 0; hit < 5; hit++) {
      aimAtEarth(controller);
      await pumpUntil(tester, () => controller.impacts == hit + 1);
    }

    expect(health.quarters, 0);
    expect(controller.state, RoundState.defeat);
    expect(health.stage, EarthStage.debris);
    expect(find.byKey(const Key('round-defeat-overlay')), findsOneWidget);
    expect(find.text('Поражение'), findsOneWidget);

    // Рестарт: шкала и таймер сброшены, раунд идёт заново.
    await tester.tap(find.byKey(const Key('round-restart-button')));
    // Даём отработать отложенным эффектам индикатора жизней
    // (лечебная вспышка планируется с задержкой 250 мс).
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.state, RoundState.playing);
    expect(health.quarters, PlanetHealth.maxQuarters);
    expect(find.byKey(const Key('round-defeat-overlay')), findsNothing);
    expect(find.text('0:45'), findsOneWidget);
  });

  testWidgets('истёкший таймер с живой планетой → оверлей победы',
      (tester) async {
    const pacing = RoundPacing(
      roundNumber: 1,
      name: 'Базовая защита',
      durationSec: 2,
      initialThreats: {},
      maxObjectsOnScreen: 1,
      speedGrowth: LinearSpeedGrowth(toPercent: 0, durationSec: 2),
    );
    final controller = await pumpGame(tester, pacing: pacing);

    // Держим астероид на безопасной дистанции до конца таймера.
    var guard = 0;
    while (controller.state == RoundState.playing && guard++ < 60) {
      final sim = controller.sim;
      sim.position = const Offset(0.1, 0.1);
      sim.velocity = Offset(sim.targetSpeed, 0);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(controller.state, RoundState.victory);
    expect(find.byKey(const Key('round-victory-overlay')), findsOneWidget);
    expect(find.text('Раунд пройден!'), findsOneWidget);
    expect(controller.health.quarters, PlanetHealth.maxQuarters);
  });
}
