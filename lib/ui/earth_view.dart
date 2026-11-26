import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/health/impact_kind.dart';
import '../game/health/planet_health.dart';

/// Визуал Земли: 5 стадий разрушения × 4 доли (20-шаговая шкала) с
/// привязкой эффектов к точке удара/посадки — issue #15, §2–3.
///
/// [stormMode] — режим Солнечного шторма (US-08, issue #12): эмиссивные
/// элементы (трещины, лава, очаги пожаров) рисуются с повышенной
/// контрастностью, чтобы игрок не терял ориентир центра гравитации.
class EarthView extends StatefulWidget {
  const EarthView({
    super.key,
    required this.health,
    this.stormMode = false,
  });

  final PlanetHealth health;
  final bool stormMode;

  @override
  State<EarthView> createState() => EarthViewState();
}

class EarthViewState extends State<EarthView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    // Медленная пульсация лавы/пожаров/трещин.
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    widget.health.addListener(_onHealth);
  }

  @override
  void dispose() {
    widget.health.removeListener(_onHealth);
    _ambient.dispose();
    super.dispose();
  }

  void _onHealth() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (context, _) {
        return CustomPaint(
          painter: _EarthPainter(
            health: widget.health,
            stormMode: widget.stormMode,
            time: _ambient.value,
          ),
        );
      },
    );
  }
}

class _EarthPainter extends CustomPainter {
  _EarthPainter({
    required this.health,
    required this.stormMode,
    required this.time,
  });

  final PlanetHealth health;
  final bool stormMode;

  /// Фаза медленной анимации (0..1) для мерцания эмиссивных элементов.
  final double time;

  /// Детерминированные «материки» стадии 1 (единичный круг диска).
  static const List<Offset> _continents = <Offset>[
    Offset(-0.35, -0.25),
    Offset(0.28, -0.05),
    Offset(-0.05, 0.33),
    Offset(0.45, 0.42),
    Offset(-0.5, 0.28),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.92;
    final stage = health.stage;
    final d = health.stageDegradation;

    switch (stage) {
      case EarthStage.greenPlanet:
        _paintGreenPlanet(canvas, center, radius, d);
      case EarthStage.desert:
        _paintDesert(canvas, center, radius, d);
      case EarthStage.fires:
        _paintFires(canvas, center, radius, d);
      case EarthStage.cracked:
        _paintCracked(canvas, center, radius, d);
      case EarthStage.debris:
        _paintDebris(canvas, center, radius);
    }

    if (stage != EarthStage.debris) {
      _paintImpactMarkers(canvas, center, radius);
      _paintAtmosphere(canvas, center, radius, stage, d);
    }
  }

  // --- Стадия 1. Зелёная планета с океанами -----------------------------

