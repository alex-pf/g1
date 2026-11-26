import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/pacing/round_pacing.dart';
import 'package:g1/game/round1/asteroid_sim.dart';

AsteroidSim makeSim({
  double aspect = 1.6,
  double earthRadius = 0.25,
  double asteroidRadius = 0.045,
  double baseSpeed = 0.24,
  SpeedGrowth? growth,
  int seed = 7,
}) {
  return AsteroidSim(
    fieldAspect: aspect,
    earthRadius: earthRadius,
    asteroidRadius: asteroidRadius,
    baseSpeed: baseSpeed,
    growth: growth ??
        const SteppedSpeedGrowth(
          stepPercent: 15,
          stepIntervalSec: 15,
          maxSteps: 3,
        ),
    rng: math.Random(seed),
  );
}

void main() {
  group('гравитация Земли', () {
    test('искривляет пролёт в дугу к планете, не меняя модуль скорости', () {
      final sim = makeSim();
      // Пролёт слева направо выше центра Земли: без гравитации y не менялся бы.
      sim.position = const Offset(-0.05, 0.3);
      sim.velocity = Offset(sim.targetSpeed, 0);
      final startDistance = sim.distanceToEarth;
      final startSpeed = sim.speed;

      for (var i = 0; i < 30; i++) {
        sim.update(0.1);
      }

      // Траектория искривлена в сторону Земли (центр на y = 0.5).
      expect(sim.position.dy, greaterThan(0.3));
      expect(sim.distanceToEarth, lessThan(startDistance));
      // Модуль скорости держится темпом раунда (гравитация гнёт, не разгоняет).
      expect(sim.speed, closeTo(startSpeed, 1e-6));
    });

    test('без касаний астероид в итоге выходит на ударную траекторию', () {
      final sim = makeSim();
      sim.spawn();
      var impacted = false;
      // До 60 секунд полёта без отбиваний — критерий приёмки 1 и 3 issue #4.
      for (var i = 0; i < 600 && !impacted; i++) {
        impacted = sim.update(0.1).impact;
      }
      expect(impacted, isTrue);
    });
  });

  group('замкнутое пространство', () {
    test('вылет за правый край — возврат с левого с тем же вектором', () {
      final sim = makeSim();
      sim.position = const Offset(1.58, 0.4);
      sim.velocity = Offset(sim.targetSpeed * 0.98, -sim.targetSpeed * 0.2);

      var wrapped = false;
      var before = sim.velocity;
      while (!wrapped) {
        before = sim.velocity; // вектор непосредственно перед шагом wrap
        wrapped = sim.update(0.05).wrapped;
      }

      expect(wrapped, isTrue);
      expect(sim.position.dx, lessThan(0.2)); // появился слева
      // Wrap сам вектор не меняет: за шаг он повёрнут только гравитацией.
      expect(sim.velocity.dx, closeTo(before.dx, 2e-3));
      expect(sim.velocity.dy, closeTo(before.dy, 2e-3));
      expect(sim.speed, closeTo(before.distance, 2e-3));
    });

    test('вылет за верхний край — возврат с нижнего', () {
      final sim = makeSim();
      sim.position = const Offset(0.8, 0.02);
      sim.velocity = Offset(0, -sim.targetSpeed);

      var wrapped = false;
      for (var i = 0; i < 20 && !wrapped; i++) {
        wrapped = sim.update(0.05).wrapped;
      }

      expect(wrapped, isTrue);
      expect(sim.position.dy, greaterThan(0.9));
    });
  });

  group('темп скорости (issue #16)', () {
    test('ступенчатый прирост +15% каждые 15 секунд, максимум 3 ступени', () {
      final sim = makeSim();
      sim.position = const Offset(0.1, 0.1);
      sim.velocity = const Offset(0.24, 0);

      double speedAt(double t) {
        while (sim.elapsed < t) {
          sim.update(0.05);
        }
        return sim.speed;
      }

      expect(speedAt(5), closeTo(0.24, 1e-6));
      expect(speedAt(16), closeTo(0.24 * 1.15, 1e-6));
      expect(speedAt(31), closeTo(0.24 * 1.30, 1e-6));
      expect(speedAt(44), closeTo(0.24 * 1.30, 1e-6)); // ступень с 45-й секунды
      expect(speedAt(46), closeTo(0.24 * 1.45, 1e-6));
    });
  });

  group('отбивание', () {
    test('меняет направление в сторону свайпа, объект не исчезает', () {
      final sim = makeSim();
      sim.position = const Offset(0.4, 0.3);
      sim.velocity = const Offset(0.24, 0);
      final speedBefore = sim.speed;

      final ok = sim.deflect(const Offset(-1, 1)); // свайп вниз-влево

      expect(ok, isTrue);
      expect(sim.velocity.dx, lessThan(0));
      expect(sim.velocity.dy, greaterThan(0));
      expect(sim.speed, closeTo(speedBefore, 1e-9));
      // Объект продолжает жить в поле.
      sim.update(0.05);
      expect(sim.position, isNot(const Offset(0.4, 0.3)));
    });

    test('нулевое направление не принимается', () {
      final sim = makeSim();
      sim.velocity = const Offset(0.24, 0);
      expect(sim.deflect(Offset.zero), isFalse);
    });
  });

  group('спавн и удар о Землю', () {
    test('спавн — за краем поля, курс с касательным смещением к Земле', () {
      final sim = makeSim();
      sim.spawn();
      final p = sim.position;
      final outside = p.dx < 0 ||
          p.dx > sim.fieldAspect ||
          p.dy < 0 ||
          p.dy > 1;
      expect(outside, isTrue);
      // Курс в сторону Земли.
      final toEarth = sim.earthCenter - p;
      final dot = sim.velocity.dx * toEarth.dx + sim.velocity.dy * toEarth.dy;
      expect(dot, greaterThan(0));
      // И при этом не строго в центр (есть касательная составляющая).
      final cross = sim.velocity.dx * toEarth.dy - sim.velocity.dy * toEarth.dx;
      expect(cross.abs(), greaterThan(1e-6));
    });

    test('попадание фиксируется при касании диска Земли', () {
      final sim = makeSim();
      sim.position = Offset(sim.earthCenter.dx - 0.3, sim.earthCenter.dy);
      sim.velocity = Offset(sim.targetSpeed, 0); // прямо в центр
      var impact = false;
      for (var i = 0; i < 30 && !impact; i++) {
        impact = sim.update(0.05).impact;
      }
      expect(impact, isTrue);
      // Точка удара на диске — в единичном круге.
      expect(sim.impactPointOnDisc.distance, lessThanOrEqualTo(1.0 + 1e-9));
    });
  });

  group('прогноз выхода (маркеры входа #20)', () {
    test('возвращает край выхода и точку входа на противоположном краю', () {
      final sim = makeSim();
      sim.position = const Offset(1.55, 0.5);
      sim.velocity = const Offset(0.24, 0);
      final prediction = sim.predictExit(0.5);
      expect(prediction, isNotNull);
      expect(prediction!.exitEdge, FieldEdge.right);
      expect(prediction.entryEdge, FieldEdge.left);
      expect(prediction.entryPoint.dx, lessThan(0));
      expect(prediction.timeToExitSec, lessThanOrEqualTo(0.5));
    });

    test('null, если выход дальше горизонта', () {
      final sim = makeSim();
      sim.position = const Offset(0.1, 0.5);
      sim.velocity = const Offset(0.24, 0);
      expect(sim.predictExit(0.5), isNull);
    });
  });
}
