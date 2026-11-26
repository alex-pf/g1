/// Механики помощи бесшовного онбординга (issue #20).
///
/// Четыре правила адаптивного онбординга из `docs/onboarding.md`:
/// 1. [SlowMoAssist] — замедление времени на 40 % при первом подлёте
///    астероида к Земле в 1-м раунде; мгновенно снимается первым
///    успешным касанием игрока.
/// 2. [GhostSwipeAssist] — полупрозрачный анимированный жест-призрак
///    поверх объекта; отключается после первого успешного выполнения
///    целевого жеста (независимо для каждого типа жеста).
/// 3. [EdgeEntryMarkers] — маркеры входа на краях экрана за 0,5 секунды
///    до возврата объекта с противоположной стороны; постоянный элемент
///    UX, не отключается.
/// 4. [SafeStartTrajectory] — самый первый объект нового типа всегда
///    летит по безопасной траектории с запасом времени на реакцию
///    3–4 секунды до контакта с планетой.
library;

import 'onboarding_constants.dart';

/// Состояние механики замедления времени (правило 1).
enum SlowMoState {
  /// Механика взведена: ждём первого пересечения внешней орбиты.
  armed,

  /// Замедление активно (множитель скорости [OnboardingTimings.slowMoFactor]).
  active,

  /// Игрок коснулся/отбил астероид — механика отработала и больше
  /// в этом раунде не срабатывает.
  completed,
}

/// Slow-Mo: снижает скорость астероида на 40 % при первом подлёте к
/// Земле в 1-м раунде. Мгновенно отключается после первого успешного
/// касания игроком.
///
/// Если игрок не успел среагировать и камень врезался в Землю,
/// механика повторно взводится и срабатывает при следующем заходе
/// ([onPlayerMissed]).
class SlowMoAssist {
  SlowMoState _state = SlowMoState.armed;

  SlowMoState get state => _state;

  bool get isActive => _state == SlowMoState.active;

  /// Множитель скорости времени: 0,6 при активном замедлении, иначе 1,0.
  double get timeScale =>
      isActive ? OnboardingTimings.slowMoFactor : 1.0;

  /// Астероид пересёк внешнюю орбиту Земли — включаем замедление,
  /// если механика взведена.
  void onOuterOrbitCrossed() {
    if (_state == SlowMoState.armed) {
      _state = SlowMoState.active;
    }
  }

  /// Первое успешное касание игрока — замедление мгновенно снимается
  /// и больше не включается.
  void onPlayerContact() {
    if (_state == SlowMoState.active) {
      _state = SlowMoState.completed;
    }
  }

  /// Игрок не успел среагировать (астероид врезался в Землю) —
  /// механика повторно взводится и сработает при следующем заходе.
  void onPlayerMissed() {
    if (_state == SlowMoState.active) {
      _state = SlowMoState.armed;
    }
  }
}

/// Целевой жест для жеста-призрака (правило 2).
///
/// Помимо отбивания астероида в 1-м раунде жест-призрак используется
/// при первом появлении хрупкого гиганта в 4-м раунде (мягкое ведение)
/// и тяжёлого болида в 9-м раунде (толчок двумя пальцами).
enum GhostSwipeTarget {
  /// Отбивание астероида свайпом (раунд 1).
  deflectAsteroid,

  /// Мягкое ведение хрупкого гиганта (раунд 4).
  gentleHoldGiant,

  /// Толчок тяжёлого болида двумя пальцами (раунд 9).
  twoFingerPushBolide,
}

/// Жест-призрак (Ghost Swipe): полупрозрачная анимированная линия
/// свайпа поверх объекта, указывающая направление жеста.
///
/// Для каждого целевого жеста показывается до первого успешного
/// выполнения этого жеста игроком, после чего отключается навсегда.
class GhostSwipeAssist {
  final Set<GhostSwipeTarget> _completed = {};
  GhostSwipeTarget? _visibleFor;

  /// Цель, для которой жест-призрак сейчас показан (null — скрыт).
  GhostSwipeTarget? get visibleFor => _visibleFor;

  bool isVisibleFor(GhostSwipeTarget target) => _visibleFor == target;

  /// Жест уже успешно выполнен игроком и больше не подсказывается.
  bool isCompleted(GhostSwipeTarget target) => _completed.contains(target);

  /// Показать жест-призрак над объектом. Не показывается для жеста,
  /// который игрок уже выполнил успешно.
  void showFor(GhostSwipeTarget target) {
    if (_completed.contains(target)) return;
    _visibleFor = target;
  }

  /// Успешное выполнение целевого жеста: подсказка скрывается и
  /// больше не появляется.
  void onGestureSuccess(GhostSwipeTarget target) {
    _completed.add(target);
    if (_visibleFor == target) {
      _visibleFor = null;
    }
  }

  /// Скрыть подсказку без отметки об успехе (объект покинул поле).
  void hide() {
    _visibleFor = null;
  }
}

/// Край экрана, за который уходит и с которого возвращается объект.
enum ScreenEdge { left, right, top, bottom }

