/// Контроллер раунда 2 «Множественные угрозы» (US-02, issue #5).
///
/// Связывает физику нескольких астероидов ([AsteroidSim]) со шкалой
/// жизней ([PlanetHealth]): 2–4 объекта на поле по конфигурации
/// [RoundPacing] (issue #16), мультитач-отбивание независимых целей,
/// столкновения астероидов в воздухе ([resolveAsteroidCollision]),
/// плавный рост скорости всех объектов по таймеру раунда, попадание —
/// −1 звезда с привязкой к точке удара (локальный кратер, #15).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../health/impact_kind.dart';
import '../health/planet_health.dart';
import '../pacing/round_pacing.dart';
import '../pacing/rounds.dart';
import '../pacing/threat_type.dart';
import '../round1/asteroid_sim.dart';
import '../round1/round_one_controller.dart' show HitFlash, RoundState;
import 'asteroid_collisions.dart';

export '../round1/round_one_controller.dart' show RoundState;

/// Отслеживаемый астероид раунда 2: симуляция полёта и его след
/// траектории (единицы поля); `null` в следе — разрыв линии
/// (переход через край поля), чтобы след не «прочёсывал» экран.
class TrackedAsteroid {
  TrackedAsteroid(this.sim);

  /// Симуляция полёта объекта.
  final AsteroidSim sim;

  /// След траектории этого астероида.
  final List<Offset?> trail = <Offset?>[];
}

/// Контроллер раунда 2: 2–4 астероида, столкновения, мультитач,
/// общий рост скорости по таймеру раунда.
class RoundTwoController extends ChangeNotifier {
  RoundTwoController({
    required this.health,
    RoundPacing? pacing,
    math.Random? rng,
  })  : pacing = pacing ??
            gameRounds.firstWhere((round) => round.roundNumber == 2),
        _rng = rng ?? math.Random();

  /// Шкала жизней Земли (общая с индикатором и визуалом планеты).
  final PlanetHealth health;

  /// Конфигурация темпа раунда (issue #16, раунд 2).
  final RoundPacing pacing;

  final math.Random _rng;

  /// Радиус астероида в единицах поля (как в раунде 1).
  static const double asteroidRadius = 0.045;

  /// Базовая скорость (множитель темпа 1.0), единиц поля в секунду.
  static const double baseSpeed = 0.24;

  /// Радиус зоны отбивания в радиусах астероида (щедрая зона для детских
  /// пальцев; точные хитбоксы — #18).
  static const double hitRadiusFactor = 2.0;

  /// Минимальная зона отбивания в единицах поля (~60 pt на планшете).
  static const double minHitRadius = 0.08;

  /// Длительность вспышки отбивания, секунды.
  static const double flashDurationSec = 0.25;

  final List<TrackedAsteroid> _asteroids = <TrackedAsteroid>[];
  final List<({Offset position, double age})> _flashes =
      <({Offset position, double age})>[];
  bool _disposed = false;

  double _aspect = 1.6;
  double _earthRadius = 0.25;
  bool _attached = false;

  /// Момент следующего планового подкрепления, секунды от старта раунда.
  double _nextSpawnAtSec = 0;

  /// Состояние раунда.
  RoundState state = RoundState.playing;

  /// Прошедшее реальное время раунда, секунды.
  double roundElapsed = 0;

  /// Число успешных отбиваний за раунд.
  int deflections = 0;

  /// Число попаданий в Землю за раунд.
  int impacts = 0;

  /// Число столкновений астероидов между собой за раунд.
  int collisions = 0;

  /// Астероиды на поле (2–4 по ходу раунда).
  List<TrackedAsteroid> get asteroids =>
      List<TrackedAsteroid>.unmodifiable(_asteroids);

  /// Симуляция доступна после [attachField].
  bool get isAttached => _attached;

  /// Остаток таймера раунда, секунды.
  double get remainingSec =>
      math.max(0, pacing.durationSec - roundElapsed).toDouble();

  /// Доля истёкшего времени раунда (0..1) для индикатора.
  double get elapsedFraction =>
      (roundElapsed / pacing.durationSec).clamp(0.0, 1.0);

  /// Зона отбивания в единицах поля.
  double get hitRadius =>
      math.max(asteroidRadius * hitRadiusFactor, minHitRadius);

  /// Активные вспышки отбивания.
  List<HitFlash> get flashes => List<HitFlash>.unmodifiable(
        _flashes.map(
          (f) => HitFlash(
            position: f.position,
            progress: (f.age / flashDurationSec).clamp(0.0, 1.0),
          ),
        ),
      );

  /// Привязка к размеру поля (вызывается из layout экрана).
  ///
  /// Идемпотентно: повторные вызовы (поворот экрана) не пересоздают
  /// симуляцию посреди раунда.
  void attachField({
    required double aspect,
    required double earthRadius,
  }) {
    if (_attached) return;
    _attached = true;
    _aspect = aspect;
    _earthRadius = earthRadius;
    _spawnInitial();
  }

  /// Стартовый состав раунда по конфигурации (раунд 2: 2 астероида).
  void _spawnInitial() {
    final initial = pacing.initialThreats[ThreatType.asteroid] ?? 0;
    for (var i = 0; i < initial; i++) {
      _spawnAsteroid();
    }
    _nextSpawnAtSec = pacing.spawnIntervalSec?.toDouble() ??
        double.infinity;
  }

