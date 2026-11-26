/// Конфигурация темпа и таймингов всех 10 раундов игры
/// «Планетарная защита» (issue #16, `docs/pacing.md`).
///
/// Единственный источник правды о параметрах раундов: длительность,
/// спавн, лимиты объектов, прирост скорости, штормы и капсулы.
/// Значения перенесены из таблицы спецификации один в один.
library;

import 'round_pacing.dart';
import 'threat_type.dart';

/// Все раунды игры в порядке прохождения.
const List<RoundPacing> gameRounds = [
  // Раунд 1. Базовая защита: один астероид, без подкреплений.
  RoundPacing(
    roundNumber: 1,
    name: 'Базовая защита',
    durationSec: 45,
    initialThreats: {ThreatType.asteroid: 1},
    maxObjectsOnScreen: 1,
    speedGrowth: SteppedSpeedGrowth(
      stepPercent: 15,
      stepIntervalSec: 15,
      maxSteps: 3,
    ),
  ),

  // Раунд 2. Множественные угрозы: +1 астероид каждые 18 сек.
  RoundPacing(
    roundNumber: 2,
    name: 'Множественные угрозы',
    durationSec: 50,
    initialThreats: {ThreatType.asteroid: 2},
    spawnIntervalSec: 18,
    maxObjectsOnScreen: 4,
    speedGrowth: LinearSpeedGrowth(toPercent: 35, durationSec: 50),
  ),

  // Раунд 3. Появление Луны: как раунд 2, плюс заставка 4 сек.
  RoundPacing(
    roundNumber: 3,
    name: 'Появление Луны',
    durationSec: 55,
    introSec: 4,
    initialThreats: {ThreatType.asteroid: 2},
    spawnIntervalSec: 18,
    maxObjectsOnScreen: 4,
    speedGrowth: LinearSpeedGrowth(toPercent: 35, durationSec: 55),
  ),

  // Раунд 4. Хрупкие гиганты: +1 гигант каждые 22 сек,
  // лимит 6 объектов с учётом осколков.
  RoundPacing(
    roundNumber: 4,
    name: 'Хрупкие гиганты',
    durationSec: 60,
    initialThreats: {ThreatType.asteroid: 2, ThreatType.giant: 1},
    spawnIntervalSec: 22,
    spawnTypes: {ThreatType.giant},
    maxObjectsOnScreen: 6,
    speedGrowth: LinearSpeedGrowth(toPercent: 40, durationSec: 60),
  ),

  // Раунд 5. Спасательные капсулы: подкрепления каждые 18 сек,
  // капсулы на 24-й и 48-й секундах.
  RoundPacing(
    roundNumber: 5,
    name: 'Спасательные капсулы',
    durationSec: 65,
    initialThreats: {ThreatType.asteroid: 2, ThreatType.giant: 1},
    spawnIntervalSec: 18,
    spawnTypes: {ThreatType.asteroid, ThreatType.giant},
    maxObjectsOnScreen: 6,
    speedGrowth: LinearSpeedGrowth(toPercent: 40, durationSec: 65),
    capsuleSpawnsSec: [24, 48],
  ),

  // Раунд 6. Маневрирующие зонды: подкрепления каждые 16 сек,
  // не более 2 зондов одновременно; пауза наведения 1,2 → 0,7 сек.
  RoundPacing(
    roundNumber: 6,
    name: 'Маневрирующие зонды',
    durationSec: 70,
    initialThreats: {ThreatType.asteroid: 2, ThreatType.probe: 1},
    spawnIntervalSec: 16,
    spawnTypes: {ThreatType.asteroid, ThreatType.probe},
    maxObjectsOnScreen: 6,
    perTypeCaps: {ThreatType.probe: 2},
    speedGrowth: LinearSpeedGrowth(toPercent: 45, durationSec: 70),
    probeAimPause: ProbeAimPause(startSec: 1.2, endSec: 0.7),
    capsuleSpawnsSec: [25, 52],
  ),

  // Раунд 7. Гравитационная аномалия: заставка 3 сек, подкрепления
  // каждые 15 сек, аномалия меняет позицию каждые 25 сек.
  RoundPacing(
    roundNumber: 7,
    name: 'Гравитационная аномалия',
    durationSec: 75,
    introSec: 3,
    initialThreats: {
      ThreatType.asteroid: 2,
      ThreatType.giant: 1,
      ThreatType.probe: 1,
    },
    spawnIntervalSec: 15,
    spawnTypes: {ThreatType.asteroid, ThreatType.giant, ThreatType.probe},
    maxObjectsOnScreen: 7,
    speedGrowth: LinearSpeedGrowth(toPercent: 45, durationSec: 75),
    anomalyRepositionIntervalSec: 25,
    anomalySpeedBursts: true,
    capsuleSpawnsSec: [20, 42, 60],
  ),

  // Раунд 8. Солнечный шторм: старт — 3 угрозы разных типов,
  // штормы с предупреждениями на 22-й и 50-й секундах (вспышка 4,5 сек),
  // капсулы — строго в окнах между штормами.
  RoundPacing(
    roundNumber: 8,
    name: 'Солнечный шторм',
    durationSec: 75,
    initialThreats: {
      ThreatType.asteroid: 1,
      ThreatType.giant: 1,
      ThreatType.probe: 1,
    },
    spawnIntervalSec: 15,
    spawnTypes: {ThreatType.asteroid, ThreatType.giant, ThreatType.probe},
    maxObjectsOnScreen: 7,
    speedGrowth: LinearSpeedGrowth(toPercent: 50, durationSec: 75),
    storms: [
      StormWindow(warningAtSec: 22, flashDurationSec: 4.5),
      StormWindow(warningAtSec: 50, flashDurationSec: 4.5),
    ],
    capsuleSpawnsSec: [16, 38, 62],
  ),

  // Раунд 9. Тяжёлые болиды: +1 болид каждые 28 сек
  // (не более 2 болидов, до 7 объектов суммарно).
  RoundPacing(
    roundNumber: 9,
    name: 'Тяжёлые болиды',
    durationSec: 80,
    initialThreats: {ThreatType.asteroid: 2, ThreatType.heavyBolide: 1},
    spawnIntervalSec: 28,
    spawnTypes: {ThreatType.heavyBolide},
    maxObjectsOnScreen: 7,
    perTypeCaps: {ThreatType.heavyBolide: 2},
    speedGrowth: LinearSpeedGrowth(toPercent: 50, durationSec: 80),
    storms: [
      StormWindow(warningAtSec: 25, flashDurationSec: 5),
      StormWindow(warningAtSec: 55, flashDurationSec: 5),
    ],
    capsuleSpawnsSec: [18, 44, 66],
  ),

  // Раунд 10. Пояс астероидов: заставка 4 сек, волны каждые 13–15 сек
  // со всеми типами угроз, рост скорости до +60% к финальным 15 секундам.
  RoundPacing(
    roundNumber: 10,
    name: 'Пояс астероидов',
    durationSec: 90,
    introSec: 4,
    initialThreats: {ThreatType.asteroid: 2, ThreatType.probe: 1},
    spawnIntervalSec: 13,
    spawnIntervalMaxSec: 15,
    spawnTypes: {
      ThreatType.asteroid,
      ThreatType.giant,
      ThreatType.probe,
      ThreatType.heavyBolide,
    },
    maxObjectsOnScreen: 8,
    // +60% достигается к началу финальных 15 секунд (к 75-й секунде).
    speedGrowth: LinearSpeedGrowth(toPercent: 60, durationSec: 75),
    storms: [
      StormWindow(warningAtSec: 20, flashDurationSec: 5),
      StormWindow(warningAtSec: 48, flashDurationSec: 5),
      StormWindow(warningAtSec: 72, flashDurationSec: 5),
    ],
    capsuleSpawnsSec: [15, 36, 58, 78],
  ),
];
