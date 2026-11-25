import 'package:flutter_test/flutter_test.dart';
import 'package:g1/game/health/impact_kind.dart';
import 'package:g1/game/health/planet_health.dart';

void main() {
  const at = Offset(0.3, -0.2);

  group('PlanetHealth: дробная шкала (шаг 1/4 звезды)', () {
    test('стартовое состояние: 5 звёзд, 20 четвертей', () {
      final h = PlanetHealth();
      expect(h.quarters, PlanetHealth.maxQuarters);
      expect(h.stars, 5.0);
      expect(h.stage, EarthStage.greenPlanet);
      expect(h.isCritical, isFalse);
      expect(h.isDestroyed, isFalse);
      expect(h.fullStars, 5);
    });

    test('осколок снимает ровно 1/4 звезды', () {
      final h = PlanetHealth();
      final applied = h.applyImpact(ImpactKind.fragment, at);
      expect(applied, -1);
      expect(h.quarters, 19);
      expect(h.stars, closeTo(4.75, 1e-9));
      expect(h.starFill(4), 3);
      expect(h.starFill(0), 4);
    });

    test('астероид снимает 1 звезду, зонд и болид — 1,5 звезды', () {
      expect(ImpactKind.asteroid.quartersDelta, -4);
      expect(ImpactKind.probe.quartersDelta, -6);
      expect(ImpactKind.bolid.quartersDelta, -6);
      expect(ImpactKind.fragment.quartersDelta, -1);
      expect(ImpactKind.capsule.quartersDelta, 1);
    });

    test('капсула восстанавливает 1/4 звезды', () {
      final h = PlanetHealth(initialQuarters: 10);
      final applied = h.applyImpact(ImpactKind.capsule, at);
      expect(applied, 1);
      expect(h.quarters, 11);
      expect(h.starFill(2), 3);
    });

    test('шкала не уходит ниже 0 и выше 20 (clamp)', () {
      final low = PlanetHealth(initialQuarters: 2);
      expect(low.applyImpact(ImpactKind.asteroid, at), -2);
      expect(low.quarters, 0);
      expect(low.isDestroyed, isTrue);

      final full = PlanetHealth();
      expect(full.applyImpact(ImpactKind.capsule, at), 0);
      expect(full.quarters, PlanetHealth.maxQuarters);
    });
  });

  group('PlanetHealth: границы стадий (5 стадий × 4 доли)', () {
    test('стадия 1 — Зелёная планета: 17–20 четвертей', () {
      expect(PlanetHealth(initialQuarters: 20).stage, EarthStage.greenPlanet);
      expect(PlanetHealth(initialQuarters: 17).stage, EarthStage.greenPlanet);
    });

    test('стадия 2 — Пустыня: 13–16 четвертей', () {
      expect(PlanetHealth(initialQuarters: 16).stage, EarthStage.desert);
      expect(PlanetHealth(initialQuarters: 13).stage, EarthStage.desert);
    });

    test('стадия 3 — Пожары и извержения: 9–12 четвертей', () {
      expect(PlanetHealth(initialQuarters: 12).stage, EarthStage.fires);
      expect(PlanetHealth(initialQuarters: 9).stage, EarthStage.fires);
    });

    test('стадия 4 — Треснувшая планета: 1–8 четвертей', () {
      expect(PlanetHealth(initialQuarters: 8).stage, EarthStage.cracked);
      expect(PlanetHealth(initialQuarters: 1).stage, EarthStage.cracked);
    });

    test('стадия 5 — Осколки: 0 четвертей, поражение', () {
      final h = PlanetHealth(initialQuarters: 0);
      expect(h.stage, EarthStage.debris);
      expect(h.isDestroyed, isTrue);
    });

    test('переходы вниз и вверх через границу стадии', () {
      final h = PlanetHealth(initialQuarters: 17);
      h.applyImpact(ImpactKind.fragment, at); // 16
      expect(h.stage, EarthStage.desert);
      h.applyImpact(ImpactKind.capsule, at); // 17
      expect(h.stage, EarthStage.greenPlanet);
    });

    test('stageProgress считает четверти внутри стадии', () {
      expect(PlanetHealth(initialQuarters: 20).stageProgress, 0);
      expect(PlanetHealth(initialQuarters: 17).stageProgress, 3);
      expect(PlanetHealth(initialQuarters: 16).stageProgress, 0);
      expect(PlanetHealth(initialQuarters: 8).stageProgress, 0);
      expect(PlanetHealth(initialQuarters: 1).stageProgress, 7);
    });
  });

  group('PlanetHealth: критическое состояние (≤ 1 звезды)', () {
    test('4 четверти — критично, 5 — ещё нет, 0 — уже поражение', () {
      expect(PlanetHealth(initialQuarters: 5).isCritical, isFalse);
      expect(PlanetHealth(initialQuarters: 4).isCritical, isTrue);
      expect(PlanetHealth(initialQuarters: 1).isCritical, isTrue);
      expect(PlanetHealth(initialQuarters: 0).isCritical, isFalse);
    });
  });

  group('PlanetHealth: события с привязкой к точке', () {
    test('событие хранит точку удара и итоговую шкалу', () {
      final h = PlanetHealth();
      h.applyImpact(ImpactKind.asteroid, at);
      final e = h.events.single;
      expect(e.position, at);
      expect(e.kind, ImpactKind.asteroid);
      expect(e.quartersDelta, -4);
      expect(e.resultingQuarters, 16);
      expect(e.isMoonImpact, isFalse);
    });

    test('попадание в Луну идёт в общую шкалу и помечается флагом', () {
      final h = PlanetHealth();
      h.applyMoonImpact(ImpactKind.fragment, at);
      expect(h.quarters, 19);
      expect(h.events.single.isMoonImpact, isTrue);
    });

    test('reset возвращает полную шкалу и чистит события', () {
      final h = PlanetHealth(initialQuarters: 7);
      h.applyImpact(ImpactKind.fragment, at);
      h.reset();
      expect(h.quarters, PlanetHealth.maxQuarters);
      expect(h.events, isEmpty);
    });
  });

  group('PlanetHealth: заполнение звёзд индикатора', () {
    test('14 четвертей: 3 полные звезды, четвёртая наполовину', () {
      final h = PlanetHealth(initialQuarters: 14);
      expect(h.starFill(0), 4);
      expect(h.starFill(2), 4);
      expect(h.starFill(3), 2);
      expect(h.starFill(4), 0);
      expect(h.fullStars, 3);
    });

    test('0 четвертей: все звёзды пустые', () {
      final h = PlanetHealth(initialQuarters: 0);
      for (var i = 0; i < PlanetHealth.maxStars; i++) {
        expect(h.starFill(i), 0);
      }
    });
  });
}
