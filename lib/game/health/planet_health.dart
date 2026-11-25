import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'impact_kind.dart';

/// Стадии разрушения Земли (5 стадий, issue #15).
enum EarthStage {
  /// 1. Зелёная планета с океанами: жизни (4.0, 5.0].
  greenPlanet(1, 'Зелёная планета'),

  /// 2. Пустыня: жизни (3.0, 4.0].
  desert(2, 'Пустыня'),

  /// 3. Пожары и извержения: жизни (2.0, 3.0].
  fires(3, 'Пожары и извержения'),

  /// 4. Треснувшая планета: жизни (0.0, 2.0].
  cracked(4, 'Треснувшая планета'),

  /// 5. Осколки: жизни 0.0, раунд завершён поражением.
  debris(5, 'Осколки');

  const EarthStage(this.number, this.label);

  /// Порядковый номер стадии (1–5) для отладки и аналитики.
  final int number;

  /// Человекочитаемое название стадии.
  final String label;
}

/// Событие изменения шкалы жизней с привязкой к точке на диске планеты.
///
/// [position] — координаты в единичном круге диска Земли:
/// (0, 0) — центр планеты, радиус диска = 1. Привязка к точке удара /
/// посадки капсулы — обязательное UX-требование (issue #15, §3).
@immutable
class PlanetEvent {
  const PlanetEvent({
    required this.kind,
    required this.position,
    required this.quartersDelta,
    required this.resultingQuarters,
    this.isMoonImpact = false,
  });

  /// Тип объекта, вызвавшего событие.
  final ImpactKind kind;

  /// Точка удара/посадки на диске планеты (единичный круг).
  final Offset position;

  /// Фактическое изменение шкалы в четвертях (после clamp 0..20).
  final int quartersDelta;

  /// Значение шкалы после события.
  final int resultingQuarters;

  /// Попадание в Луну: урон идёт в общую шкалу (US-03, issue #6),
  /// а на Луне дополнительно остаётся дымящийся кратер.
  final bool isMoonImpact;
}

/// Модель дробной шкалы жизней Земли: 5 звёзд × 4 четверти = 20 шагов.
///
/// В 1-м раунде планета переключается между стадиями дискретно (шаг 1
/// звезда), со 2–4 раундов — плавно, шагом 1/4 звезды (issue #15, §2).
/// Модель ведёт единую шкалу; дискретный режим — надмножество шагов
/// (урон кратен 4 четвертям), поэтому отдельного кода не требует.
class PlanetHealth extends ChangeNotifier {
  PlanetHealth({int initialQuarters = maxQuarters})
      : assert(
          initialQuarters >= 0 && initialQuarters <= maxQuarters,
          'initialQuarters вне диапазона 0..$maxQuarters',
        ),
        _quarters = initialQuarters;

  /// Количество звёзд на шкале.
  static const int maxStars = 5;

  /// Четвертей в одной звезде (радиальное заполнение по секторам 90°).
  static const int quartersPerStar = 4;

  /// Полная шкала: 5 × 4 = 20 шагов.
  static const int maxQuarters = maxStars * quartersPerStar;

  /// Порог критического состояния: 1 звезда и меньше (issue #15, §1).
  static const int criticalThreshold = quartersPerStar;

  int _quarters;
  final List<PlanetEvent> _events = <PlanetEvent>[];

  /// Текущее значение шкалы в четвертях (0..20).
  int get quarters => _quarters;

  /// Текущее значение шкалы в звёздах (0.0..5.0).
  double get stars => _quarters / quartersPerStar;

  /// Журнал событий (попаданий/лечения) с привязкой к точкам на диске.
  List<PlanetEvent> get events => List<PlanetEvent>.unmodifiable(_events);

  /// Критическое состояние: 1 звезда и меньше, но планета ещё жива.
  bool get isCritical => _quarters > 0 && _quarters <= criticalThreshold;

  /// Планета разрушена (стадия «Осколки», раунд завершён поражением).
  bool get isDestroyed => _quarters == 0;

  /// Текущая стадия разрушения Земли по 20-шаговой шкале.
  EarthStage get stage {
    if (_quarters == 0) return EarthStage.debris;
    if (_quarters > 16) return EarthStage.greenPlanet;
    if (_quarters > 12) return EarthStage.desert;
    if (_quarters > 8) return EarthStage.fires;
    return EarthStage.cracked;
  }

  /// Сколько четвертей пройдено внутри текущей стадии (0-based).
  ///
  /// Для стадий 1–3 диапазон 0..3, для стадии 4 (8 четвертей) — 0..7.
  /// Используется визуальным слоем как интенсивность деградации
  /// внутри стадии (issue #15, §2).
  int get stageProgress {
    final int upperBound = switch (stage) {
      EarthStage.greenPlanet => maxQuarters,
      EarthStage.desert => 16,
      EarthStage.fires => 12,
      EarthStage.cracked => 8,
      EarthStage.debris => 0,
    };
    return upperBound - _quarters;
  }

  /// Доля деградации внутри стадии (0.0 — начало стадии, 1.0 — на грани
  /// перехода в следующую).
  double get stageDegradation {
    final int span = switch (stage) {
      EarthStage.cracked => 8,
      EarthStage.debris => 1,
      _ => quartersPerStar,
    };
    if (stage == EarthStage.debris) return 1.0;
    return stageProgress / span;
  }

  /// Заполнение звезды [starIndex] (0-based) в четвертях: 0..4.
  ///
  /// Звёзды заполняются слева направо: первые [fullStars] полные,
  /// следующая — частично, остальные пустые.
  int starFill(int starIndex) {
    assert(starIndex >= 0 && starIndex < maxStars);
    final int fill = _quarters - starIndex * quartersPerStar;
    return fill.clamp(0, quartersPerStar);
  }

  /// Число полностью заполненных звёзд.
  int get fullStars => _quarters ~/ quartersPerStar;

  /// Применяет попадание или лечение с привязкой к точке на диске.
  ///
  /// [position] — точка удара/посадки в единичном круге диска Земли.
  /// Возвращает фактическое изменение шкалы (после clamp 0..20);
  /// 0 — если шкала уже на пределе (урон по осколкам / лечение полной).
  int applyImpact(ImpactKind kind, Offset position) {
    final int next = (_quarters + kind.quartersDelta)
        .clamp(0, maxQuarters)
        .toInt();
    final int applied = next - _quarters;
    _quarters = next;
    _events.add(
      PlanetEvent(
        kind: kind,
        position: position,
        quartersDelta: applied,
        resultingQuarters: next,
      ),
    );
    notifyListeners();
    return applied;
  }

  /// Попадание в Луну (US-03, issue #6): урон идёт в общую шкалу,
  /// событие помечается [PlanetEvent.isMoonImpact], чтобы визуальный
  /// слой Луны оставил на ней дымящийся кратер.
  int applyMoonImpact(ImpactKind kind, Offset position) {
    final int next = (_quarters + kind.quartersDelta)
        .clamp(0, maxQuarters)
        .toInt();
    final int applied = next - _quarters;
    _quarters = next;
    _events.add(
      PlanetEvent(
        kind: kind,
        position: position,
        quartersDelta: applied,
        resultingQuarters: next,
        isMoonImpact: true,
      ),
    );
    notifyListeners();
    return applied;
  }

  /// Сброс шкалы (новый раунд/игра).
  void reset({int quarters = maxQuarters}) {
    assert(quarters >= 0 && quarters <= maxQuarters);
    _quarters = quarters;
    _events.clear();
    notifyListeners();
  }
}
