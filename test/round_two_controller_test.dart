import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/health/planet_health.dart';
import 'package:g1/game/pacing/round_pacing.dart';
import 'package:g1/game/pacing/threat_type.dart';
import 'package:g1/game/round2/round_two_controller.dart';

RoundTwoController makeController({
  PlanetHealth? health,
  RoundPacing? pacing,
  int seed = 11,
}) {
  final controller = RoundTwoController(
    health: health ?? PlanetHealth(),
    pacing: pacing,
    rng: math.Random(seed),
  );
  controller.attachField(aspect: 1.6, earthRadius: 0.25);
  return controller;
}

/// Безопасные точки поля (далеко от Земли и друг от друга).
const safeSpots = <Offset>[
  Offset(0.15, 0.15),
  Offset(1.45, 0.15),
  Offset(0.15, 0.85),
  Offset(1.45, 0.85),
];

/// Расставляет астероидов по безопасным точкам с курсом от Земли,
/// чтобы за время прогона никто не упал и ни с кем не столкнулся.
void keepSafe(RoundTwoController controller, {TrackedAsteroid? except}) {
  for (var i = 0; i < controller.asteroids.length; i++) {
    final tracked = controller.asteroids[i];
    if (identical(tracked, except)) continue;
    final sim = tracked.sim;
    final spot = safeSpots[i % safeSpots.length];
    sim.position = spot;
    final away = spot - sim.earthCenter;
    sim.velocity = away / away.distance * sim.targetSpeed;
  }
}

/// Ставит астероид на гарантированный курс в Землю с близкой дистанции.
void aimAtEarth(TrackedAsteroid tracked) {
  final sim = tracked.sim;
  sim.position = Offset(sim.earthCenter.dx - 0.3, sim.earthCenter.dy);
  sim.velocity = Offset(sim.targetSpeed, 0);
}

/// Прогоняет раунд на [seconds] секунд, удерживая астероидов в
/// безопасности (никто не падает и не сталкивается).
void runSafe(
  RoundTwoController controller,
  double seconds, {
  double stepSec = 0.1,
}) {
  var t = 0.0;
  while (t < seconds) {
    keepSafe(controller);
    controller.update(stepSec);
    t += stepSec;
  }
}

/// Прогоняет раунд до попадания: астероид [aimed] один раз ставится на
/// курс в Землю, остальные удерживаются в безопасности.
void runUntilAimedImpact(
  RoundTwoController controller,
  TrackedAsteroid aimed, {
  double stepSec = 0.05,
  double maxSec = 10,
}) {
  var t = 0.0;
  final before = controller.impacts;
  aimAtEarth(aimed);
  while (controller.impacts == before && t < maxSec) {
    keepSafe(controller, except: aimed);
    controller.update(stepSec);
    t += stepSec;
  }
}

