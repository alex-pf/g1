/// Классификация касаний и эргономика жеста двумя пальцами (тяжёлый
/// болид) — issue #18, `docs/hitboxes.md`, раздел 2.
///
/// Правила распознавания учитывают физиологию руки: подушечки двух пальцев
/// сливаются в одно пятно на малой дистанции, а в динамике пальцы почти
/// никогда не касаются стекла в одну миллисекунду.
library;

import 'dart:math' as math;

/// Точка касания на экране планшета.
///
/// Координаты — в стандартных экранных единицах планшета (pt), время —
/// в миллисекундах монотонных часов устройства.
class TouchContact {
  const TouchContact({
    required this.id,
    required this.xPt,
    required this.yPt,
    required this.downAtMs,
    this.contactDiameterPt = typicalFingerContactDiameterPt,
    this.isElongated = false,
  });

  /// Типичный диаметр пятна контакта подушечки пальца, pt (8–12 мм —
  /// диапазон 48–75 pt по спецификации).
  static const double typicalFingerContactDiameterPt = 60;

  /// Идентификатор точки касания (pointer id).
  final int id;

  /// Координата центра касания по горизонтали, pt.
  final double xPt;

  /// Координата центра касания по вертикали, pt.
  final double yPt;

  /// Момент касания, мс.
  final int downAtMs;

  /// Диаметр пятна контакта, pt (используется фильтром palm rejection).
  final double contactDiameterPt;

  /// Вытянутая овальная форма пятна (ребро ладони, запястье, большой
  /// палец плашмя) — признак ладони, а не подушечки пальца.
  final bool isElongated;

  /// Расстояние между центрами двух точек касания, pt.
  double distanceTo(TouchContact other) {
    final dx = xPt - other.xPt;
    final dy = yPt - other.yPt;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// Конфигурация эргономики жеста двумя пальцами (issue #18, раздел 2).
///
/// Правила едины для толчка двумя пальцами одной руки (указательный +
/// средний) и большими/указательными пальцами обеих рук: классификатор
/// оперирует только дистанцией и временем касаний, не привязываясь
/// к конкретной руке.
class TwoFingerGestureConfig {
  const TwoFingerGestureConfig();

  /// Минимальная дистанция между центрами двух точек касания, pt
  /// (~4,5 мм). Физический минимум, при котором подушечки двух пальцев
  /// не сливаются в одно пятно; ближе — система считает касание одним
  /// широким пальцем и силовой толчок не активирует.
  static const double minFingerDistancePt = 26;

  /// Максимальный захват силовой дуги, pt (~39 мм, примерно ширина трёх
  /// пальцев). Игроку не обязательно ставить оба пальца строго на корпус
  /// болида: достаточно коснуться экрана по обе стороны от него в радиусе
  /// до 240 pt — между пальцами автоматически натягивается силовая дуга.
  static const double maxArcReachPt = 240;

  /// Окно синхронности касания, мс (0,14 сек). Второй палец, опустившийся
  /// на экран в течение 140 мс после первого, образует единый двуручный
  /// толчок; позже — первое касание обрабатывается как слабый удар одним
  /// пальцем.
  static const int syncWindowMs = 140;
}

/// Вердикт классификации пары касаний для силового толчка.
enum TwoFingerVerdict {
  /// Дистанция меньше 26 pt: подушечки слились в одно пятно — касание
  /// обрабатывается как один широкий палец, силовой толчок не активируется.
  singleWideFinger,

  /// Силовой двухпальцевый толчок: вторая точка в окне синхронности
  /// 140 мс, дуга между пальцами не шире 240 pt.
  powerPush,

  /// Второй палец опустился позже 140 мс после первого: первое касание
  /// обрабатывается как слабый удар одним пальцем.
  lateSecondTouch,

  /// Пальцы дальше 240 pt друг от друга: силовая дуга не натягивается,
  /// касания обрабатываются независимо.
  arcTooWide,
}

/// Классификатор жеста двумя пальцами (тяжёлый болид).
class TwoFingerGestureClassifier {
  const TwoFingerGestureClassifier();

  /// Классифицирует пару касаний [first] и [second] (по времени нажатия).
  ///
  /// Порядок проверок повторяет физиологию жеста: сначала слияние пятен
  /// на малой дистанции, затем окно синхронности, затем ширина дуги.
  TwoFingerVerdict classify(TouchContact first, TouchContact second) {
    final distance = first.distanceTo(second);
    if (distance < TwoFingerGestureConfig.minFingerDistancePt) {
      return TwoFingerVerdict.singleWideFinger;
    }
    if (second.downAtMs - first.downAtMs >
        TwoFingerGestureConfig.syncWindowMs) {
      return TwoFingerVerdict.lateSecondTouch;
    }
    if (distance > TwoFingerGestureConfig.maxArcReachPt) {
      return TwoFingerVerdict.arcTooWide;
    }
    return TwoFingerVerdict.powerPush;
  }

  /// Является ли первое касание пары слабым ударом одним пальцем.
  ///
  /// По спецификации первое касание обрабатывается как слабый удар одним
  /// пальцем, если второй палец опоздал за окно синхронности.
  bool isWeakSingleStrike(TouchContact first, TouchContact second) =>
      classify(first, second) == TwoFingerVerdict.lateSecondTouch;
}
