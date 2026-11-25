import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/health/planet_health.dart';

/// Индикатор дробных жизней: ряд из 5 звёзд с радиальным заполнением
/// по 4 секторам (90° на четверть) — issue #15, §1.
///
/// Геометрия и безопасная зона (docs/ux-health-indicator.md):
/// звезда 40 pt (требование ≥ 36–44), зазор 10 pt (8–12),
/// отступ от края 28 pt (≥ 24–32).
class LivesIndicator extends StatefulWidget {
  const LivesIndicator({super.key, required this.health});

  final PlanetHealth health;

  /// Отступ блока звёзд от края экрана (требование: не менее 24–32 pt).
  static const double safeZonePadding = 28.0;

  /// Размер одной звезды (требование: не менее 36–44 pt).
  static const double starSize = 40.0;

  /// Расстояние между звёздами (требование: 8–12 pt).
  static const double starSpacing = 10.0;

  @override
  State<LivesIndicator> createState() => _LivesIndicatorState();
}

class _LivesIndicatorState extends State<LivesIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _criticalPulse;
  late final AnimationController _shake;

  /// Активные эффекты на звёздах (вспышки, отлетающие сектора, лечение).
  final List<_StarFx> _fx = <_StarFx>[];

  late int _lastQuarters;

  @override
  void initState() {
    super.initState();
    _lastQuarters = widget.health.quarters;
    _criticalPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    widget.health.addListener(_onHealthChanged);
  }

  @override
  void dispose() {
    widget.health.removeListener(_onHealthChanged);
    for (final fx in _fx) {
      fx.controller.dispose();
    }
    _criticalPulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onHealthChanged() {
    final int now = widget.health.quarters;
    final int delta = now - _lastQuarters;
    if (delta != 0) {
      final transitions = _sectorTransitions(_lastQuarters, now);
      if (delta < 0) {
        if (delta <= -PlanetHealth.quartersPerStar) {
          // Потеря 1 или 1,5 звезды: сотрясение + красная вспышка 0,3 с.
          _shake.forward(from: 0);
          for (final t in transitions) {
            _addFx(t, _FxKind.heavyLoss);
          }
        } else {
          // Потеря 1/4: белая вспышка сектора и осыпающийся осколок.
          for (final t in transitions) {
            _addFx(t, _FxKind.fragmentLoss);
          }
        }
      } else {
        // Восстановление: мягкая зелёно-золотая вспышка заполнения.
        // Задержка 250 мс — импульс от капсулы летит к индикатору
        // (оверлей в GameScreen) и «долетает» до шкалы.
        for (final t in transitions) {
          _addFx(t, _FxKind.heal, delay: const Duration(milliseconds: 250));
        }
      }
    }
    _lastQuarters = now;
    if (mounted) setState(() {});
  }

  /// Список изменившихся секторов между двумя значениями шкалы.
  ///
  /// Возвращает пары (звезда, сектор): сектор 0 — верхний, далее по
  /// часовой стрелке (4 сектора × 90°).
  List<({int star, int sector})> _sectorTransitions(int from, int to) {
    final result = <({int star, int sector})>[];
    for (var star = 0; star < PlanetHealth.maxStars; star++) {
      final oldFill = (from - star * PlanetHealth.quartersPerStar)
          .clamp(0, PlanetHealth.quartersPerStar);
      final newFill = (to - star * PlanetHealth.quartersPerStar)
          .clamp(0, PlanetHealth.quartersPerStar);
      if (newFill < oldFill) {
        for (var s = oldFill - 1; s >= newFill; s--) {
          result.add((star: star, sector: s));
        }
      } else if (newFill > oldFill) {
        for (var s = oldFill; s < newFill; s++) {
          result.add((star: star, sector: s));
        }
      }
    }
    return result;
  }

  void _addFx(
    ({int star, int sector}) target,
    _FxKind kind, {
    Duration delay = Duration.zero,
  }) {
    final controller = AnimationController(
      vsync: this,
      duration: switch (kind) {
        _FxKind.fragmentLoss => const Duration(milliseconds: 900),
        _FxKind.heavyLoss => const Duration(milliseconds: 600),
        _FxKind.heal => const Duration(milliseconds: 700),
      },
    );
    final fx = _StarFx(
      star: target.star,
      sector: target.sector,
      kind: kind,
      controller: controller,
      delay: delay,
    );
    _fx.add(fx);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        _fx.remove(fx);
        if (mounted) setState(() {});
      }
    });
    if (delay == Duration.zero) {
      controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted && _fx.contains(fx)) controller.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final critical = widget.health.isCritical;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_criticalPulse, _shake]),
      builder: (context, _) {
        final shakeT = _shake.value;
        final shakeDx = shakeT == 0
            ? 0.0
            : math.sin(shakeT * math.pi * 6) * 4 * (1 - shakeT);
        return Transform.translate(
          offset: Offset(shakeDx, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < PlanetHealth.maxStars; i++) ...<Widget>[
                if (i > 0)
                  const SizedBox(width: LivesIndicator.starSpacing),
                _buildStar(i, critical),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStar(int index, bool critical) {
    final fill = widget.health.starFill(index);
    final starFx = _fx.where((f) => f.star == index).toList();
    return SizedBox(
      key: Key('lives-star-$index'),
      width: LivesIndicator.starSize,
      height: LivesIndicator.starSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          CustomPaint(
            size: const Size.square(LivesIndicator.starSize),
            painter: _StarPainter(
              fillQuarters: fill,
              pulse: critical ? _criticalPulse.value : 0,
              critical: critical,
            ),
          ),
          for (final fx in starFx) _buildFxOverlay(fx),
        ],
      ),
    );
  }

  Widget _buildFxOverlay(_StarFx fx) {
    return AnimatedBuilder(
      animation: fx.controller,
      builder: (context, _) => _buildFxOverlayFrame(fx),
    );
  }

  Widget _buildFxOverlayFrame(_StarFx fx) {
    final t = fx.controller.value;
    const size = LivesIndicator.starSize;
    switch (fx.kind) {
      case _FxKind.fragmentLoss:
        // 0.0–0.25: белая вспышка сектора; 0.2–1.0: осколок падает с дымком.
        final flashOpacity = t < 0.25 ? 1.0 : 0.0;
        final fallT = ((t - 0.2) / 0.8).clamp(0.0, 1.0);
        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (flashOpacity > 0)
                CustomPaint(
                  size: const Size.square(size),
                  painter: _SectorPainter(
                    sector: fx.sector,
                    color: Colors.white.withValues(alpha: flashOpacity),
                  ),
                ),
              if (fallT > 0)
                Positioned(
                  left: size / 2 - 8,
                  top: size / 2,
                  child: Transform.translate(
                    offset: Offset(4 * fallT, 46 * fallT),
                    child: Transform.rotate(
                      angle: 0.9 * fallT,
                      child: Opacity(
                        opacity: 1 - fallT,
                        child: CustomPaint(
                          size: const Size(16, 16),
                          painter: _FragmentPainter(smoke: fallT),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      case _FxKind.heavyLoss:
        // Тревожный красный на 0,3 с, затем затухание до тёмного контура
        // (контур дорисовывает базовый слой звезды).
        final opacity = t < 0.5 ? 1.0 : (1 - (t - 0.5) * 2).clamp(0.0, 1.0);
        return IgnorePointer(
          child: CustomPaint(
            size: const Size.square(size),
            painter: _SectorPainter(
              sector: fx.sector,
              color: const Color(0xFFFF3B30).withValues(alpha: opacity),
            ),
          ),
        );
      case _FxKind.heal:
        // Зелёно-золотая вспышка: сектор «нарастает» и мягко гаснет.
        final sweep = (t / 0.6).clamp(0.0, 1.0);
        final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) * 2.5).clamp(0.0, 1.0);
        return IgnorePointer(
          child: CustomPaint(
            size: const Size.square(size),
            painter: _SectorPainter(
              sector: fx.sector,
              sweep: sweep,
              color: const Color(0xFF9BE15D).withValues(alpha: opacity),
            ),
          ),
        );
    }
  }
}

enum _FxKind { fragmentLoss, heavyLoss, heal }

class _StarFx {
  _StarFx({
    required this.star,
    required this.sector,
    required this.kind,
    required this.controller,
    required this.delay,
  });

  final int star;
  final int sector;
  final _FxKind kind;
  final AnimationController controller;
  final Duration delay;
}

/// Путь четырёхлучевой космической звезды (issue #15, §1).
Path starPath(Size size) {
  final center = size.center(Offset.zero);
  final outer = size.shortestSide / 2;
  final inner = outer * 0.28;
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final radius = i.isEven ? outer : inner;
    final angle = -math.pi / 2 + i * math.pi / 4;
    final dx = center.dx + radius * math.cos(angle);
    final dy = center.dy + radius * math.sin(angle);
    if (i == 0) {
      path.moveTo(dx, dy);
    } else {
      path.lineTo(dx, dy);
    }
  }
  path.close();
  return path;
}

/// Базовая отрисовка звезды: золотое радиальное заполнение по секторам,
/// тёмный полупрозрачный контур пустых ячеек, критический ореол.
class _StarPainter extends CustomPainter {
  const _StarPainter({
    required this.fillQuarters,
    required this.pulse,
    required this.critical,
  });

  final int fillQuarters;
  final double pulse;
  final bool critical;

  @override
  void paint(Canvas canvas, Size size) {
    final path = starPath(size);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    // Критическое состояние: ритмичный красно-оранжевый ореол.
    if (critical && fillQuarters > 0) {
      final halo = Paint()
        ..color = Color.lerp(
          const Color(0xFFFF6A00),
          const Color(0xFFFF2D00),
          pulse,
        )!
            .withValues(alpha: 0.35 + 0.4 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, radius * (1.05 + 0.15 * pulse), halo);
    }

    // Пустые сектора: тёмный полупрозрачный контур ячейки.
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1A1A26).withValues(alpha: 0.75),
    );

    // Заполненные сектора: золотое свечение, по 90° на четверть.
    if (fillQuarters > 0) {
      final gold = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFFFE08A),
            const Color(0xFFF5B301),
            const Color(0xFFB97A0A),
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      final sweepRect =
          Rect.fromCircle(center: center, radius: radius * 1.4);
      for (var s = 0; s < fillQuarters; s++) {
        final start = -math.pi / 2 + s * math.pi / 2;
        canvas.drawArc(sweepRect, start, math.pi / 2, true, gold);
      }
    }
    canvas.restore();

    // Границы четвертей: читаемость 3/4 vs 1/4 с первого взгляда.
    final divider = Paint()
      ..color = const Color(0xFF0B0B12).withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var s = 0; s < 4; s++) {
      final angle = -math.pi / 2 + s * math.pi / 2;
      canvas.drawLine(
        center,
        center +
            Offset(
              radius * 1.3 * math.cos(angle),
              radius * 1.3 * math.sin(angle),
            ),
        divider,
      );
    }

    // Обводка звезды.
    canvas.drawPath(
      path,
      Paint()
        ..color = fillQuarters > 0
            ? const Color(0xFFFFD75E)
            : const Color(0xFF4A4A5A).withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) =>
      oldDelegate.fillQuarters != fillQuarters ||
      oldDelegate.pulse != pulse ||
      oldDelegate.critical != critical;
}

