/// Физика полёта астероида раунда 1 (US-01, issue #4).
///
/// Чистая модель без UI: нормированная система координат поля
/// (высота поля = 1.0, ширина = [AsteroidSim.fieldAspect]), время
/// в секундах. Гравитация Земли искривляет вектор скорости, модуль
/// скорости задаёт темп раунда ([SpeedGrowth], issue #16), пространство
/// замкнуто: вылет за край — мгновенное появление с противоположной
/// стороны с сохранением вектора и скорости.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../pacing/round_pacing.dart';

/// Край поля для прогноза выхода/возврата объекта.
enum FieldEdge { left, right, top, bottom }

/// Результат одного шага интеграции [AsteroidSim.update].
typedef SimStep = ({bool wrapped, bool impact});

/// Прогноз выхода астероида за край поля по прямой (без учёта гравитации).
class ExitPrediction {
  const ExitPrediction({
    required this.exitEdge,
    required this.entryPoint,
    required this.timeToExitSec,
  });

  /// Край, за который астероид вылетает.
  final FieldEdge exitEdge;

  /// Точка появления на противоположном краю (для маркера входа, #20).
  final Offset entryPoint;

  /// Через сколько секунд произойдёт выход.
  final double timeToExitSec;

  /// Край, на котором появится маркер входа.
  FieldEdge get entryEdge => switch (exitEdge) {
        FieldEdge.left => FieldEdge.right,
        FieldEdge.right => FieldEdge.left,
        FieldEdge.top => FieldEdge.bottom,
        FieldEdge.bottom => FieldEdge.top,
      };
}

/// Симуляция одиночного астероида в замкнутом поле с гравитацией Земли.
class AsteroidSim {
  AsteroidSim({
    required this.fieldAspect,
    required this.earthRadius,
    required this.asteroidRadius,
    required this.baseSpeed,
    required this.growth,
    math.Random? rng,
  })  : _rng = rng ?? math.Random(),
        earthCenter = Offset(fieldAspect / 2, 0.5),
        position = Offset(fieldAspect / 2, 0.5),
        velocity = Offset.zero;

  /// Ширина поля в единицах высоты (высота поля = 1.0).
  final double fieldAspect;

  /// Радиус Земли в единицах поля.
  final double earthRadius;

  /// Радиус астероида в единицах поля.
  final double asteroidRadius;

  /// Базовая скорость (множитель темпа 1.0), единиц поля в секунду.
  final double baseSpeed;

  /// Модель прироста скорости раунда (issue #16).
  final SpeedGrowth growth;

  final math.Random _rng;

  /// Гравитационный параметр Земли (ед. поля³/с²): на дистанции ~0,5
  /// высоты поля ускорение заметно искривляет траекторию в дугу,
  /// но не срывает касательный пролёт в мгновенное падение.
  static const double gravityMu = 0.0165;

  /// Центр Земли (середина поля).
  final Offset earthCenter;

  /// Позиция астероида в единицах поля.
  Offset position;

  /// Вектор скорости (единицы поля в секунду).
  Offset velocity;

  /// Игровое время жизни астероида, секунды (для темпа скорости).
  double elapsed = 0;

  /// Текущий модуль скорости.
  double get speed => velocity.distance;

  /// Дистанция до центра Земли.
  double get distanceToEarth => (position - earthCenter).distance;

  /// Целевой модуль скорости по темпу раунда на текущей отметке времени.
  double get targetSpeed => baseSpeed * growth.multiplierAt(elapsed);

  /// Точка удара на диске Земли в единичном круге (для [PlanetHealth]).
  Offset get impactPointOnDisc {
    final d = position - earthCenter;
    final len = d.distance;
    if (len < 1e-9) return const Offset(0, -1);
    return d / len;
  }

  /// Спавн за случайным краем поля курсом к Земле с касательным
  /// смещением 15–40°: первый пролёт — дуга мимо планеты, а не таран.
  void spawn() {
    final edge = _rng.nextInt(4);
    final along = 0.15 + _rng.nextDouble() * 0.7;
    final m = asteroidRadius * 2;
    position = switch (edge) {
      0 => Offset(-m, along), // левый край
      1 => Offset(fieldAspect + m, along), // правый край
      2 => Offset(along * fieldAspect, -m), // верхний край
      _ => Offset(along * fieldAspect, 1 + m), // нижний край
    };
    final toEarth = earthCenter - position;
    final baseAngle = math.atan2(toEarth.dy, toEarth.dx);
    final sign = _rng.nextBool() ? 1.0 : -1.0;
    final offsetAngle = sign * (15 + _rng.nextDouble() * 25) * math.pi / 180;
    final angle = baseAngle + offsetAngle;
    velocity = Offset(math.cos(angle), math.sin(angle)) * targetSpeed;
  }