void main() {
  group('состав поля по конфигурации раунда 2 (#16)', () {
    test('старт — 2 астероида, таймер 50 секунд', () {
      final controller = makeController();
      expect(controller.asteroids, hasLength(2));
      expect(controller.pacing.durationSec, 50);
      expect(controller.remainingSec, 50);
    });

    test('подкрепления +1 каждые 18 секунд до лимита 4', () {
      const pacing = RoundPacing(
        roundNumber: 2,
        name: 'Тестовые угрозы',
        durationSec: 100,
        initialThreats: {ThreatType.asteroid: 2},
        spawnIntervalSec: 10,
        maxObjectsOnScreen: 4,
        speedGrowth: LinearSpeedGrowth(toPercent: 0, durationSec: 100),
      );
      final controller = makeController(pacing: pacing);

      runSafe(controller, 10.1);
      expect(controller.asteroids, hasLength(3));
      runSafe(controller, 10.0);
      expect(controller.asteroids, hasLength(4));
      // Лимит объектов на экране: дальше спавн не идёт.
      runSafe(controller, 20.0);
      expect(controller.asteroids, hasLength(4));
    });

    test('после попадания поле восполняется до стартового состава', () {
      final controller = makeController();
      final aimed = controller.asteroids.first;
      runUntilAimedImpact(controller, aimed);
      expect(controller.impacts, 1);
      expect(controller.asteroids, hasLength(1));

      controller.update(0.1); // следующий шаг — мин-спавн
      expect(controller.asteroids, hasLength(2));
    });

    test('стоп-спавн последних 10 секунд раунда', () {
      const pacing = RoundPacing(
        roundNumber: 2,
        name: 'Тестовый финал',
        durationSec: 30,
        initialThreats: {ThreatType.asteroid: 2},
        spawnIntervalSec: 10,
        maxObjectsOnScreen: 4,
        speedGrowth: LinearSpeedGrowth(toPercent: 0, durationSec: 30),
      );
      final controller = makeController(pacing: pacing);

      runSafe(controller, 10.1); // t≈10: третий астероид
      expect(controller.asteroids, hasLength(3));

      // Один уходит в Землю до стоп-спавна (t≈10 → 11).
      final aimed = controller.asteroids.first;
      runUntilAimedImpact(controller, aimed);
      expect(controller.asteroids, hasLength(2));

      // t=20 — стоп-спавн: несмотря на расписание, новых объектов нет.
      runSafe(controller, 10.0);
      expect(controller.roundElapsed, greaterThanOrEqualTo(20));
      expect(controller.asteroids, hasLength(2));
    });
  });

  group('мультитач-отбивание (критерий 1)', () {
    test('два пальца отбивают два разных астероида независимо', () {
      final controller = makeController();
      final first = controller.asteroids[0].sim;
      final second = controller.asteroids[1].sim;
      first.position = const Offset(0.4, 0.3);
      first.velocity = const Offset(0.24, 0);
      second.position = const Offset(1.2, 0.7);
      second.velocity = const Offset(-0.24, 0);
      final secondVelocityBefore = second.velocity;

      // Палец 1: свайп вверх по первому астероиду.
      final ok1 = controller.tryDeflect(
        const Offset(0.4, 0.3),
        const Offset(0, -1),
      );
      // Палец 2: свайп вправо по второму астероиду.
      final ok2 = controller.tryDeflect(
        const Offset(1.2, 0.7),
        const Offset(1, 0),
      );

      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(controller.deflections, 2);
      // Оба изменили траектории независимо друг от друга.
      expect(first.velocity.dy, lessThan(0));
      expect(second.velocity.dx, greaterThan(0));
      expect(second.velocity, isNot(secondVelocityBefore));
      expect(controller.flashes, hasLength(2));
    });

    test('отбивание одного астероида не трогает второй', () {
      final controller = makeController();
      final first = controller.asteroids[0].sim;
      final second = controller.asteroids[1].sim;
      first.position = const Offset(0.4, 0.3);
      second.position = const Offset(1.2, 0.7);
      second.velocity = const Offset(-0.2, 0.1);
      final secondVelocityBefore = second.velocity;

      controller.tryDeflect(const Offset(0.4, 0.3), const Offset(0, -1));

      expect(second.velocity, secondVelocityBefore);
      expect(second.position, const Offset(1.2, 0.7));
    });

    test('касание вне зон астероидов — промах', () {
      final controller = makeController();
      controller.asteroids[0].sim.position = const Offset(0.4, 0.3);
      controller.asteroids[1].sim.position = const Offset(1.2, 0.7);

      final ok = controller.tryDeflect(
        const Offset(0.8, 0.05),
        const Offset(1, 0),
      );

      expect(ok, isFalse);
      expect(controller.deflections, 0);
    });
  });

  group('столкновения астероидов (критерий 2)', () {
    test('два астероида на встречных курсах отскакивают друг от друга', () {
      final controller = makeController();
      final first = controller.asteroids[0].sim;
      final second = controller.asteroids[1].sim;
      // Встречные курсы в верхней части поля — вне досягаемости
      // гравитационной дуги за время сближения.
      first.position = const Offset(0.5, 0.15);
      first.velocity = const Offset(0.24, 0);
      second.position = const Offset(0.95, 0.15);
      second.velocity = const Offset(-0.24, 0);

      var t = 0.0;
      while (controller.collisions == 0 && t < 5) {
        controller.update(0.02);
        t += 0.02;
      }

      expect(controller.collisions, 1);
      // Объекты отскочили: векторы сменили знак по оси столкновения.
      expect(first.velocity.dx, lessThan(0));
      expect(second.velocity.dx, greaterThan(0));
    });
  });

  group('нарастание темпа (критерий 3)', () {
    test('скорость всех астероидов растёт по таймеру раунда', () {
      final controller = makeController();
      final baseSpeed = controller.asteroids.first.sim.targetSpeed;

      // Вторая половина раунда (t=40 из 50): +35% линейно к концу → +28%.
      runSafe(controller, 40.0);

      for (final tracked in controller.asteroids) {
        expect(
          tracked.sim.targetSpeed,
          greaterThan(baseSpeed * 1.2),
          reason: 'ко второй половине раунда темп заметно выше стартового',
        );
      }
      // Часы объектов синхронизированы с таймером раунда.
      expect(
        controller.asteroids.first.sim.elapsed,
        closeTo(controller.roundElapsed, 0.2),
      );
    });

    test('новый астероид появляется сразу с темпом раунда', () {
      final controller = makeController();
      runSafe(controller, 18.2); // третий астероид только что заспавнился
      expect(controller.asteroids, hasLength(3));

      final speeds = controller.asteroids
          .map((tracked) => tracked.sim.targetSpeed)
          .toSet();
      expect(speeds, hasLength(1)); // темп общий для всех объектов
      expect(
        speeds.single,
        greaterThan(0.24 * 1.1), // t=18 из 50 → +12,6%
      );
    });
  });

  group('попадание и кратер (критерий 3)', () {
    test('пропущенный астероид: −1 звезда и событие с точкой удара', () {
      final controller = makeController();
      final aimed = controller.asteroids.first;
      runUntilAimedImpact(controller, aimed);

      expect(controller.impacts, 1);
      expect(controller.health.quarters, 16); // 5 → 4 звезды
      expect(controller.state, RoundState.playing);
      // Локальный кратер: событие урона с привязкой к точке на диске.
      final craterEvents = controller.health.events
          .where((e) => e.kind.isDamage)
          .toList();
      expect(craterEvents, hasLength(1));
      expect(craterEvents.single.position.distance, closeTo(1.0, 1e-9));
    });

    test('5 попаданий → осколки и поражение, время останавливается', () {
      final controller = makeController();
      for (var hit = 0; hit < 5; hit++) {
        final aimed = controller.asteroids.first;
        runUntilAimedImpact(controller, aimed);
        expect(controller.impacts, hit + 1);
      }

      expect(controller.health.quarters, 0);
      expect(controller.state, RoundState.defeat);
      final elapsed = controller.roundElapsed;
      controller.update(1);
      expect(controller.roundElapsed, elapsed);
    });
  });

  group('таймер раунда', () {
    test('истёкший таймер с живой планетой — победа', () {
      const pacing = RoundPacing(
        roundNumber: 2,
        name: 'Тестовый спринт',
        durationSec: 3,
        initialThreats: {ThreatType.asteroid: 2},
        maxObjectsOnScreen: 4,
        speedGrowth: LinearSpeedGrowth(toPercent: 0, durationSec: 3),
      );
      final controller = makeController(pacing: pacing);

      runSafe(controller, 3.5);

      expect(controller.state, RoundState.victory);
      expect(controller.remainingSec, 0);
      expect(controller.health.quarters, PlanetHealth.maxQuarters);
    });
  });

  group('рестарт', () {
    test('сбрасывает шкалу, состав поля, счётчики и таймер', () {
      final controller = makeController();
      final aimed = controller.asteroids.first;
      runUntilAimedImpact(controller, aimed);
      expect(controller.health.quarters, 16);
      controller.tryDeflect(
        controller.asteroids.first.sim.position,
        const Offset(0, -1),
      );

      controller.reset();

      expect(controller.health.quarters, PlanetHealth.maxQuarters);
      expect(controller.state, RoundState.playing);
      expect(controller.roundElapsed, 0);
      expect(controller.impacts, 0);
      expect(controller.deflections, 0);
      expect(controller.collisions, 0);
      expect(controller.asteroids, hasLength(2));
    });
  });
}
