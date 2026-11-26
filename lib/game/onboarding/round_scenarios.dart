/// Режиссёрские сценарии бесшовного онбординга (раунды 1–3, issue #20).
///
/// Обучение действием без текста: игра режиссирует первые 10–15 секунд
/// каждого раунда через безопасные траектории, визуальные подсказки и
/// причинно-следственные связи. Спецификация — `docs/onboarding.md`.
///
/// Сценарии заданы расписаниями [ScenarioBeat] и проигрываются
/// [ScenarioPlayer] по игровому времени. Реактивные события (ответ на
/// действия игрока) вынесены в [MultiTouchChord] и [MoonOnboarding].
library;

import 'onboarding_constants.dart';

/// Тип режиссёрского события сценария.
enum OnboardingBeat {
  // --- Раунд 1: базовая физика, отбивание, замкнутое пространство ---
  /// Касательный пролёт первого астероида мимо Земли с полупрозрачным
  /// пунктирным следом траектории (гравитация искривляет путь в дугу).
  tangentialFlybyDottedTrail,

  /// Астероид огибает Землю и уходит за правый край; за 0,5 секунды до
  /// возврата на левом краю вспыхивает маркер входа; камень возвращается
  /// и закручивается прямо на планету.
  wrapAroundWithEntryMarker,

  /// Астероид пересекает внешнюю орбиту: время замедляется на 40 %,
  /// поверх камня — полупрозрачный жест-призрак со свайпом от планеты.
  ghostSwipeWithSlowMo,

  /// Первый контакт игрока: замедление мгновенно снимается, упругий
  /// звуковой и визуальный отклик удара, индикатор времени раунда
  /// начинает основной отсчёт.
  firstContactStartsRoundTimer,

  // --- Раунд 2: мультитач и столкновение объектов ---
  /// Синхронный вылет двух астероидов с противоположных краёв экрана
  /// (слева и справа) с одинаковой скоростью: отбить оба по очереди
  /// одним пальцем физически неудобно — игрок задействует два пальца.
  syncDualLaunch,

  /// Вознаграждение за мультитач: оба астероида отбиты в пределах
  /// 0,3 секунды друг от друга — яркие росчерки и гармоничный двойной
  /// звуковой аккорд (см. [MultiTouchChord]).
  multiTouchChordReward,

  /// Третий астероид выходит на пересекающийся с уже летающим камнем
  /// курс на безопасном расстоянии от Земли: столкновение со снопом
  /// искр — астероиды можно бить друг о друга, как бильярдные шары.
  midAirCollisionSetup,

  // --- Раунд 3: Луна, вторая гравитация, общая шкала жизни ---
  /// Заставка (4 сек до старта таймера): Луна влетает из-за края,
  /// «цепляется» за Землю и выравнивается на круговую орбиту.
  moonGravityCaptureIntro,

  /// На 1 секунду проявляется тонкая голубая дуга гравитационной
  /// связки в момент захвата Луны.
  gravityLinkArc,

  /// 0–2 сек раунда: золотистый световой импульс от Земли к Луне;
  /// блок из 5 звёзд на мгновение обводится единым контуром — система
  /// Земля–Луна защищается как единое целое.
  sharedHealthPulse,

  /// 2–8 сек раунда: первый астероид идёт мимо Земли, но задевает
  /// орбиту Луны; гравитационный ореол Луны вспыхивает и резко
  /// заворачивает астероид к её поверхности.
  gravityFunnelDemo,

  /// Успешная защита Луны: по её поверхности проходит лёгкая
  /// защитная рябь (см. [MoonOnboarding.onMoonDefended]).
  moonDefendedRipple,

  /// Попадание в Луну: дымящийся кратер, −1 звезда из общей шкалы,
  /// Земля синхронно теряет часть зелёного покрова
  /// (см. [MoonOnboarding.onMoonImpact]).
  moonImpactCrater,
}

/// Одно режиссёрское событие сценария.
class ScenarioBeat {
  const ScenarioBeat({
    required this.beat,
    required this.start,
    this.end,
    required this.summary,
  });

  final OnboardingBeat beat;

  /// Момент начала (секунды от старта сценария).
  final Duration start;

  /// Момент окончания; `null` — мгновенное событие.
  final Duration? end;

  /// Краткое описание из спецификации (для журналов и отладки).
  final String summary;

  /// Событие активно в момент [now] (для событий с окном).
  bool isActiveAt(Duration now) {
    final e = end;
    if (e == null) return now == start;
    return now >= start && now < e;
  }
}