/// Отрисовка одного сектора (90°) поверх звезды — для вспышек.
class _SectorPainter extends CustomPainter {
  const _SectorPainter({
    required this.sector,
    required this.color,
    this.sweep = 1.0,
  });

  final int sector;
  final Color color;

  /// Доля сектора по дуге (0..1) — для анимации заполнения при лечении.
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.save();
    canvas.clipPath(starPath(size));
    final start = -math.pi / 2 + sector * math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 1.4),
      start,
      (math.pi / 2) * sweep,
      true,
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SectorPainter oldDelegate) =>
      oldDelegate.sector != sector ||
      oldDelegate.color != color ||
      oldDelegate.sweep != sweep;
}

/// Отлетающий осколок звезды с лёгким дымком (потеря 1/4).
class _FragmentPainter extends CustomPainter {
  const _FragmentPainter({required this.smoke});

  /// 0..1 — стадия падения; дымок рассеивается к концу.
  final double smoke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Дымок: серое полупрозрачное облачко над осколком.
    final smokePaint = Paint()
      ..color = const Color(0xFF9AA0A6)
          .withValues(alpha: 0.45 * (1 - smoke))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(
      center + Offset(-3, -6 - 6 * smoke),
      4.5 + 3 * smoke,
      smokePaint,
    );
    // Осколок: золотой треугольный клин.
    final shard = Path()
      ..moveTo(center.dx, center.dy - 7)
      ..lineTo(center.dx + 6, center.dy + 5)
      ..lineTo(center.dx - 5, center.dy + 4)
      ..close();
    canvas.drawPath(shard, Paint()..color = const Color(0xFFF5B301));
    canvas.drawPath(
      shard,
      Paint()
        ..color = const Color(0xFFFFE08A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_FragmentPainter oldDelegate) => oldDelegate.smoke != smoke;
}
