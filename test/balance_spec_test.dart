import 'package:flutter_test/flutter_test.dart';
import 'package:g1/game/health/impact_kind.dart';
import 'package:g1/game/health/planet_health.dart';
import 'package:g1/game/pacing/threat_type.dart';

/// Контрактные тесты спецификации баланса объектов (`docs/balance.md`,
/// issue #7): значения урона/лечения в обеих моделях (`ImpactKind` —
/// шкала жизней, `ThreatType` — темп раундов) обязаны совпадать с
/// таблицей и между собой, чтобы модели не расходились снова.
void main() {
  group('Баланс объектов (docs/balance.md): таблица урона ImpactKind', () {
    test('урон/лечение каждого типа соответствует спецификации', () {
      // Четверти звезды: −1 звезда = −4, −1/4 звезды = −1, +1/4 = +1.
      expect(ImpactKind.asteroid.quartersDelta, -4); // −1 звезда
      expect(ImpactKind.giant.quartersDelta, -4); // −1 звезда (целиком)
      expect(ImpactKind.fragment.quartersDelta, -1); // −1/4 звезды
      expect(ImpactKind.probe.quartersDelta, -4); // −1 звезда
      expect(ImpactKind.bolid.quartersDelta, -6); // −1,5 звезды
      expect(ImpactKind.capsule.quartersDelta, 1); // +1/4 звезды
    });
  });

  group('Баланс объектов (docs/balance.md): таблица урона ThreatType', () {
    test('урон/эффект каждого типа соответствует спецификации', () {
      // Звёзды: положительное значение — урон, отрицательное — лечение.
      expect(ThreatType.asteroid.starDamage, 1.0); // −1 звезда
      expect(ThreatType.giant.starDamage, 1.0); // −1 звезда (целиком)
      expect(ThreatType.giantFragment.starDamage, 0.25); // −1/4 звезды
      expect(ThreatType.probe.starDamage, 1.0); // −1 звезда
      expect(ThreatType.heavyBolide.starDamage, 1.5); // −1,5 звезды
      expect(ThreatType.escapeCapsule.starDamage, -0.25); // +1/4 звезды
    });

    test('враждебность типов соответствует спецификации', () {
      for (final type in ThreatType.values) {
        expect(
          type.isHostile,
          type != ThreatType.escapeCapsule,
          reason: 'капсула — единственный невраждебный объект',
        );
      }
    });
  });

  group('Баланс объектов: консистентность ImpactKind ↔ ThreatType', () {
    /// Пары одного и того же объекта в двух моделях.
    const pairs = {
      ImpactKind.asteroid: ThreatType.asteroid,
      ImpactKind.giant: ThreatType.giant,
      ImpactKind.fragment: ThreatType.giantFragment,
      ImpactKind.probe: ThreatType.probe,
      ImpactKind.bolid: ThreatType.heavyBolide,
      ImpactKind.capsule: ThreatType.escapeCapsule,
    };

    test('каждый объект покрыт обеими моделями', () {
      expect(pairs.length, ThreatType.values.length);
      expect(pairs.length, ImpactKind.values.length);
    });

    test('урон в моделях совпадает с точностью до четверти звезды', () {
      for (final entry in pairs.entries) {
        // ImpactKind: отрицательное = урон; ThreatType: положительное =
        // урон. Приводим к общему знаку через четверти звезды.
        final quartersFromThreat =
            (-entry.value.starDamage * PlanetHealth.quartersPerStar).round();
        expect(
          entry.key.quartersDelta,
          quartersFromThreat,
          reason: '${entry.key.name} ↔ ${entry.value.name}: модели '
              'расходятся с таблицей docs/balance.md',
        );
      }
    });
  });
}