/// Расписания режиссёрских сценариев раундов 1–3.
///
/// Тайминги — из `docs/onboarding.md`; согласованы со спецификацией
/// темпа (#16): сценарии укладываются в длительности раундов
/// (45/50/55 сек), заставка Луны — 4 секунды, как в таблице темпа.
abstract final class RoundScenarios {
  RoundScenarios._();

  /// Раунд 1, первые 15 секунд: базовая физика, отбивание пальцем
  /// и замкнутое пространство.
  static const List<ScenarioBeat> roundOne = [
    ScenarioBeat(
      beat: OnboardingBeat.tangentialFlybyDottedTrail,
      start: ScenarioTimings.r1FlybyStart,
      end: ScenarioTimings.r1FlybyEnd,
      summary: 'Касательный пролёт мимо Земли с пунктирным следом траектории',
    ),
    ScenarioBeat(
      beat: OnboardingBeat.wrapAroundWithEntryMarker,
      start: ScenarioTimings.r1WrapStart,
      end: ScenarioTimings.r1WrapEnd,
      summary: 'Уход за край и возврат с маркером входа за 0,5 сек',
    ),
    ScenarioBeat(
      beat: OnboardingBeat.ghostSwipeWithSlowMo,
      start: ScenarioTimings.r1HintStart,
      end: ScenarioTimings.r1HintEnd,
      summary: 'Жест-призрак и замедление 40 % на внешней орбите',
    ),
    ScenarioBeat(
      beat: OnboardingBeat.firstContactStartsRoundTimer,
      start: ScenarioTimings.r1FirstContact,
      summary: 'Первый контакт: снятие замедления, отклик удара, старт таймера',
    ),
  ];

  /// Раунд 2, первые 20 секунд: мультитач двумя пальцами и столкновение
  /// объектов.
  static const List<ScenarioBeat> roundTwo = [
    ScenarioBeat(
      beat: OnboardingBeat.syncDualLaunch,
      start: ScenarioTimings.r2SyncLaunchStart,
      end: ScenarioTimings.r2SyncLaunchEnd,
      summary: 'Синхронный вылет двух астероидов с противоположных краёв',
    ),
    ScenarioBeat(
      beat: OnboardingBeat.midAirCollisionSetup,
      start: ScenarioTimings.r2CollisionStart,
      end: ScenarioTimings.r2CollisionEnd,
      summary: 'Постановка столкновения третьего астероида в воздухе',
    ),
  ];

  /// Раунд 3, заставка (4 секунды до старта таймера): гравитационный
  /// захват Луны. Согласовано с #16: раунд 3 = 55 сек + 4 сек заставка.
  /// (Не `const`: конец дуги связки вычисляется из констант спецификации.)
  static final List<ScenarioBeat> roundThreeIntro = [
    ScenarioBeat(
      beat: OnboardingBeat.moonGravityCaptureIntro,
      start: Duration.zero,
      end: OnboardingTimings.moonIntroDuration,
      summary: 'Луна влетает, цепляется за Землю, выходит на круговую орбиту',
    ),
    ScenarioBeat(
      beat: OnboardingBeat.gravityLinkArc,
      start: Duration(seconds: 2),
      end: Duration(seconds: 2) + OnboardingTimings.gravityLinkArcDuration,
      summary: 'Тонкая голубая дуга гравитационной связки (1 секунда)',
    ),
  ];

  /// Раунд 3, первые 15 секунд после заставки: визуальная связка общей
  /// защиты и демонстрация гравитационной воронки Луны.
  static const List<ScenarioBeat> roundThree = [
    ScenarioBeat(
      beat: OnboardingBeat.sharedHealthPulse,
      start: ScenarioTimings.r3SharedPulseStart,
      end: ScenarioTimings.r3SharedPulseEnd,
      summary: 'Золотистый импульс Земля→Луна, единый контур шкалы из 5 звёзд',
    ),
    ScenarioBeat(
      beat: OnboardingBeat.gravityFunnelDemo,
      start: ScenarioTimings.r3FunnelStart,
      end: ScenarioTimings.r3FunnelEnd,
      summary: 'Ореол Луны заворачивает астероид к её поверхности',
    ),
  ];
}

/// Проигрыватель режиссёрского сценария по игровому времени.
///
/// На каждый [tick] возвращает события, чьё время начала наступило
/// с прошлого тика. События с окном ([ScenarioBeat.end]) дополнительно
/// можно опрашивать через [activeBeatsAt].
class ScenarioPlayer {
  ScenarioPlayer(this.beats);

