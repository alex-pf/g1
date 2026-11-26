import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/hitboxes/hitbox_resolver.dart';
import 'package:g1/game/hitboxes/hitbox_spec.dart';
import 'package:g1/game/pacing/threat_type.dart';

FieldObject obj(
  int id,
  ThreatType type,
  double x,
  double y, {
  double distanceToPlanet = 500,
}) =>
    FieldObject(
      id: id,
      type: type,
      xPt: x,
      yPt: y,
      distanceToPlanetPt: distanceToPlanet,
    );

void main() {
  const resolver = HitboxResolver();

  group('Зоны касания по таблице (issue #18, раздел 1)', () {
    test('касание внутри расширенного хитбокса астероида засчитывается', () {
      // Радиус зоны астероида 34 pt (68/2); касание в 30 pt от центра.
      final asteroid = obj(1, ThreatType.asteroid, 100, 100);
      final resolution = resolver.resolve([asteroid], 130, 100, TouchKind.strike);
      expect(resolution.target?.id, 1);
    });

    test('касание за пределами хитбокса уходит в пустоту', () {
      final asteroid = obj(1, ThreatType.asteroid, 100, 100);
      final resolution = resolver.resolve([asteroid], 200, 100, TouchKind.strike);
      expect(resolution.target, isNull);
      expect(resolution.coveredIds, isEmpty);
    });

    test('хитбокс шире спрайта: касание рядом с осколком засчитывается', () {
      // Визуальный радиус осколка ~14 pt, зона касания 58 pt (радиус 29):
      // палец, закрывший осколок, всё равно попадает.
      final fragment = obj(1, ThreatType.giantFragment, 100, 100);
      final resolution =
          resolver.resolve([fragment], 125, 100, TouchKind.strike);
      expect(resolution.target?.id, 1);
    });
  });

  group('Асимметричный хитбокс спасательной капсулы', () {
    // Капсула: ведение 68 pt (радиус 34), удар 44 pt (радиус 22).
    final capsule = obj(1, ThreatType.escapeCapsule, 100, 100);

    test('мягкое ведение принимается широкой зоной 68 pt', () {
      // 30 pt от центра: внутри зоны ведения (34), снаружи зоны удара (22).
      final resolution = resolver.resolve([capsule], 130, 100, TouchKind.guide);
      expect(resolution.target?.id, 1);
    });

    test('резкий удар в кольце 44–68 pt капсулу не разрушает', () {
      // Тот же заход, но резким ударом: узкая центральная зона не накрыта.
      final resolution =
          resolver.resolve([capsule], 130, 100, TouchKind.strike);
      expect(resolution.target, isNull);
    });

    test('резкий удар в центральную зону 44 pt принимается', () {
      final resolution = resolver.resolve([capsule], 120, 100, TouchKind.strike);
      expect(resolution.target?.id, 1);
    });
  });

  group('Силовая дуга двух пальцев для тяжёлого болида', () {
    // Болид: 1 палец — 116 pt (радиус 58), 2 пальца — до 240 pt (радиус 120).
    final bolide = obj(1, ThreatType.heavyBolide, 500, 500);

    test('толчок двумя пальцами захватывает болид по бокам (до 240 pt)', () {
      // Палец в 100 pt от центра болида: вне зоны одного пальца (58),
      // внутри дуги двух (120).
      final resolution =
          resolver.resolve([bolide], 600, 500, TouchKind.powerPush);
      expect(resolution.target?.id, 1);
    });

    test('один палец в той же точке болид не берёт', () {
      final resolution = resolver.resolve([bolide], 600, 500, TouchKind.strike);
      expect(resolution.target, isNull);
    });
  });

  group('Приоритет угроз при перекрытии хитбоксов (раздел 3)', () {
    test('свайп между астероидом и капсулой достаётся астероиду', () {
      // Хитбоксы перекрываются: зона астероида (34 pt) и центральная зона
      // удара капсулы (22 pt) обе накрывают точку касания.
      final asteroid = obj(1, ThreatType.asteroid, 100, 100,
          distanceToPlanet: 400);
      final capsule = obj(2, ThreatType.escapeCapsule, 140, 100,
          distanceToPlanet: 200); // капсула ближе к планете
      final resolution = resolver.resolve(
        [asteroid, capsule],
        125,
        100,
        TouchKind.strike,
      );
      expect(resolution.coveredIds, containsAll([1, 2]));
      expect(resolution.target?.id, 1,
          reason: 'враждебная угроза важнее цели сопровождения');
    });

    test('из двух угроз касание получает более близкая к планете', () {
      final far = obj(1, ThreatType.asteroid, 100, 100,
          distanceToPlanet: 400);
      final near = obj(2, ThreatType.probe, 120, 100, distanceToPlanet: 150);
      final resolution = resolver.resolve([far, near], 110, 100, TouchKind.strike);
      expect(resolution.target?.id, 2);
    });

    test('приоритет не зависит от порядка объектов в списке', () {
      final capsule = obj(1, ThreatType.escapeCapsule, 140, 100,
          distanceToPlanet: 100);
      final asteroid = obj(2, ThreatType.asteroid, 100, 100,
          distanceToPlanet: 900);
      final resolution = resolver.resolve(
        [capsule, asteroid],
        125,
        100,
        TouchKind.strike,
      );
      expect(resolution.target?.id, 2);
    });
  });

  group('Эффективные радиусы согласованы с конфигурацией', () {
    test('радиусы берутся из hitboxSpecs, а не из констант логики', () {
      final asteroid = obj(1, ThreatType.asteroid, 0, 0);
      final capsule = obj(2, ThreatType.escapeCapsule, 0, 0);
      final bolide = obj(3, ThreatType.heavyBolide, 0, 0);
      expect(
        resolver.effectiveRadiusPt(asteroid, TouchKind.strike),
        hitboxSpecs[ThreatType.asteroid]!.touchZonePt / 2,
      );
      expect(
        resolver.effectiveRadiusPt(capsule, TouchKind.strike),
        hitboxSpecs[ThreatType.escapeCapsule]!.strikeZonePt! / 2,
      );
      expect(
        resolver.effectiveRadiusPt(capsule, TouchKind.guide),
        hitboxSpecs[ThreatType.escapeCapsule]!.touchZonePt / 2,
      );
      expect(
        resolver.effectiveRadiusPt(bolide, TouchKind.powerPush),
        hitboxSpecs[ThreatType.heavyBolide]!.twoFingerZonePt! / 2,
      );
    });
  });
}