  /// Сброс часов и новый заход (рестарт раунда).
  void restart() {
    elapsed = 0;
    spawn();
  }

  /// Шаг интеграции на [dt] секунд.
  ///
  /// Возвращает флаги шага: [SimStep.wrapped] — был переход через край,
  /// [SimStep.impact] — астероид достиг поверхности Земли (респавн и
  /// урон — ответственность контроллера раунда).
  SimStep update(double dt) {
    if (dt <= 0) return (wrapped: false, impact: false);
    elapsed += dt;

    // Гравитация Земли: ускорение к центру ~ 1/d².
    final toEarth = earthCenter - position;
    final d = math.max(toEarth.distance, earthRadius * 0.6);
    velocity += (toEarth / d) * (gravityMu / (d * d)) * dt;

    // Темп раунда задаёт модуль скорости, гравитация — направление:
    // скорость ступенчато растёт по [SpeedGrowth], не ломая дугу полёта.
    velocity = _normalized(velocity) * targetSpeed;
    position += velocity * dt;

    // Замкнутое пространство: вылет за край — появление с противоположной
    // стороны с сохранением вектора и скорости (US-01).
    var wrapped = false;
    final m = asteroidRadius;
    if (position.dx < -m) {
      position = Offset(position.dx + fieldAspect + 2 * m, position.dy);
      wrapped = true;
    } else if (position.dx > fieldAspect + m) {
      position = Offset(position.dx - fieldAspect - 2 * m, position.dy);
      wrapped = true;
    }
    if (position.dy < -m) {
      position = Offset(position.dx, position.dy + 1 + 2 * m);
      wrapped = true;
    } else if (position.dy > 1 + m) {
      position = Offset(position.dx, position.dy - 1 - 2 * m);
      wrapped = true;
    }

    final impact = distanceToEarth <= earthRadius + asteroidRadius * 0.5;
    return (wrapped: wrapped, impact: impact);
  }

  /// Отбивание: объект не разрушается, а меняет направление полёта
  /// в сторону движения пальца; модуль скорости сохраняется.
  bool deflect(Offset direction) {
    if (direction.distance < 1e-6) return false;
    velocity = _normalized(direction) * speed;
    return true;
  }

  /// Прогноз выхода за край по прямой на горизонте [horizonSec] секунд —
  /// для маркеров входа на противоположном краю (онбординг #20, правило 3).
  ExitPrediction? predictExit(double horizonSec) {
    final v = velocity;
    if (v.distance < 1e-6) return null;
    final m = asteroidRadius;
    var bestT = double.infinity;
    FieldEdge? bestEdge;
    if (v.dx > 0) {
      final t = (fieldAspect + m - position.dx) / v.dx;
      if (t >= 0 && t < bestT) {
        bestT = t;
        bestEdge = FieldEdge.right;
      }
    } else if (v.dx < 0) {
      final t = (-m - position.dx) / v.dx;
      if (t >= 0 && t < bestT) {
        bestT = t;
        bestEdge = FieldEdge.left;
      }
    }
    if (v.dy > 0) {
      final t = (1 + m - position.dy) / v.dy;
      if (t >= 0 && t < bestT) {
        bestT = t;
        bestEdge = FieldEdge.bottom;
      }
    } else if (v.dy < 0) {
      final t = (-m - position.dy) / v.dy;
      if (t >= 0 && t < bestT) {
        bestT = t;
        bestEdge = FieldEdge.top;
      }
    }
    if (bestEdge == null || bestT > horizonSec) return null;
    final exitPoint = position + v * bestT;
    final entryPoint = switch (bestEdge) {
      FieldEdge.right => Offset(-m, exitPoint.dy),
      FieldEdge.left => Offset(fieldAspect + m, exitPoint.dy),
      FieldEdge.top => Offset(exitPoint.dx, 1 + m),
      FieldEdge.bottom => Offset(exitPoint.dx, -m),
    };
    return ExitPrediction(
      exitEdge: bestEdge,
      entryPoint: entryPoint,
      timeToExitSec: bestT,
    );
  }

  static Offset _normalized(Offset v) {
    final len = v.distance;
    if (len < 1e-9) return const Offset(1, 0);
    return v / len;
  }
}
