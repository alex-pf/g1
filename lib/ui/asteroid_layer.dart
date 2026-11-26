/// Отрисовка астероида и эффектов раунда 1 (US-01, issue #4).
///
/// Слой поверх поля: скальный полигон с вращением, пунктирный след
/// траектории (онбординг #20, правило 3), вспышка отбивания (лёгкая
/// версия «резкого удара» из docs/vfx-sfx.md) и маркер входа на краю
/// за 0,5 секунды до возврата объекта.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/round1/round_one_controller.dart';

/// Слой астероида: рисуется на весь игровой field (Positioned.fill).
///
/// Родитель перестраивает слой каждый кадр (Ticker → notify контроллера),
/// поэтому анимация вращения и вспышек идёт за счёт перерисовки.
class AsteroidLayer extends StatelessWidget {
  const AsteroidLayer({super.key, required this.controller});

  final RoundOneController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _AsteroidPainter(controller),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AsteroidPainter extends CustomPainter {
  _AsteroidPainter(this.controller);

  final RoundOneController controller;

  /// Вершины скального полигона (детерминированная «каменная» форма,
  /// радиусы в долях радиуса астероида).
  static const List<double> _rockRadii = <double>[
    1.0, 0.82, 0.95, 0.78, 1.0, 0.86, 0.92, 0.8, 0.97,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isAttached) return;
    final sim = controller.sim;
    // Поле: высота = 1.0 → пикселей в единице поля = высота экрана.
    final unit = size.height;
    Offset toPx(Offset p) => Offset(p.dx * unit, p.dy * unit);

    _paintTrail(canvas, toPx);
    _paintEntryMarker(canvas, toPx, unit);
    if (controller.state == RoundState.playing) {
      _paintAsteroid(canvas, toPx(sim.position), sim.asteroidRadius * unit);
    }
    _paintFlashes(canvas, toPx, unit);
  }

  /// Пунктирный след траектории: точки за шаг, разрыв (`null`) на
  /// переходе через край, чтобы след не «прочёсывал» экран.
  void _paintTrail(Canvas canvas, Offset Function(Offset) toPx) {
    final trail = controller.trail;
    if (trail.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFF9FB6DA).withValues(alpha: 0.45)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    Offset? prev;
    var dashPhase = 0.0;
    for (final point in trail) {
      if (point == null) {
        prev = null;
        dashPhase = 0;
        continue;
      }
      final current = toPx(point);
      if (prev != null) {
        dashPhase = _dashedLine(canvas, prev, current, paint, dashPhase);
      }
      prev = current;
    }
  }

  /// Рисует пунктир от [a] к [b]; возвращает фазу для стыковки штрихов
  /// между сегментами. Штрих 7 px, пропуск 7 px.
  double _dashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double startPhase,
  ) {
    const dash = 7.0;
    const gap = 7.0;
    final total = (b - a).distance;
    if (total < 1e-6) return startPhase;
    final dir = (b - a) / total;
    var t = -startPhase;
    while (t < total) {
      final from = math.max(t, 0.0);
      final to = math.min(t + dash, total);
      if (to > from) {
        canvas.drawLine(a + dir * from, a + dir * to, paint);
      }
      t += dash + gap;
    }
    final tail = total - (t - dash - gap);
    return tail < dash ? tail : tail % (dash + gap);
  }

  /// Скальный астероид: неправильный полигон с вращением, кратеры.
  void _paintAsteroid(Canvas canvas, Offset center, double radius) {
    final angle = controller.sim.elapsed * 1.4; // вращение ~0,22 об/с
    final path = Path();
    for (var i = 0; i < _rockRadii.length; i++) {
      final a = angle + i * 2 * math.pi / _rockRadii.length;
      final r = radius * _rockRadii[i];
      final p = center + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: const <Color>[Color(0xFF9C8E7E), Color(0xFF4E443B)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2E2823)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Кратеры на теле (вращаются вместе с астероидом).
    final craterPaint = Paint()..color = const Color(0xFF38302A);
    for (final (double da, double dist, double rr) in <(double, double, double)>[
      (0.6, 0.42, 0.2),
      (2.5, 0.5, 0.14),
      (4.4, 0.36, 0.16),
    ]) {
      final p = center +
          Offset(math.cos(angle + da), math.sin(angle + da)) * radius * dist;
      canvas.drawCircle(p, radius * rr, craterPaint);
    }
  }

  /// Маркер входа (онбординг #20, правило 3): пульсирующий шеврон на
  /// краю за 0,5 с до возврата астероида с противоположной стороны.
  void _paintEntryMarker(
    Canvas canvas,
    Offset Function(Offset) toPx,
    double unit,
  ) {
    final prediction = controller.exitPrediction;
    if (prediction == null) return;
    final sim = controller.sim;
    // Точка появления лежит чуть за краем — втягиваем маркер на поле.
    final inset = 0.035;
    final p = Offset(
      prediction.entryPoint.dx.clamp(inset, sim.fieldAspect - inset),
      prediction.entryPoint.dy.clamp(inset, 1 - inset),
    );
    final center = toPx(p);
    final pulse =
        0.5 + 0.5 * math.sin(2 * math.pi * 2 * controller.roundElapsed);
    // Направление «внутрь поля» — от края к центру экрана.
    final inward = (Offset(sim.fieldAspect / 2, 0.5) - p);
    final dir = inward.distance < 1e-6
        ? const Offset(1, 0)
        : inward / inward.distance;
    final normal = Offset(-dir.dy, dir.dx);
    final s = unit * 0.035 * (1 + 0.15 * pulse);
    final tip = center + dir * s;
    final back = center - dir * s;
    final chevron = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx * s * 0.7, back.dy + normal.dy * s * 0.7)
      ..lineTo(back.dx - normal.dx * s * 0.7, back.dy - normal.dy * s * 0.7)
      ..close();
    canvas.drawPath(
      chevron,
      Paint()..color = const Color(0xFFFFD75E).withValues(alpha: 0.55 + 0.35 * pulse),
    );
    canvas.drawCircle(
      center,
      s * 1.6,
      Paint()
        ..color = const Color(0xFFFFD75E).withValues(alpha: 0.25 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  /// Вспышки отбивания: белая вспышка в точке контакта и сноп искр
  /// (лёгкая версия «резкого удара», docs/vfx-sfx.md, строка 1).
  void _paintFlashes(Canvas canvas, Offset Function(Offset) toPx, double unit) {
    for (final flash in controller.flashes) {
      final center = toPx(flash.position);
      final t = flash.progress;
      final fade = 1 - t;
      // Белая вспышка, расходящееся кольцо.
      canvas.drawCircle(
        center,
        unit * 0.02 * (1 + t),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        center,
        unit * (0.02 + 0.07 * t),
        Paint()
          ..color = const Color(0xFFFFE08A).withValues(alpha: 0.7 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * fade + 0.5,
      );
      // Сноп мелких искр в стороны от точки контакта.
      final sparkPaint = Paint()
        ..color = const Color(0xFFFFF3C4).withValues(alpha: 0.85 * fade)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + 0.35;
        final dir = Offset(math.cos(a), math.sin(a));
        final from = center + dir * unit * 0.012;
        final to = center + dir * unit * (0.02 + 0.055 * t);
        canvas.drawLine(from, to, sparkPaint);
      }
    }
  }

  @override
  // Контроллер мутирует каждый кадр (Ticker → notify), а слой
  // перестраивается родителем — перерисовываем всегда.
  bool shouldRepaint(_AsteroidPainter oldDelegate) => true;
}