/// Маркер входа: вспышка на краю экрана в точке возврата объекта.
class EdgeEntryMarker {
  const EdgeEntryMarker({
    required this.objectId,
    required this.edge,
    required this.visibleFrom,
    required this.objectReturnsAt,
  });

  /// Идентификатор объекта, который возвращается на поле.
  final String objectId;

  /// Край, на котором появляется маркер.
  final ScreenEdge edge;

  /// Момент появления маркера (за [OnboardingTimings.edgeEntryMarkerLead]
  /// до возврата объекта).
  final Duration visibleFrom;

  /// Момент вылета объекта с противоположной стороны.
  final Duration objectReturnsAt;

  /// Маркер виден в момент [now].
  bool isVisibleAt(Duration now) =>
      !now.isNegative &&
      now >= visibleFrom &&
      now <= objectReturnsAt;
}

/// Маркеры входа на краях экрана (правило 3).
///
/// Подсвечивают точку возврата астероида за 0,5 секунды до вылета с
/// противоположной стороны. Базовый элемент UX: остаётся в игре
/// постоянно (особенно важен в 7-м раунде с аномалией) и не имеет
/// условия отключения.
class EdgeEntryMarkers {
  EdgeEntryMarkers({this.lead = OnboardingTimings.edgeEntryMarkerLead});

  /// За сколько до возврата объекта появляется маркер.
  final Duration lead;

  final List<EdgeEntryMarker> _pending = [];

  /// Объект [objectId] ушёл за край [exitEdge]; вернётся с противоположного
  /// края [returnEdge] в момент [returnAt]. Планирует маркер входа.
  void scheduleReturn({
    required String objectId,
    required ScreenEdge returnEdge,
    required Duration returnAt,
  }) {
    _pending.add(EdgeEntryMarker(
      objectId: objectId,
      edge: returnEdge,
      visibleFrom: returnAt - lead,
      objectReturnsAt: returnAt,
    ));
  }

  /// Маркеры, видимые в момент [now]; просроченные (объект вернулся)
  /// удаляются из расписания.
  List<EdgeEntryMarker> tick(Duration now) {
    _pending.removeWhere((m) => now > m.objectReturnsAt);
    return List.unmodifiable(
      _pending.where((m) => m.isVisibleAt(now)),
    );
  }

  /// Число запланированных маркеров (для диагностики и тестов).
  int get pendingCount => _pending.length;
}

/// Тип угрозы для правила безопасной стартовой траектории.
///
/// Локальный перечень модуля онбординга. После мержа спецификации
/// баланса (#7) и темпа (#16) типы сходятся с
/// `lib/game/pacing/threat_type.dart`; правило онбординга опирается
/// только на факт «первый объект нового типа».
enum OnboardingThreatKind {
  asteroid,
  fragileGiant,
  maneuveringProbe,
  heavyBolide,
  rescueCapsule,
}

/// План спавна объекта: безопасная стартовая траектория или обычная.
class SpawnPlan {
  const SpawnPlan({
    required this.isSafeIntro,
    required this.timeToContact,
    required this.tangential,
  });

  /// Траектория является безопасной стартовой (только для первого
  /// объекта нового типа).
  final bool isSafeIntro;

  /// Запас времени до контакта с планетой. Для безопасной траектории —
  /// в окне 3–4 секунды ([OnboardingTimings.safeTrajectoryMinWindow] —
  /// [OnboardingTimings.safeTrajectoryMaxWindow]).
  final Duration timeToContact;

  /// Касательная траектория мимо планеты (а не прямо в неё).
  final bool tangential;
}

/// Безопасная стартовая траектория (правило 4).
///
/// Самый первый объект каждого нового типа угрозы всегда летит с
/// запасом времени на реакцию (3–4 секунды до контакта с планетой)
/// по касательной. Действует только для первого спавна типа; все
/// последующие объекты того же типа получают обычную траекторию.
class SafeStartTrajectory {
  final Set<OnboardingThreatKind> _seen = {};

  /// Тип уже появлялся на поле.
  bool hasSeen(OnboardingThreatKind kind) => _seen.contains(kind);

  /// План траектории для очередного спавна объекта типа [kind].
  ///
  /// [requestedWindow] — желаемый запас времени; для первого спавна
  /// принудительно ограничивается окном 3–4 секунды.
  SpawnPlan planFor(
    OnboardingThreatKind kind, {
    Duration requestedWindow = OnboardingTimings.safeTrajectoryMinWindow,
  }) {
    if (_seen.add(kind)) {
      return SpawnPlan(
        isSafeIntro: true,
        timeToContact: _clampToSafeWindow(requestedWindow),
        tangential: true,
      );
    }
    return SpawnPlan(
      isSafeIntro: false,
      timeToContact: requestedWindow,
      tangential: false,
    );
  }

  static Duration _clampToSafeWindow(Duration window) {
    if (window < OnboardingTimings.safeTrajectoryMinWindow) {
      return OnboardingTimings.safeTrajectoryMinWindow;
    }
    if (window > OnboardingTimings.safeTrajectoryMaxWindow) {
      return OnboardingTimings.safeTrajectoryMaxWindow;
    }
    return window;
  }
}
