/// Разрешение касания в конкретный игровой объект с учётом перекрытия
/// хитбоксов — issue #18, `docs/hitboxes.md`, разделы 1 и 3.
///
/// Реализует два правила спецификации:
/// - асимметричный хитбокс спасательной капсулы: резкий удар принимается
///   только центральной зоной (44 pt), ведение — широкой (68 pt);
/// - приоритет угроз при перекрытии хитбоксов: касание применяется к более
///   опасному и более близкому к планете объекту.
library;

import '../pacing/threat_type.dart';
import 'hitbox_spec.dart';

/// Характер касания игрока.
enum TouchKind {
  /// Мягкое ведение (плавное подталкивание гиганта или капсулы).
  guide,

  /// Резкий удар (свайп/щелчок) — отбивание или разрушение.
  strike,

  /// Силовой толчок двумя пальцами (тяжёлый болид); распознаётся
  /// классификатором `TwoFingerGestureClassifier`.
  powerPush,
}

/// Игровой объект на поле с позицией центра и дистанцией до планеты.
class FieldObject {
  const FieldObject({
    required this.id,
    required this.type,
    required this.xPt,
    required this.yPt,
    required this.distanceToPlanetPt,
  });

  /// Идентификатор объекта.
  final int id;

  /// Тип объекта (issue #7, `lib/game/pacing/threat_type.dart`).
  final ThreatType type;

  /// Координата центра объекта по горизонтали, pt.
  final double xPt;

  /// Координата центра объекта по вертикали, pt.
  final double yPt;

  /// Расстояние от объекта до планеты, pt — используется приоритетом
  /// угроз при перекрытии хитбоксов.
  final double distanceToPlanetPt;
}

/// Результат разрешения касания.
class HitResolution {
  const HitResolution({
    required this.target,
    required this.coveredIds,
  });

  /// Объект, которому применяется касание, или `null`, если под точкой
  /// никого нет (касание ушло в пустоту).
  final FieldObject? target;

  /// Идентификаторы всех объектов, чьи расширенные хитбоксы накрыли точку
  /// касания (для диагностики перекрытий).
  final List<int> coveredIds;
}

/// Разрешитель касаний: превращает точку касания и жест в цель.
class HitboxResolver {
  const HitboxResolver();

  /// Эффективный радиус зоны касания объекта для жеста [kind], pt.
  ///
  /// Асимметричный хитбокс капсулы: ведение и двухпальцевый толчок
  /// принимаются широкой зоной (68 pt), а резкий удар — только узкой
  /// центральной (44 pt), чтобы игрок случайно не разбил капсулу,
  /// отбивая астероид рядом с ней. Для тяжёлого болида двухпальцевый
  /// толчок использует широкую зону силовой дуги (до 240 pt).
  double effectiveRadiusPt(FieldObject object, TouchKind kind) {
    final spec = hitboxSpecs[object.type]!;
    if (object.type == ThreatType.escapeCapsule && kind == TouchKind.strike) {
      return (spec.strikeZonePt ?? spec.touchZonePt) / 2;
    }
    if (object.type == ThreatType.heavyBolide && kind == TouchKind.powerPush) {
      return (spec.twoFingerZonePt ?? spec.touchZonePt) / 2;
    }
    return spec.touchRadiusPt;
  }

  /// Все объекты, чьи зоны касания накрывают точку ([xPt], [yPt])
  /// для жеста [kind].
  List<FieldObject> coveredObjects(
    List<FieldObject> objects,
    double xPt,
    double yPt,
    TouchKind kind,
  ) {
    return objects.where((object) {
      final radius = effectiveRadiusPt(object, kind);
      final dx = object.xPt - xPt;
      final dy = object.yPt - yPt;
      return dx * dx + dy * dy <= radius * radius;
    }).toList();
  }

  /// Разрешает касание в точке ([xPt], [yPt]) жестом [kind].
  ///
  /// При перекрытии расширенных хитбоксов касание применяется к более
  /// опасному и более близкому к планете объекту: сначала враждебные
  /// угрозы, при равной враждебности — ближний к планете. Например, при
  /// свайпе между астероидом и спасательной капсулой удар гарантированно
  /// получит астероид.
  HitResolution resolve(
    List<FieldObject> objects,
    double xPt,
    double yPt,
    TouchKind kind,
  ) {
    final covered = coveredObjects(objects, xPt, yPt, kind);
    if (covered.isEmpty) {
      return const HitResolution(target: null, coveredIds: []);
    }
    covered.sort((a, b) {
      if (a.type.isHostile != b.type.isHostile) {
        return a.type.isHostile ? -1 : 1;
      }
      return a.distanceToPlanetPt.compareTo(b.distanceToPlanetPt);
    });
    return HitResolution(
      target: covered.first,
      coveredIds: covered.map((o) => o.id).toList(),
    );
  }
}