  void _paintGreenPlanet(Canvas canvas, Offset c, double r, double d) {
    _disc(
      canvas,
      c,
      r,
      const Color(0xFF1B6CA8),
      const Color(0xFF0B3D91),
    );
    // Материки желтеют по мере деградации.
    final landColor = Color.lerp(
      const Color(0xFF2E9E4F),
      const Color(0xFFC9B458),
      d,
    )!;
    for (final p in _continents) {
      canvas.drawCircle(
        c + p * r,
        r * 0.24,
        Paint()..color = landColor,
      );
    }
    // Океаны мелеют: песчаная сушь разрастается от точек удара.
    for (final e in _damageEvents()) {
      final p = c + e.position * r * 0.8;
      canvas.drawCircle(
        p,
        r * 0.16 * (0.4 + d),
        Paint()
          ..color = const Color(0xFFD8C58D).withValues(alpha: 0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  // --- Стадия 2. Пустыня -------------------------------------------------

  void _paintDesert(Canvas canvas, Offset c, double r, double d) {
    _disc(canvas, c, r, const Color(0xFFB36A3C), const Color(0xFF7A4026));
    // Тлеющие кратеры, очаги пожаров и столбы дыма с каждой четвертью.
    final spots = _damageEvents();
    for (var i = 0; i < spots.length; i++) {
      final p = c + spots[i].position * r * 0.8;
      _crater(canvas, p, r * 0.09);
      if (d > 0.2) {
        _fire(canvas, p, r * 0.05, intensity: d);
        _smokeColumn(canvas, p, r, d, seed: i);
      }
    }
  }

  // --- Стадия 3. Пожары и извержения -------------------------------------

  void _paintFires(Canvas canvas, Offset c, double r, double d) {
    _disc(canvas, c, r, const Color(0xFF5A2A1A), const Color(0xFF2E1408));
    final flicker = 0.75 + 0.25 * math.sin(2 * math.pi * time);
    // Лавовые реки: свечение усиливается с каждой потерянной четвертью.
    final lavaPaint = Paint()
      ..color = const Color(0xFFFF7A1A)
          .withValues(alpha: (0.45 + 0.55 * d) * flicker)
      ..strokeWidth = r * 0.045
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (stormMode) {
      lavaPaint
        ..strokeWidth = r * 0.06
        ..color = const Color(0xFFFFB347).withValues(alpha: flicker);
    }
    for (var i = 0; i < 3 + (d * 3).round(); i++) {
      final rng = math.Random(41 + i);
      final start = Offset(
        (rng.nextDouble() - 0.5) * 1.2,
        (rng.nextDouble() - 0.5) * 1.2,
      );
      final path = _jaggedPath(c + start * r, c - start * r * 0.6, 5, r * 0.08, rng);
      canvas.drawPath(path, lavaPaint);
    }
    // Пепел затягивает атмосферу.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF6E6E6E).withValues(alpha: 0.12 + 0.3 * d),
    );
  }

  // --- Стадия 4. Треснувшая планета --------------------------------------

  void _paintCracked(Canvas canvas, Offset c, double r, double d) {
    _disc(canvas, c, r, const Color(0xFF3A3340), const Color(0xFF17131C));
    // Чем ближе к 1/4 звезды, тем ослепительнее оранжевое свечение разломов.
    final critical = health.quarters <= PlanetHealth.criticalThreshold;
    final glow = critical
        ? const Color(0xFFFFC966)
        : const Color(0xFFFF8C2E);
    final baseAlpha = stormMode ? 0.95 : 0.55 + 0.4 * d;
    final flicker = 0.85 + 0.15 * math.sin(2 * math.pi * time * 2);
    final crackPaint = Paint()
      ..color = glow.withValues(alpha: baseAlpha * flicker)
      ..strokeWidth = r * (critical ? 0.035 : 0.022)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final sources = _damageEvents();
    final crackCount = 2 + sources.length;
    for (var i = 0; i < crackCount; i++) {
      final rng = math.Random(97 + i * 13);
      // Разломы идут от точек удара; если ударов мало — от края диска.
      final origin = i < sources.length
          ? c + sources[i].position * r * 0.8
          : c +
              Offset(math.cos(i * 1.7), math.sin(i * 1.7)) * r * 0.9;
      final path = _jaggedPath(origin, c, 6, r * 0.1, rng);
      canvas.drawPath(path, crackPaint);
    }
    // Отслаивающиеся фрагменты коры на низкой орбите.
    final detach = 0.04 + 0.08 * d;
    for (var i = 0; i < 3; i++) {
      final angle = i * 2.1 + 0.6;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final chunkCenter = c + dir * r * (1.02 + detach);
      final chunk = Path()
        ..moveTo(chunkCenter.dx - r * 0.07, chunkCenter.dy)
        ..lineTo(chunkCenter.dx, chunkCenter.dy - r * 0.05)
        ..lineTo(chunkCenter.dx + r * 0.08, chunkCenter.dy + r * 0.02)
        ..lineTo(chunkCenter.dx + r * 0.01, chunkCenter.dy + r * 0.07)
        ..close();
      canvas.drawPath(chunk, Paint()..color = const Color(0xFF2A2430));
      canvas.drawPath(
        chunk,
        Paint()
          ..color = glow.withValues(alpha: 0.8 * flicker)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  // --- Стадия 5. Осколки ---------------------------------------------------

  void _paintDebris(Canvas canvas, Offset c, double r) {
    // Вспышка из ядра.
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..color = const Color(0xFFFFD27A).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    // Крупные обломки, разлетающиеся в космос.
    for (var i = 0; i < 7; i++) {
      final rng = math.Random(7 + i * 31);
      final angle = i * (2 * math.pi / 7) + rng.nextDouble() * 0.4;
      final dist = r * (0.55 + rng.nextDouble() * 0.55);
      final chunkCenter = c + Offset(math.cos(angle), math.sin(angle)) * dist;
      final s = r * (0.1 + rng.nextDouble() * 0.12);
      final chunk = Path();
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5 + rng.nextDouble() * 0.5;
        final rr = s * (0.7 + rng.nextDouble() * 0.5);
        final dx = chunkCenter.dx + rr * math.cos(a);
        final dy = chunkCenter.dy + rr * math.sin(a);
        if (k == 0) {
          chunk.moveTo(dx, dy);
        } else {
          chunk.lineTo(dx, dy);
        }
      }
      chunk.close();
      canvas.drawPath(chunk, Paint()..color = const Color(0xFF4A4038));
      canvas.drawPath(
        chunk,
        Paint()
          ..color = const Color(0xFFFF9A3C).withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  // --- Общие элементы ------------------------------------------------------

  /// Метки событий с привязкой к точке удара/посадки (issue #15, §3).
  void _paintImpactMarkers(Canvas canvas, Offset c, double r) {
    for (final e in health.events) {
      if (e.isMoonImpact) continue; // кратер Луны рисует US-03
      final p = c + e.position * r * 0.8;
      if (e.kind == ImpactKind.capsule) {
        // Волна «озеленения» от точки посадки капсулы.
        canvas.drawCircle(
          p,
          r * 0.2,
          Paint()
            ..color = const Color(0xFF4ADE80).withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
        canvas.drawCircle(
          p,
          r * 0.1,
          Paint()..color = const Color(0xFF22C55E).withValues(alpha: 0.85),
        );
      } else if (health.stage != EarthStage.desert) {
        // Кратер в точке удара (в пустыне кратеры рисует стадия).
        _crater(canvas, p, r * (e.kind == ImpactKind.fragment ? 0.06 : 0.1));
      }
    }
  }

  void _paintAtmosphere(
    Canvas canvas,
    Offset c,
    double r,
    EarthStage stage,
    double d,
  ) {
    final Color color;
    switch (stage) {
      case EarthStage.greenPlanet:
        // Голубая атмосфера уплотняется при регенерации.
        color = const Color(0xFF7EC8FF).withValues(alpha: 0.5 - 0.2 * d);
      case EarthStage.desert:
        color = const Color(0xFFD8B98A).withValues(alpha: 0.3);
      case EarthStage.fires:
        color = const Color(0xFF8A8A8A).withValues(alpha: 0.35 + 0.2 * d);
      case EarthStage.cracked:
        color = const Color(0xFF5A4A3A).withValues(alpha: 0.3);
      case EarthStage.debris:
        return;
    }
    canvas.drawCircle(
      c,
      r * 1.06,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  List<PlanetEvent> _damageEvents() => health.events
      .where((e) => e.kind.isDamage && !e.isMoonImpact)
      .toList();

  void _disc(Canvas canvas, Offset c, double r, Color light, Color dark) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: <Color>[light, dark],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _crater(Canvas canvas, Offset p, double radius) {
    canvas.drawCircle(p, radius, Paint()..color = const Color(0xFF201812));
    canvas.drawCircle(
      p,
      radius,
      Paint()
        ..color = const Color(0xFF8A6A4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _fire(Canvas canvas, Offset p, double radius, {required double intensity}) {
    final flicker = 0.7 + 0.3 * math.sin(2 * math.pi * time * 3 + p.dx);
    final alpha = (stormMode ? 0.95 : 0.55 + 0.4 * intensity) * flicker;
    canvas.drawCircle(
      p,
      radius * (1 + 0.3 * flicker),
      Paint()
        ..color = const Color(0xFFFF6A00).withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      p,
      radius * 0.45,
      Paint()..color = const Color(0xFFFFD27A).withValues(alpha: alpha),
    );
  }

  void _smokeColumn(
    Canvas canvas,
    Offset p,
    double r,
    double d, {
    required int seed,
  }) {
    final rng = math.Random(seed * 17 + 5);
    final drift = (rng.nextDouble() - 0.5) * r * 0.1;
    canvas.drawOval(
      Rect.fromCenter(
        center: p + Offset(drift, -r * 0.16),
        width: r * 0.12,
        height: r * (0.22 + 0.12 * d),
      ),
      Paint()
        ..color = const Color(0xFF7A7A7A).withValues(alpha: 0.35 + 0.25 * d)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  /// Ломаная линия от [a] к [b] с [segments] изломами и амплитудой [amp].
  Path _jaggedPath(Offset a, Offset b, int segments, double amp, math.Random rng) {
    final path = Path()..moveTo(a.dx, a.dy);
    final delta = b - a;
    final normal = Offset(-delta.dy, delta.dx) / delta.distance;
    for (var i = 1; i <= segments; i++) {
      final t = i / segments;
      final base = a + delta * t;
      final offset = i == segments ? 0.0 : (rng.nextDouble() - 0.5) * 2 * amp;
      final p = base + normal * offset;
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_EarthPainter oldDelegate) =>
      oldDelegate.health != health ||
      oldDelegate.stormMode != stormMode ||
      oldDelegate.time != time;
}