  final List<ScenarioBeat> beats;

  Duration _elapsed = Duration.zero;
  final Set<OnboardingBeat> _fired = {};

  /// Текущее игровое время сценария.
  Duration get elapsed => _elapsed;

  /// События, уже начавшиеся.
  bool hasFired(OnboardingBeat beat) => _fired.contains(beat);

  /// Продвинуть сценарий на [dt] и вернуть события, время начала которых
  /// наступило (в порядке расписания, каждое — один раз).
  List<ScenarioBeat> tick(Duration dt) {
    _elapsed += dt;
    final due = <ScenarioBeat>[];
    for (final beat in beats) {
      if (_fired.contains(beat.beat)) continue;
      if (beat.start <= _elapsed) {
        _fired.add(beat.beat);
        due.add(beat);
      }
    }
    return List.unmodifiable(due);
  }

  /// Активные в момент [now] события с окном действия.
  List<ScenarioBeat> activeBeatsAt(Duration now) => List.unmodifiable(
        beats.where((b) => b.end != null && b.isActiveAt(now)),
      );
}

/// Мультитач-аккорд раунда 2: вознаграждение, если два астероида
/// отбиты в пределах 0,3 секунды друг от друга.
///
/// Успешная пара даёт яркие энергетические росчерки свайпов и
/// гармоничный двойной звуковой аккорд (отклики — по спецификации
/// VFX/SFX, issue #17), закрепляя привычку играть двумя руками.
class MultiTouchChord {
  MultiTouchChord({this.window = OnboardingTimings.multiTouchChordWindow});

  /// Окно между двумя отбиваниями, при котором играет аккорд.
  final Duration window;

  Duration? _lastDeflectAt;

  /// Регистрирует успешное отбивание в момент [at].
  /// Возвращает `true`, если пара сложилась в аккорд.
  bool registerDeflect(Duration at) {
    final prev = _lastDeflectAt;
    if (prev != null && at >= prev && at - prev <= window) {
      _lastDeflectAt = null; // пара сыграна, третий удар не цепляется
      return true;
    }
    _lastDeflectAt = at;
    return false;
  }
}

/// Исход защиты Луны в раунде 3.
class MoonOutcome {
  const MoonOutcome({
    required this.beat,
    required this.starsLost,
    required this.leavesCrater,
    required this.earthDegradesSync,
    required this.protectiveRipple,
  });

  /// Событие для слоя представления ([OnboardingBeat.moonImpactCrater]
  /// или [OnboardingBeat.moonDefendedRipple]).
  final OnboardingBeat beat;

  /// Списанные звёзды из общей шкалы Земля–Луна (5 звёзд, шаг 1/4 —
  /// по UX-спецификации #15 и балансу #7).
  final int starsLost;

  /// На поверхности Луны остаётся дымящийся кратер.
  final bool leavesCrater;

  /// Земля синхронно теряет часть зелёного покрова.
  final bool earthDegradesSync;

  /// По поверхности Луны проходит лёгкая защитная рябь.
  final bool protectiveRipple;
}

/// Закрепление уязвимости спутника в раунде 3.
///
/// Шкала в 5 звёзд общая для системы Земля–Луна (US-03, issue #6;
/// UX-спецификация, issue #15): попадание в Луну списывает 1 звезду
/// из общего пула, оставляет кратер и синхронно деградирует Землю.
class MoonOnboarding {
  /// Звёзд в общей шкале системы Земля–Луна.
  static const int sharedPoolStars = 5;

  /// Штраф за попадание астероида в Луну (1 звезда = 4 четверти
  /// по таблице урона #7/#15).
  static const int moonImpactPenaltyStars = 1;

  /// Игрок вовремя отбил астероид от Луны — защитная рябь.
  MoonOutcome onMoonDefended() => const MoonOutcome(
        beat: OnboardingBeat.moonDefendedRipple,
        starsLost: 0,
        leavesCrater: false,
        earthDegradesSync: false,
        protectiveRipple: true,
      );

  /// Астероид попал в Луну — кратер, −1 звезда из общей шкалы,
  /// синхронная деградация Земли.
  MoonOutcome onMoonImpact() => const MoonOutcome(
        beat: OnboardingBeat.moonImpactCrater,
        starsLost: moonImpactPenaltyStars,
        leavesCrater: true,
        earthDegradesSync: true,
        protectiveRipple: false,
      );
}
