/// Константы бесшовного онбординга (раунды 1–3).
///
/// Источник: issue #20, спецификация — `docs/onboarding.md`.
/// Все тайминги и коэффициенты механик помощи собраны здесь и нигде
/// больше не дублируются.
library;

/// Сводные правила адаптивного онбординга (таблица из 4 правил в спеке).
abstract final class OnboardingTimings {
  OnboardingTimings._();

  /// Правило 1. Slow-Mo: замедление времени на 40 % при первом подлёте
  /// астероида к Земле в 1-м раунде (множитель скорости 0,6).
  static const double slowMoFactor = 0.6;

  /// Правило 3. Маркеры входа на краях экрана: подсветка точки возврата
  /// объекта за 0,5 секунды до вылета с противоположной стороны.
  /// Элемент UX постоянный, не отключается.
  static const Duration edgeEntryMarkerLead = Duration(milliseconds: 500);

  /// Правило 4. Безопасная стартовая траектория: самый первый объект
  /// нового типа летит с запасом времени на реакцию 3–4 секунды до
  /// контакта с планетой.
  static const Duration safeTrajectoryMinWindow = Duration(seconds: 3);
  static const Duration safeTrajectoryMaxWindow = Duration(seconds: 4);

  /// Раунд 2: вознаграждающий мультитач-аккорд, если оба астероида
  /// отбиты в пределах 0,3 секунды друг от друга.
  static const Duration multiTouchChordWindow = Duration(milliseconds: 300);

  /// Раунд 3: длительность заставки гравитационного захвата Луны.
  /// Согласовано со спецификацией темпа (issue #16): раунд 3 = 55 сек
  /// таймера + 4 сек заставки.
  static const Duration moonIntroDuration = Duration(seconds: 4);

  /// Раунд 3: тонкая голубая дуга гравитационной связки проявляется
  /// на 1 секунду в момент захвата Луны.
  static const Duration gravityLinkArcDuration = Duration(seconds: 1);
}

/// Тайминги режиссёрских сценариев первых секунд раундов 1–3.
abstract final class ScenarioTimings {
  ScenarioTimings._();

  // --- Раунд 1 (первые 15 секунд) ---

  /// 0–3 сек: безопасный касательный пролёт с пунктирным следом.
  static const Duration r1FlybyStart = Duration.zero;
  static const Duration r1FlybyEnd = Duration(seconds: 3);

  /// 3–6 сек: демонстрация замкнутости космоса (уход за край и возврат).
  static const Duration r1WrapStart = Duration(seconds: 3);
  static const Duration r1WrapEnd = Duration(seconds: 6);

  /// 6–9 сек: жест-призрак и мягкое замедление на внешней орбите.
  static const Duration r1HintStart = Duration(seconds: 6);
  static const Duration r1HintEnd = Duration(seconds: 9);

  /// 9+ сек: первый контакт игрока, старт таймера раунда.
  static const Duration r1FirstContact = Duration(seconds: 9);

  // --- Раунд 2 (первые 20 секунд) ---

  /// 0–5 сек: синхронный вылет двух астероидов с противоположных краёв.
  static const Duration r2SyncLaunchStart = Duration.zero;
  static const Duration r2SyncLaunchEnd = Duration(seconds: 5);

  /// 12–18 сек: постановка столкновения третьего астероида в воздухе.
  static const Duration r2CollisionStart = Duration(seconds: 12);
  static const Duration r2CollisionEnd = Duration(seconds: 18);

  // --- Раунд 3 (заставка 4 сек + первые 15 секунд раунда) ---

  /// 0–2 сек раунда: золотистый импульс Земля→Луна и единый контур
  /// общей шкалы из 5 звёзд.
  static const Duration r3SharedPulseStart = Duration.zero;
  static const Duration r3SharedPulseEnd = Duration(seconds: 2);

  /// 2–8 сек раунда: демонстрация гравитационной воронки Луны.
  static const Duration r3FunnelStart = Duration(seconds: 2);
  static const Duration r3FunnelEnd = Duration(seconds: 8);
}
