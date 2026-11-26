/// Контроллер раунда 1 «Базовая защита» (US-01, issue #4).
///
/// Связывает физику ([AsteroidSim]) со шкалой жизней ([PlanetHealth]):
/// таймер раунда и темп скорости — из конфигурации [RoundPacing]
/// (issue #16), попадание астероида — −1 звезда с привязкой к точке
/// удара, slow-mo первого подлёта — механика онбординга (#20).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../health/impact_kind.dart';
import '../health/planet_health.dart';
import '../onboarding/assist_mechanics.dart';
import '../onboarding/onboarding_constants.dart';
import '../pacing/round_pacing.dart';
import '../pacing/rounds.dart';
import 'asteroid_sim.dart';

/// Состояние раунда.
enum RoundState {
  /// Раунд идёт.
  playing,

  /// Таймер истёк, планета уцелела.
  victory,

  /// Шкала жизней на нуле — Земля разрушена.
  defeat,
}

/// Вспышка в точке отбивания (лёгкий VFX «резкого удара», docs/vfx-sfx.md).
class HitFlash {
  const HitFlash({required this.position, required this.progress});

  /// Точка контакта в единицах поля.
  final Offset position;

  /// 0.0 — только что отбит, 1.0 — вспышка погасла.
  final double progress;
}

/// Контроллер раунда 1: один астероид, таймер, урон, победа/поражение.
class RoundOneController extends ChangeNotifier {
  RoundOneController({
    required this.health,
    RoundPacing? pacing,
    math.Random? rng,
  })  : pacing = pacing ??
            gameRounds.firstWhere((round) => round.roundNumber == 1),
        _rng = rng ?? math.Random();

  /// Шкала жизней Земли (общая с индикатором и визуалом планеты).
  final PlanetHealth health;

  /// Конфигурация темпа раунда (issue #16).
  final RoundPacing pacing;

  final math.Random _rng;

  /// Внешняя орбита Земли (в радиусах планеты): её пересечение включает
  /// slow-mo первого подлёта (#20).
  static const double outerOrbitFactor = 2.2;

  /// Радиус зоны отбивания в радиусах астероида (щедрая зона для детских
  /// пальцев; точные хитбоксы — #18).
  static const double hitRadiusFactor = 2.0;

  /// Минимальная зона отбивания в единицах поля (~60 pt на планшете).
  static const double minHitRadius = 0.08;

  /// Длительность вспышки отбивания, секунды.
  static const double flashDurationSec = 0.25;

  AsteroidSim? _sim;
  bool _disposed = false;

  /// Состояние раунда.
  RoundState state = RoundState.playing;

  /// Прошедшее реальное время раунда, секунды (slow-mo его не замедляет).
  double roundElapsed = 0;

  /// Число успешных отбиваний за раунд.
  int deflections = 0;

  /// Число попаданий в Землю за раунд.
  int impacts = 0;

  /// Slow-mo первого подлёта (онбординг #20, правило 1).
  SlowMoAssist slowMo = SlowMoAssist();

  /// След траектории астероида (единицы поля); `null` — разрыв
  /// (переход через край или респавн), чтобы след не «прочёсывал» экран.
  final List<Offset?> trail = <Offset?>[];

  final List<({Offset position, double age})> _flashes =
      <({Offset position, double age})>[];

  /// Прогноз выхода за край для маркера входа (обновляется каждый шаг).
  ExitPrediction? exitPrediction;

  /// Симуляция доступна после [attachField].
  bool get isAttached => _sim != null;

  /// Симуляция полёта (после [attachField]).
  AsteroidSim get sim => _sim!;

  /// Остаток таймера раунда, секунды.
  double get remainingSec =>
      math.max(0, pacing.durationSec - roundElapsed).toDouble();

  /// Доля истёкшего времени раунда (0..1) для индикатора.
  double get elapsedFraction =>
      (roundElapsed / pacing.durationSec).clamp(0.0, 1.0);

  /// Зона отбивания в единицах поля.
  double get hitRadius =>
      math.max(sim.asteroidRadius * hitRadiusFactor, minHitRadius);

  /// Радиус внешней орбиты в единицах поля.
  double get outerOrbitRadius => sim.earthRadius * outerOrbitFactor;

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
    double asteroidRadius = 0.045,
    double baseSpeed = 0.24,
  }) {
    if (_sim != null) return;
    _sim = AsteroidSim(
      fieldAspect: aspect,
      earthRadius: earthRadius,
      asteroidRadius: asteroidRadius,
      baseSpeed: baseSpeed,
      growth: pacing.speedGrowth,
      rng: _rng,
    )..spawn();
  }

  /// Шаг раунда на [dt] секунд реального времени (гоняется Ticker'ом).
  void update(double dt) {
    if (state != RoundState.playing || _sim == null || dt <= 0) return;
    roundElapsed += dt;
    if (roundElapsed >= pacing.durationSec) {
      roundElapsed = pacing.durationSec.toDouble();
      state = RoundState.victory;
      _notify();
      return;
    }

    final step = sim.update(dt * slowMo.timeScale);

    // Slow-mo: пересечение внешней орбиты взводит замедление (#20).
    if (sim.distanceToEarth <= outerOrbitRadius) {
      slowMo.onOuterOrbitCrossed();
    }

    if (step.impact) {
      _onEarthImpact();
    }

    // След траектории: точка за шаг, разрыв на переходе через край.
    if (step.wrapped) trail.add(null);
    trail.add(sim.position);
    if (trail.length > 60) {
      trail.removeRange(0, trail.length - 60);
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

    exitPrediction = sim.predictExit(
      OnboardingTimings.edgeEntryMarkerLead.inMilliseconds / 1000.0,
    );

    _notify();
  }

  /// Отбивание по касанию/свайпу.
  ///
  /// [fieldPosition] — точка касания в единицах поля, [direction] —
  /// направление движения пальца (для касания без свайпа — от пальца
  /// через центр астероида). Возвращает true, если астероид отбит.
  bool tryDeflect(Offset fieldPosition, Offset direction) {
    if (state != RoundState.playing || _sim == null) return false;
    if ((fieldPosition - sim.position).distance > hitRadius) return false;
    if (!sim.deflect(direction)) return false;
    deflections++;
    slowMo.onPlayerContact();
    _flashes.add((position: sim.position, age: 0));
    _notify();
    return true;
  }

  /// Рестарт раунда: шкала жизней и симуляция сбрасываются.
  void reset() {
    health.reset();
    state = RoundState.playing;
    roundElapsed = 0;
    deflections = 0;
    impacts = 0;
    slowMo = SlowMoAssist();
    trail.clear();
    _flashes.clear();
    exitPrediction = null;
    _sim?.restart();
    _notify();
  }

  void _onEarthImpact() {
    // Игрок не успел среагировать — slow-mo повторно взведётся при
    // следующем заходе (#20).
    slowMo.onPlayerMissed();
    impacts++;
    health.applyImpact(ImpactKind.asteroid, sim.impactPointOnDisc);
    if (health.isDestroyed) {
      state = RoundState.defeat;
      trail.clear();
      return;
    }
    // На экране всегда не больше одного объекта (лимит раунда 1, #16):
    // астероид ушёл в Землю — следующий заходит с края поля.
    sim.spawn();
    trail
      ..clear()
      ..add(null);
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
