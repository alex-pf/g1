/// Защита от случайных касаний ладонью (palm rejection) — issue #18,
/// `docs/hitboxes.md`, раздел 3.
///
/// На планшете игроки часто опираются ребром ладони на край экрана или
/// придерживают корпус большими пальцами. Четыре фильтра исключают ложные
/// срабатывания: площадь/форма пятна контакта, неподвижная опора,
/// краевой буфер хвата и приоритет угроз при перекрытии хитбоксов
/// (последний реализован в `hitbox_resolver.dart`).
library;

import 'dart:math' as math;

import 'touch_gesture.dart';

/// Конфигурация фильтров palm rejection (issue #18, раздел 3).
class PalmRejectionConfig {
  const PalmRejectionConfig();

  /// Максимальный диаметр пятна контакта пальца, pt (~20 мм). Любое
  /// касание с диаметром отпечатка свыше 125 pt полностью игнорируется.
  static const double maxFingerContactDiameterPt = 125;

  /// Диаметр пятна контакта подушечки пальца, pt (8–12 мм): типичный
  /// диапазон 48–75 pt.
  static const double minFingerContactDiameterPt = 48;
  static const double maxTypicalFingerContactDiameterPt = 75;

  /// Время неподвижности точки касания, после которого она маркируется
  /// как «опорная рука», мс. В «Планетарной защите» нет механик удержания
  /// пальца на месте, поэтому неподвижная точка без объекта под ней —
  /// опора, а не жест.
  static const int stationarySupportMs = 250;

  /// Краевой буфер хвата, pt (~3 мм): узкая буферная рамка по всему
  /// периметру экрана для защиты от пальцев, держащих планшет.
  static const double edgeBufferPt = 18;
}

/// Причина отбраковки касания фильтрами palm rejection.
enum PalmRejectionReason {
  /// Диаметр пятна контакта свыше 125 pt (~20 мм) — ладонь или запястье.
  oversizedContact,

  /// Вытянутая овальная форма пятна — ребро ладони, запястье или большой
  /// палец плашмя.
  elongatedContact,

  /// Неподвижная опора: точка неподвижна дольше 250 мс, под ней не
  /// пролетает объект.
  stationarySupport,

  /// Касание возникло в краевом буфере 18 pt и направлено к краю —
  /// палец, держащий планшет.
  edgeGrip,
}

/// Фильтр площади и формы пятна контакта.
///
/// Подушечка пальца при касании образует пятно диаметром 48–75 pt
/// (8–12 мм). Касание с диаметром свыше 125 pt или вытянутой овальной
/// формой игнорируется и не сбивает хрупких гигантов или капсулы.
class ContactShapeFilter {
  const ContactShapeFilter();

  /// Причина отбраковки касания или `null`, если касание похоже на палец.
  PalmRejectionReason? rejectReason(TouchContact contact) {
    if (contact.contactDiameterPt >
        PalmRejectionConfig.maxFingerContactDiameterPt) {
      return PalmRejectionReason.oversizedContact;
    }
    if (contact.isElongated) {
      return PalmRejectionReason.elongatedContact;
    }
    return null;
  }

  /// Принимается ли касание как палец (не ладонь).
  bool accepts(TouchContact contact) => rejectReason(contact) == null;
}

/// Фильтр неподвижной опоры (250 мс).
///
/// Если точка касания остаётся неподвижной дольше 250 мс и в этот момент
/// под ней не пролетает объект, система маркирует её как «опорную руку»
/// и перестаёт учитывать до отрыва от экрана. Появление объекта под точкой
/// сбрасывает отсчёт: игрок мог придержать палец над целью.
class StationarySupportFilter {
  StationarySupportFilter({this.movementTolerancePt = 4});

  /// Допуск смещения центра касания, при котором точка считается
  /// неподвижной, pt.
  final double movementTolerancePt;

  final Map<int, _StationaryTrack> _tracks = {};

