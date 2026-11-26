import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/health/planet_health.dart';
import 'package:g1/game/pacing/round_pacing.dart';
import 'package:g1/game/round1/round_one_controller.dart';

RoundOneController makeController({
  PlanetHealth? health,
  RoundPacing? pacing,
  int seed = 11,
}) {
  final controller = RoundOneController(
    health: health ?? PlanetHealth(),
    pacing: pacing,
    rng: math.Random(seed),
  );
  controller.attachField(aspect: 1.6, earthRadius: 0.25);
  return controller;
}

/// Ставит астероид на гарантированный курс в Землю с близкой дистанции.
void aimAtEarth(RoundOneController controller) {
  final sim = controller.sim;
  sim.position = Offset(sim.earthCenter.dx - 0.3, sim.earthCenter.dy);
  sim.velocity = Offset(sim.targetSpeed, 0);
}

/// Прогоняет раунд до события или таймаута.
void runUntil(
  RoundOneController controller,
  bool Function() done, {
  double stepSec = 0.05,
  double maxSec = 30,
}) {
  var t = 0.0;
  while (!done() && t < maxSec) {
    controller.update(stepSec);
    t += stepSec;
  }
}

void main() {
  group('попадания и шкала жизней (критерий 3)', () {
    test('попадание снимает 1 звезду и астероид уходит на новый заход', () {
      final controller = makeController();
      aimAtEarth(controller);
      runUntil(controller, () => controller.impacts == 1);

      expect(controller.health.quarters, 16); // 5 → 4 звезды
      expect(controller.state, RoundState.playing);
      // Респавн: астероид снова за краем поля, на экране ≤ 1 объекта.
      final p = controller.sim.position;
      final outside =
          p.dx < 0 || p.dx > 1.6 || p.dy < 0 || p.dy > 1;
      expect(outside, isTrue);
    });

    test('5 попаданий: стадии Земли деградируют до осколков, поражение', () {
      final controller = makeController();
      final stages = <EarthStage>[];

      for (var hit = 0; hit < 5; hit++) {
        aimAtEarth(controller);
        runUntil(controller, () => controller.impacts == hit + 1);
        stages.add(controller.health.stage);
      }

      expect(controller.health.quarters, 0);
      expect(controller.state, RoundState.defeat);
      // Зелёная → пустыня → пожары → трещины → осколки.
      expect(stages, <EarthStage>[
        EarthStage.desert,
        EarthStage.fires,
        EarthStage.cracked,
        EarthStage.cracked,
        EarthStage.debris,
      ]);
      // После поражения время раунда не идёт.
      final elapsed = controller.roundElapsed;
      controller.update(1);
      expect(controller.roundElapsed, elapsed);
    });
  });

  group('таймер раунда', () {
    test('истёкший таймер с живой планетой — победа', () {
      const pacing = RoundPacing(
        roundNumber: 1,
        name: 'Тестовый спринт',
        durationSec: 3,
        initialThreats: {},
        maxObjectsOnScreen: 1,
        speedGrowth: LinearSpeedGrowth(toPercent: 0, durationSec: 3),
      );
      final controller = makeController(pacing: pacing);

      // Держим астероид на безопасной орбите до конца таймера.
      var t = 0.0;
      while (controller.state == RoundState.playing && t < 10) {
        final sim = controller.sim;
        sim.position = const Offset(0.1, 0.1);
        sim.velocity = Offset(sim.targetSpeed, 0);
        controller.update(0.1);
        t += 0.1;
      }

      expect(controller.state, RoundState.victory);
      expect(controller.remainingSec, 0);
      expect(controller.health.quarters, PlanetHealth.maxQuarters);
    });

    test('таймер по умолчанию — 45 секунд из конфигурации раунда 1', () {
      final controller = makeController();
      expect(controller.pacing.durationSec, 45);
      expect(controller.remainingSec, 45);
    });
  });

  group('отбивание (критерий 2)', () {
    test('касание в зоне астероида меняет его курс и считается', () {
      final controller = makeController();
      final sim = controller.sim;
      sim.position = const Offset(0.4, 0.3);
      sim.velocity = const Offset(0.24, 0);

      final ok = controller.tryDeflect(
        const Offset(0.42, 0.31), // палец рядом с астероидом
        const Offset(0, -1), // свайп вверх
      );

      expect(ok, isTrue);
      expect(controller.deflections, 1);
      expect(sim.velocity.dy, lessThan(0)); // полетел вверх
      expect(sim.velocity.dx.abs(), lessThan(1e-9));
      expect(controller.flashes, hasLength(1));
    });

    test('касание вне зоны астероида — промах', () {
      final controller = makeController();
      controller.sim.position = const Offset(0.4, 0.3);

      final ok = controller.tryDeflect(
        const Offset(1.2, 0.9),
        const Offset(1, 0),
      );

      expect(ok, isFalse);
      expect(controller.deflections, 0);
    });
  });

  group('slow-mo первого подлёта (#20)', () {
    test('включается на внешней орбите и снимается первым касанием', () {
      final controller = makeController();
      final sim = controller.sim;
      // Подлёт к Земле снаружи: пересекает внешнюю орбиту (2.2 R).
      sim.position = Offset(
        sim.earthCenter.dx - controller.outerOrbitRadius - 0.05,
        sim.earthCenter.dy,
      );
      sim.velocity = Offset(sim.targetSpeed, 0);

      runUntil(controller, () => controller.slowMo.isActive, maxSec: 5);
      expect(controller.slowMo.isActive, isTrue);

      // Пока slow-mo активно, астероид летит медленнее.
      final before = sim.position;
      controller.update(0.1);
      final slowedStep = (sim.position - before).distance;

      controller.tryDeflect(sim.position, const Offset(0, -1));
      expect(controller.slowMo.isActive, isFalse);

      final before2 = sim.position;
      controller.update(0.1);
      final normalStep = (sim.position - before2).distance;
      expect(normalStep, greaterThan(slowedStep * 1.3));
    });
  });

  group('рестарт', () {
    test('сбрасывает шкалу, таймер и состояние', () {
      final controller = makeController();
      aimAtEarth(controller);
      runUntil(controller, () => controller.impacts == 1);
      expect(controller.health.quarters, 16);

      controller.reset();

      expect(controller.health.quarters, PlanetHealth.maxQuarters);
      expect(controller.state, RoundState.playing);
      expect(controller.roundElapsed, 0);
      expect(controller.impacts, 0);
      expect(controller.deflections, 0);
    });
  });
}
