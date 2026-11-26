import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/pacing/round_pacing.dart';
import 'package:g1/game/round1/asteroid_sim.dart';
import 'package:g1/game/round2/asteroid_collisions.dart';

AsteroidSim makeSim() => AsteroidSim(
      fieldAspect: 1.6,
      earthRadius: 0.25,
      asteroidRadius: 0.045,
      baseSpeed: 0.24,
      growth: const LinearSpeedGrowth(toPercent: 0, durationSec: 50),
      rng: math.Random(1),
    );

void main() {
  group('столкновение астероидов (US-02, критерий 2)', () {
    test('лобовое столкновение: астероиды меняются скоростями', () {
      final a = makeSim()
        ..position = const Offset(0.6, 0.5)
        ..velocity = const Offset(0.24, 0);
      final b = makeSim()
        ..position = const Offset(0.68, 0.5)
        ..velocity = const Offset(-0.24, 0);

      final collided = resolveAsteroidCollision(a, b);

      expect(collided, isTrue);
      // Равные массы: нормальные компоненты обменялись.
      expect(a.velocity.dx, closeTo(-0.24, 1e-9));
      expect(b.velocity.dx, closeTo(0.24, 1e-9));
      // Тела разведены: больше не пересекаются.
      expect(
        (b.position - a.position).distance,
        greaterThanOrEqualTo(a.asteroidRadius + b.asteroidRadius - 1e-9),
      );
    });

    test('скользящее столкновение: неподвижная цель уносится по нормали', () {
      final a = makeSim()
        ..position = const Offset(0.6, 0.5)
        ..velocity = const Offset(0.24, 0);
      final b = makeSim()
        ..position = const Offset(0.68, 0.53)
        ..velocity = Offset.zero;

      final collided = resolveAsteroidCollision(a, b);

      expect(collided, isTrue);
      // Цель получила скорость вдоль линии центров (вправо-вверх).
      expect(b.velocity.dx, greaterThan(0));
      expect(b.velocity.dy, greaterThan(0));
      // Налетающий потерял нормальную составляющую: курс отклонился вниз.
      expect(a.velocity.dy, lessThan(0));
      // Суммарный импульс сохранился.
      expect(
        a.velocity.dx + b.velocity.dx,
        closeTo(0.24, 1e-9),
      );
      expect(a.velocity.dy + b.velocity.dy, closeTo(0, 1e-9));
    });

    test('расходящиеся тела не сталкиваются', () {
      final a = makeSim()
        ..position = const Offset(0.6, 0.5)
        ..velocity = const Offset(-0.24, 0);
      final b = makeSim()
        ..position = const Offset(0.68, 0.5)
        ..velocity = const Offset(0.24, 0);

      final collided = resolveAsteroidCollision(a, b);

      expect(collided, isFalse);
      expect(a.velocity, const Offset(-0.24, 0));
      expect(b.velocity, const Offset(0.24, 0));
    });

    test('непересекающиеся тела не сталкиваются', () {
      final a = makeSim()
        ..position = const Offset(0.6, 0.5)
        ..velocity = const Offset(0.24, 0);
      final b = makeSim()
        ..position = const Offset(0.8, 0.5)
        ..velocity = const Offset(-0.24, 0);

      expect(resolveAsteroidCollision(a, b), isFalse);
      expect(a.velocity, const Offset(0.24, 0));
      expect(b.velocity, const Offset(-0.24, 0));
    });
  });
}