  /// Обновляет отслеживание точки [contact] в момент [nowMs].
  ///
  /// [objectUnderPoint] — под точкой в этот момент пролетает объект.
  /// Возвращает `true`, если точка маркирована как «опорная рука» и должна
  /// игнорироваться.
  bool isSupportHand(
    TouchContact contact,
    int nowMs, {
    bool objectUnderPoint = false,
  }) {
    final track = _tracks.putIfAbsent(
      contact.id,
      () => _StationaryTrack(xPt: contact.xPt, yPt: contact.yPt, sinceMs: nowMs),
    );

    // Маркировка держится до отрыва точки от экрана.
    if (track.markedAsSupport) return true;

    final moved = _distance(track, contact) > movementTolerancePt;
    if (moved) {
      // Движущийся палец — не опора: переякориваем отсчёт.
      track.reanchor(contact.xPt, contact.yPt, nowMs);
      return false;
    }
    if (objectUnderPoint) {
      // Под точкой пролетает объект: отсчёт начинается заново.
      track.reanchor(contact.xPt, contact.yPt, nowMs);
      return false;
    }
    if (nowMs - track.sinceMs > PalmRejectionConfig.stationarySupportMs) {
      track.markedAsSupport = true;
      return true;
    }
    return false;
  }

  /// Отрыв точки от экрана: сбрасывает отслеживание и маркировку.
  void lift(int contactId) => _tracks.remove(contactId);

  double _distance(_StationaryTrack track, TouchContact contact) {
    final dx = track.xPt - contact.xPt;
    final dy = track.yPt - contact.yPt;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// Отслеживаемое состояние одной неподвижной точки.
class _StationaryTrack {
  _StationaryTrack({required this.xPt, required this.yPt, required this.sinceMs});

  double xPt;
  double yPt;
  int sinceMs;
  bool markedAsSupport = false;

  void reanchor(double newX, double newY, int nowMs) {
    xPt = newX;
    yPt = newY;
    sinceMs = nowMs;
  }
}

/// Краевой буфер хвата (18 pt).
///
/// По всему периметру экрана выделена узкая буферная рамка. Касания,
/// возникшие внутри неё и направленные к краю, игнорируются (защита от
/// пальцев, держащих планшет). При этом активный свайп, начатый на
/// игровом поле и уходящий за край экрана вслед за астероидом,
/// отрабатывается без обрыва.
class EdgeBufferFilter {
  const EdgeBufferFilter({
    required this.screenWidthPt,
    required this.screenHeightPt,
  });

  /// Ширина экрана, pt.
  final double screenWidthPt;

  /// Высота экрана, pt.
  final double screenHeightPt;

  /// Точка находится внутри краевого буфера 18 pt.
  bool isInEdgeBuffer(double xPt, double yPt) {
    const b = PalmRejectionConfig.edgeBufferPt;
    return xPt < b ||
        yPt < b ||
        xPt > screenWidthPt - b ||
        yPt > screenHeightPt - b;
  }

  /// Касание, возникшее в точке ([xPt], [yPt]) с начальным смещением
  /// ([dxPt], [dyPt]) за первый кадр, подлежит игнорированию.
  ///
  /// Игнорируются касания внутри буфера, направленные к ближайшему краю
  /// (пальцы, держащие планшет), и статичные касания в буфере (хват
  /// корпуса). Касание в буфере, направленное в игровое поле, — это
  /// свайп игрока, он принимается.
  bool shouldIgnoreStart(
    double xPt,
    double yPt, {
    double dxPt = 0,
    double dyPt = 0,
  }) {
    if (!isInEdgeBuffer(xPt, yPt)) return false;
    if (dxPt == 0 && dyPt == 0) {
      // Статичное касание в буфере — хват корпуса планшета.
      return true;
    }
    return _isDirectedToNearestEdge(xPt, yPt, dxPt, dyPt);
  }

  /// Активный свайп, начатый на игровом поле, не обрывается на краю.
  ///
  /// Метод зафиксирован для читаемости вызывающего кода: обрыв активного
  /// жеста краевым буфером запрещён спецификацией, поэтому результат
  /// всегда `false` независимо от текущей позиции точки.
  bool shouldInterruptActiveSwipe(
    TouchContact swipeStart,
    double xPt,
    double yPt,
  ) =>
      false;

  /// Направлено ли движение к ближайшему краю экрана.
  bool _isDirectedToNearestEdge(double xPt, double yPt, double dxPt, double dyPt) {
    const b = PalmRejectionConfig.edgeBufferPt;
    // Ближайший край определяем по меньшему расстоянию до границы буфера.
    final distances = {
      'left': xPt - 0,
      'top': yPt - 0,
      'right': screenWidthPt - xPt,
      'bottom': screenHeightPt - yPt,
    };
    final nearest = distances.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;
    switch (nearest) {
      case 'left':
        return xPt < b && dxPt < 0;
      case 'top':
        return yPt < b && dyPt < 0;
      case 'right':
        return xPt > screenWidthPt - b && dxPt > 0;
      case 'bottom':
        return yPt > screenHeightPt - b && dyPt > 0;
    }
    return false;
  }
}