  /// Новый астероид за случайным краем поля. Часы объекта сразу
  /// синхронизируются с таймером раунда: скорость всех астероидов
  /// растёт по таймеру раунда, а не по времени жизни объекта (US-02).
  void _spawnAsteroid() {
    final sim = AsteroidSim(
      fieldAspect: _aspect,
      earthRadius: _earthRadius,
      asteroidRadius: asteroidRadius,
      baseSpeed: baseSpeed,
      growth: pacing.speedGrowth,
      rng: _rng,
    );
    sim.elapsed = roundElapsed;
    sim.spawn();
    _asteroids.add(TrackedAsteroid(sim));
  }

  /// Шаг раунда на [dt] секунд реального времени (гоняется Ticker'ом).
  void update(double dt) {
    if (state != RoundState.playing || !_attached || dt <= 0) return;
    roundElapsed += dt;
    if (roundElapsed >= pacing.durationSec) {
      roundElapsed = pacing.durationSec.toDouble();
      state = RoundState.victory;
      _notify();
      return;
    }

    _maybeSpawn();

    // Шаг каждого астероида: общие часы темпа — скорость всех объектов
    // растёт по таймеру раунда (US-02, «скорость плавно увеличивается»).
    for (final tracked in _asteroids) {
      final sim = tracked.sim;
      sim.elapsed = roundElapsed;
      final step = sim.update(dt);
      if (step.wrapped) tracked.trail.add(null);
      tracked.trail.add(sim.position);
      if (tracked.trail.length > 60) {
        tracked.trail.removeRange(0, tracked.trail.length - 60);
      }
    }

    // Столкновения астероидов между собой (US-02, критерий 2).
    for (var i = 0; i < _asteroids.length; i++) {
      for (var j = i + 1; j < _asteroids.length; j++) {
        if (resolveAsteroidCollision(_asteroids[i].sim, _asteroids[j].sim)) {
          collisions++;
        }
      }
    }

    // Попадания в Землю: −1 звезда с привязкой к точке удара (кратер).
    for (var i = _asteroids.length - 1; i >= 0; i--) {
      final sim = _asteroids[i].sim;
      if (sim.distanceToEarth <= sim.earthRadius + sim.asteroidRadius * 0.5) {
        _onEarthImpact(sim);
        _asteroids.removeAt(i);
      }
    }

    // Вспышки стареют.
    for (var i = _flashes.length - 1; i >= 0; i--) {
      final age = _flashes[i].age + dt;
      if (age >= flashDurationSec) {
        _flashes.removeAt(i);
      } else {
        _flashes[i] = (position: _flashes[i].position, age: age);
      }
    }

    _notify();
  }

  /// Спавн по конфигурации раунда 2 (#16): подкрепление каждые
  /// `spawnIntervalSec` до лимита `maxObjectsOnScreen`; если после
  /// попадания на поле меньше стартового состава — слот восполняется
  /// сразу; при достижении лимита спавн откладывается до освобождения
  /// слота. За `stopSpawnBeforeEndSec` до конца — стоп-спавн.
  void _maybeSpawn() {
    final interval = pacing.spawnIntervalSec;
    if (interval == null) return;
    if (roundElapsed >= pacing.stopSpawnAtSec) return;
    if (_asteroids.length < pacing.initialObjectCount) {
      _spawnAsteroid();
      return;
    }
    if (_asteroids.length < pacing.maxObjectsOnScreen &&
        roundElapsed >= _nextSpawnAtSec) {
      _spawnAsteroid();
      _nextSpawnAtSec = roundElapsed + interval;
    }
  }

  /// Ближайший к точке касания астероид в его зоне отбивания.
  ///
  /// Мультитач (US-02, критерий 1): каждый палец ищет свою ближайшую
  /// цель, поэтому пальцы обеих рук отбивают разные астероиды
  /// независимо друг от друга.
  TrackedAsteroid? nearestTarget(Offset fieldPosition) {
    TrackedAsteroid? best;
    var bestDistance = double.infinity;
    for (final tracked in _asteroids) {
      final distance = (fieldPosition - tracked.sim.position).distance;
      if (distance <= hitRadius && distance < bestDistance) {
        best = tracked;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Отбивание по касанию/свайпу ближайшего к [fieldPosition] астероида.
  ///
  /// [direction] — направление движения пальца (для касания без свайпа —
  /// от пальца через центр астероида). Возвращает true, если астероид
  /// отбит.
  bool tryDeflect(Offset fieldPosition, Offset direction) {
    if (state != RoundState.playing || !_attached) return false;
    final target = nearestTarget(fieldPosition);
    if (target == null) return false;
    if (!target.sim.deflect(direction)) return false;
    deflections++;
    _flashes.add((position: target.sim.position, age: 0));
    _notify();
    return true;
  }

  /// Рестарт раунда: шкала жизней, состав поля и таймер сбрасываются.
  void reset() {
    health.reset();
    state = RoundState.playing;
    roundElapsed = 0;
    deflections = 0;
    impacts = 0;
    collisions = 0;
    _asteroids.clear();
    _flashes.clear();
    if (_attached) _spawnInitial();
    _notify();
  }

  void _onEarthImpact(AsteroidSim sim) {
    impacts++;
    health.applyImpact(ImpactKind.asteroid, sim.impactPointOnDisc);
    if (health.isDestroyed) {
      state = RoundState.defeat;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
