import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/hitboxes/hitbox_spec.dart';
import 'package:g1/game/hitboxes/touch_gesture.dart';
import 'package:g1/game/pacing/threat_type.dart';

void main() {
  group('Таблица хитбоксов (issue #18, раздел 1)', () {
    test('все 6 типов объектов из спецификации баланса имеют хитбоксы', () {
      expect(hitboxSpecs.keys, unorderedEquals(ThreatType.values));
    });

    test('значения таблицы: визуальные диаметры, зоны касания, мм', () {
      final fragment = hitboxSpecs[ThreatType.giantFragment]!;
      expect(fragment.visualMinPt, 24);
      expect(fragment.visualMaxPt, 28);
      expect(fragment.touchZonePt, 58);
      expect(fragment.physicalSizeMm, 9.5);

      final asteroid = hitboxSpecs[ThreatType.asteroid]!;
      expect(asteroid.visualMinPt, 42);
      expect(asteroid.visualMaxPt, 48);
      expect(asteroid.touchZonePt, 68);
      expect(asteroid.physicalSizeMm, 11);

      final probe = hitboxSpecs[ThreatType.probe]!;
      expect(probe.visualMinPt, 40);
      expect(probe.visualMaxPt, 46);
      expect(probe.touchZonePt, 68);
      expect(probe.physicalSizeMm, 11);

      final capsule = hitboxSpecs[ThreatType.escapeCapsule]!;
      expect(capsule.visualMinPt, 40);
      expect(capsule.visualMaxPt, 44);
      expect(capsule.touchZonePt, 68);
      expect(capsule.physicalSizeMm, 11);

      final giant = hitboxSpecs[ThreatType.giant]!;
      expect(giant.visualMinPt, 78);
      expect(giant.visualMaxPt, 86);
      expect(giant.touchZonePt, 98);
      expect(giant.physicalSizeMm, 16);

      final bolide = hitboxSpecs[ThreatType.heavyBolide]!;
      expect(bolide.visualMinPt, 88);
      expect(bolide.visualMaxPt, 96);
      expect(bolide.touchZonePt, 116);
      expect(bolide.physicalSizeMm, 19);
    });

    test('каждый хитбокс строго шире визуального спрайта (запас прощения)', () {
      for (final entry in hitboxSpecs.entries) {
        expect(
          entry.value.touchZonePt,
          greaterThan(entry.value.visualMaxPt),
          reason: '${entry.key}: хитбокс должен быть шире спрайта',
        );
      }
    });

    test('осколок гиганта — максимальный запас прощения (×2,2 от картинки)',
        () {
      final fragment = hitboxSpecs[ThreatType.giantFragment]!;
      final midpoint = (fragment.visualMinPt + fragment.visualMaxPt) / 2;
      expect(fragment.touchZonePt / midpoint, closeTo(2.2, 0.15));
      for (final entry in hitboxSpecs.entries) {
        if (entry.key == ThreatType.giantFragment) continue;
        expect(
          fragment.forgivenessRatio,
          greaterThan(entry.value.forgivenessRatio),
          reason: 'запас прощения осколка должен быть максимальным',
        );
      }
    });

    test('асимметричный хитбокс капсулы: ведение 68 pt, удар 44 pt', () {
      final capsule = hitboxSpecs[ThreatType.escapeCapsule]!;
      expect(capsule.touchZonePt, 68);
      expect(capsule.strikeZonePt, 44);
      expect(capsule.strikeZonePt!, lessThan(capsule.touchZonePt));
      // Узкая зона удара — только у капсулы.
      for (final entry in hitboxSpecs.entries) {
        if (entry.key == ThreatType.escapeCapsule) continue;
        expect(entry.value.strikeZonePt, isNull);
      }
    });

    test('зона двух пальцев болида совпадает с захватом силовой дуги', () {
      final bolide = hitboxSpecs[ThreatType.heavyBolide]!;
      expect(bolide.twoFingerZonePt, 240);
      expect(
        bolide.twoFingerZonePt,
        TwoFingerGestureConfig.maxArcReachPt,
      );
      // Зона двух пальцев — только у тяжёлого болида.
      for (final entry in hitboxSpecs.entries) {
        if (entry.key == ThreatType.heavyBolide) continue;
        expect(entry.value.twoFingerZonePt, isNull);
      }
    });

    test('визуальные диапазоны корректны: min <= max, размеры положительны',
        () {
      for (final entry in hitboxSpecs.entries) {
        final spec = entry.value;
        expect(spec.visualMinPt, lessThanOrEqualTo(spec.visualMaxPt));
        expect(spec.physicalSizeMm, greaterThan(0));
        expect(spec.touchRadiusPt, spec.touchZonePt / 2);
      }
    });
  });
}
