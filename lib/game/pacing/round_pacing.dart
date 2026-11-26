/// Модель конфигурации темпа одного раунда игры «Планетарная защита».
///
/// Все значения — по спецификации темпа и таймингов (issue #16,
/// `docs/pacing.md`). Конфигурация лежит в [RoundPacing]-константах
/// (`rounds.dart`) и нигде больше: код игры читает параметры только
/// отсюда.
library;

import 'threat_type.dart';

/// Пауза наведения маневрирующего зонда после отбивания (раунд 6).
///
/// Согласовано с US-06 (issue #10): пауза сокращается по ходу раунда.
class ProbeAimPause {
  const ProbeAimPause({required this.startSec, required this.endSec});

  /// Пауза наведения в начале раунда, секунды.
  final double startSec;

  /// Пауза наведения к концу раунда, секунды.
  final double endSec;
}

/// Окно солнечного шторма (US-08, issue #12).
class StormWindow {
  const StormWindow({required this.warningAtSec, required this.flashDurationSec});

  /// Момент предупреждения (пульсация края экрана), секунды от старта
  /// раунда.
  final int warningAtSec;

  /// Длительность слепящей вспышки, секунды.
  final double flashDurationSec;

  /// Пауза между предупреждением и началом вспышки (US-08: ~2 секунды).
  static const double warningLeadSec = 2.0;

  /// Момент начала вспышки, секунды от старта раунда.
  double get flashStartSec => warningAtSec + warningLeadSec;

  /// Момент окончания вспышки, секунды от старта раунда.
  double get flashEndSec => flashStartSec + flashDurationSec;
}

/// Модель прироста скорости объектов в течение раунда.
sealed class SpeedGrowth {
  const SpeedGrowth();

  /// Множитель скорости на отметке [elapsedSec] от старта раунда.
  double multiplierAt(double elapsedSec);
}

/// Ступенчатый прирост: +[stepPercent]% каждые [stepIntervalSec] секунд,
/// не более [maxSteps] ступеней (раунд 1).
class SteppedSpeedGrowth extends SpeedGrowth {
  const SteppedSpeedGrowth({
    required this.stepPercent,
    required this.stepIntervalSec,
    required this.maxSteps,
  });

  /// Прирост за одну ступень, в процентах.
  final double stepPercent;

  /// Период ступени, секунды.
  final int stepIntervalSec;

  /// Максимальное число ступеней.
  final int maxSteps;

  @override
  double multiplierAt(double elapsedSec) {
    final steps = (elapsedSec ~/ stepIntervalSec).clamp(0, maxSteps);
    return 1 + stepPercent * steps / 100;
  }
}

/// Плавный прирост до [toPercent]% к концу таймера раунда.
class LinearSpeedGrowth extends SpeedGrowth {
  const LinearSpeedGrowth({required this.toPercent, required this.durationSec});

  /// Целевой прирост к концу раунда, в процентах.
  final double toPercent;

  /// Длительность раунда (таймер), секунды.
  final int durationSec;

  @override
  double multiplierAt(double elapsedSec) {
    final t = (elapsedSec / durationSec).clamp(0.0, 1.0);
    return 1 + toPercent * t / 100;
  }
}

/// Конфигурация темпа и таймингов одного раунда (issue #16).
class RoundPacing {
  const RoundPacing({
    required this.roundNumber,
    required this.name,
    required this.durationSec,
    this.introSec = 0,
    required this.initialThreats,
    this.spawnIntervalSec,
    this.spawnIntervalMaxSec,
    this.spawnTypes = const {ThreatType.asteroid},
    required this.maxObjectsOnScreen,
    this.perTypeCaps = const {},
    required this.speedGrowth,
    this.probeAimPause,
    this.anomalyRepositionIntervalSec,
    this.anomalySpeedBursts = false,
    this.storms = const [],
    this.capsuleSpawnsSec = const [],
  });

  /// Номер раунда (1–10).
  final int roundNumber;

  /// Название раунда из спецификации.
  final String name;

  /// Длительность раунда по таймеру, секунды (без заставки).
  final int durationSec;

  /// Длительность вступительной заставки, секунды (0 — без заставки).
  final int introSec;

  /// Стартовый состав объектов на экране в момент старта раунда.
  final Map<ThreatType, int> initialThreats;

  /// Базовый интервал появления подкреплений, секунды.
  /// `null` — новые объекты не появляются (раунд 1).
  final int? spawnIntervalSec;

  /// Верхняя граница интервала, если он плавающий (раунд 10: 13–15 сек).
  /// `null` — интервал фиксированный.
  final int? spawnIntervalMaxSec;

  /// Типы угроз, которые может порождать спавнер раунда.
  final Set<ThreatType> spawnTypes;

  /// Лимит объектов на экране одновременно (Screen Density Cap):
  /// при достижении лимита спавн откладывается, пока слот не освободится.
  final int maxObjectsOnScreen;

  /// Дополнительные лимиты по типам (например, не более 2 зондов
  /// одновременно в раунде 6 или 2 болидов в раунде 9).
  final Map<ThreatType, int> perTypeCaps;

  /// Модель прироста скорости в раунде.
  final SpeedGrowth speedGrowth;

  /// Динамика паузы наведения зондов (только раунд 6).
  final ProbeAimPause? probeAimPause;

  /// Период смены позиции гравитационной аномалии, секунды
  /// (только раунд 7; `null` — аномалии нет).
  final int? anomalyRepositionIntervalSec;

  /// Резкие выбросы скорости из аномалии (только раунд 7).
  final bool anomalySpeedBursts;

  /// Расписание солнечных штормов (US-08).
  final List<StormWindow> storms;

  /// Моменты появления спасательных капсул, секунды от старта раунда
  /// (US-05).
  final List<int> capsuleSpawnsSec;

  /// Стартовое число объектов на экране.
  int get initialObjectCount =>
      initialThreats.values.fold(0, (sum, count) => sum + count);

  /// Момент, начиная с которого спавн новых угроз прекращается
  /// (стоп-спавн последних [stopSpawnBeforeEndSec] секунд раунда).
  double get stopSpawnAtSec => durationSec - RoundPacing.stopSpawnBeforeEndSec;

  /// Общее правило драматургии финала: за 10 секунд до конца любого
  /// раунда появление новых угроз прекращается.
  static const double stopSpawnBeforeEndSec = 10;

  /// Капсулы не появляются за это число секунд до начала вспышки шторма
  /// и во время самой вспышки.
  static const double capsuleStormBufferSec = 3;

  /// Минимальное «чистое» время (в секундах) с момента появления капсулы
  /// до ближайшего штормового запрета — окно, чтобы расчистить ей
  /// коридор к Земле (по спецификации: 5–6 секунд).
  static const double capsuleMinClearTimeSec = 5;
}
