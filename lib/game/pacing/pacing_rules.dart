/// Правила балансировки темпа (issue #16, `docs/pacing.md`):
///
/// 1. Screen Density Cap — спавн откладывается при заполненном экране.
/// 2. Честные окна капсул — капсулы не появляются за 3 секунды до
///    вспышки шторма и во время неё, а игрок получает минимум
///    5 секунд чистого времени.
/// 3. Стоп-спавн — за 10 секунд до конца раунда новые угрозы не
///    появляются.
///
/// Все функции чистые: принимают конфигурацию раунда и момент времени,
/// не зависят от движка и UI.
library;

import 'round_pacing.dart';
import 'threat_type.dart';

/// Правило 3 — драматургия последних секунд: активен ли стоп-спавн
/// на отметке [elapsedSec] (последние
/// [RoundPacing.stopSpawnBeforeEndSec] секунд раунда).
bool isStopSpawnActive(RoundPacing round, double elapsedSec) =>
    elapsedSec >= round.stopSpawnAtSec;

/// Правило 1 — Screen Density Cap: есть ли на экране слот для нового
/// объекта с учётом общего лимита [RoundPacing.maxObjectsOnScreen]
/// и потиповых лимитов [RoundPacing.perTypeCaps].
bool hasFreeObjectSlot(
  RoundPacing round, {
  required int activeObjects,
  Map<ThreatType, int> activeByType = const {},
  ThreatType? incomingType,
}) {
  if (activeObjects >= round.maxObjectsOnScreen) {
    return false;
  }
  final cap = incomingType == null ? null : round.perTypeCaps[incomingType];
  if (cap != null && (activeByType[incomingType] ?? 0) >= cap) {
    return false;
  }
  return true;
}

/// Может ли спавнер выпустить новую угрозу типа [incomingType]
/// на отметке [elapsedSec]: действуют и Screen Density Cap,
/// и стоп-спавн последних секунд.
///
/// Отклонённый спавн не отменяется, а откладывается — спавнер обязан
/// повторить попытку, когда освободится слот или закончится стоп-спавн.
bool canSpawnThreat(
  RoundPacing round, {
  required double elapsedSec,
  required int activeObjects,
  Map<ThreatType, int> activeByType = const {},
  ThreatType? incomingType,
}) {
  if (isStopSpawnActive(round, elapsedSec)) {
    return false;
  }
  return hasFreeObjectSlot(
    round,
    activeObjects: activeObjects,
    activeByType: activeByType,
    incomingType: incomingType,
  );
}

/// Запрещённая для появления капсулы зона одного шторма:
/// [flashStartSec − buffer, flashEndSec] (правило 2).
bool isCapsuleSpawnForbiddenAt(RoundPacing round, double spawnAtSec) {
  for (final storm in round.storms) {
    final from = storm.flashStartSec - RoundPacing.capsuleStormBufferSec;
    final to = storm.flashEndSec;
    if (spawnAtSec >= from && spawnAtSec <= to) {
      return true;
    }
  }
  return false;
}

/// Чистое время (в секундах) с момента появления капсулы до ближайшей
/// вспышки шторма (с неё начинается потеря видимости); если штормов
/// впереди нет — до конца раунда.
///
/// Буфер в [RoundPacing.capsuleStormBufferSec] секунд перед вспышкой —
/// запрет на *появление* капсулы, но не граница видимости: капсула,
/// появившаяся раньше, всё ещё видна игроку в нормальном контрасте.
double capsuleClearTimeSec(RoundPacing round, double spawnAtSec) {
  var nearest = round.durationSec.toDouble();
  for (final storm in round.storms) {
    if (storm.flashStartSec > spawnAtSec && storm.flashStartSec < nearest) {
      nearest = storm.flashStartSec;
    }
  }
  return nearest - spawnAtSec;
}

/// Правило 2 — честное окно капсулы: момент появления вне запрещённой
/// зоны и с достаточным запасом чистого времени
/// (>= [RoundPacing.capsuleMinClearTimeSec]).
bool isCapsuleWindowFair(RoundPacing round, double spawnAtSec) =>
    !isCapsuleSpawnForbiddenAt(round, spawnAtSec) &&
    capsuleClearTimeSec(round, spawnAtSec) >=
        RoundPacing.capsuleMinClearTimeSec;

/// Множитель скорости объектов на отметке [elapsedSec] согласно
/// модели прироста раунда.
double speedMultiplierAt(RoundPacing round, double elapsedSec) =>
    round.speedGrowth.multiplierAt(elapsedSec);

/// Проверка конфигурации раунда на внутреннюю согласованность.
///
/// Возвращает список нарушений (пустой — конфигурация корректна).
/// Используется тестами и может использоваться при загрузке контента.
List<String> validateRoundPacing(RoundPacing round) {
  final problems = <String>[];
  final label = 'Раунд ${round.roundNumber} (${round.name})';

  if (round.durationSec <= 0) {
    problems.add('$label: длительность должна быть положительной');
  }
  if (round.introSec < 0) {
    problems.add('$label: заставка не может быть отрицательной');
  }
  if (round.maxObjectsOnScreen <= 0) {
    problems.add('$label: лимит объектов должен быть положительным');
  }
  if (round.initialObjectCount > round.maxObjectsOnScreen) {
    problems.add(
      '$label: стартовый состав (${round.initialObjectCount}) '
      'превышает лимит объектов (${round.maxObjectsOnScreen})',
    );
  }
  for (final entry in round.perTypeCaps.entries) {
    if (!round.spawnTypes.contains(entry.key) &&
        !(round.initialThreats.containsKey(entry.key))) {
      problems.add(
        '$label: потиповой лимит для ${entry.key.name} без источника '
        'этого типа в раунде',
      );
    }
  }
  for (final capsuleAt in round.capsuleSpawnsSec) {
    if (capsuleAt < 0 || capsuleAt >= round.durationSec) {
      problems.add(
        '$label: капсула на $capsuleAt сек вне длительности раунда',
      );
    }
    if (isCapsuleSpawnForbiddenAt(round, capsuleAt.toDouble())) {
      problems.add(
        '$label: капсула на $capsuleAt сек попадает в запрещённую зону '
        'шторма (предупреждение + вспышка)',
      );
    } else if (capsuleClearTimeSec(round, capsuleAt.toDouble()) <
        RoundPacing.capsuleMinClearTimeSec) {
      problems.add(
        '$label: капсула на $capsuleAt сек имеет меньше '
        '${RoundPacing.capsuleMinClearTimeSec} сек чистого времени',
      );
    }
  }
  for (final storm in round.storms) {
    if (storm.flashEndSec > round.durationSec) {
      problems.add(
        '$label: вспышка шторма (предупреждение на ${storm.warningAtSec} сек) '
        'заканчивается за пределами раунда',
      );
    }
  }
  return problems;
}
