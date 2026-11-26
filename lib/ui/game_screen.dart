import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/health/impact_kind.dart';
import '../game/health/planet_health.dart';
import 'earth_view.dart';
import 'lives_indicator.dart';

/// Экран игры: Земля в центре, индикатор жизней в верхней левой
/// безопасной зоне (issue #15, §1).
///
/// Отладочная панель внизу — временный контур до появления геймплея
/// раундов (US-01…US-10): позволяет вручную применить урон/лечение и
/// проверить UX-отклики индикатора и переходы стадий Земли.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.health});

  final PlanetHealth health;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GlobalKey _earthKey = GlobalKey();
  final GlobalKey _indicatorKey = GlobalKey();
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    widget.health.addListener(_onHealth);
  }

  @override
  void dispose() {
    widget.health.removeListener(_onHealth);
    super.dispose();
  }

  void _onHealth() {
    final events = widget.health.events;
    if (events.isEmpty) return;
    final last = events.last;
    // От капсулы к индикатору летит зелёно-золотой импульс (issue #15, §1).
    if (last.kind == ImpactKind.capsule && last.quartersDelta > 0) {
      _flyHealImpulse(last.position);
    }
    if (mounted) setState(() {});
  }

  /// Случайная точка в единичном круге диска планеты.
  Offset _randomPointOnDisc() {
    final angle = _rng.nextDouble() * 2 * math.pi;
    final radius = math.sqrt(_rng.nextDouble()) * 0.85;
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  void _applyDebugImpact(ImpactKind kind) {
    widget.health.applyImpact(kind, _randomPointOnDisc());
  }

  Offset? _globalCenter(GlobalKey key) {
    final render = key.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    return render.localToGlobal(render.size.center(Offset.zero));
  }

  void _flyHealImpulse(Offset landing) {
    final overlay = Overlay.of(context);
    final earthRender = _earthKey.currentContext?.findRenderObject();
    final from = _globalCenter(_earthKey);
    final to = _globalCenter(_indicatorKey);
    if (from == null || to == null || earthRender is! RenderBox) return;

    // Точка посадки капсулы на диске — в глобальных координатах.
    final earthSize = earthRender.size.shortestSide;
    final start = earthRender.localToGlobal(
      earthRender.size.center(Offset.zero) +
          Offset(landing.dx, landing.dy) * earthSize / 2 * 0.92 * 0.8,
    );
    final entry = OverlayEntry(
      builder: (context) => _HealImpulse(start: start, end: to),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 600), entry.remove);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.4,
            colors: <Color>[Color(0xFF101A33), Color(0xFF05070F)],
          ),
        ),
        child: Stack(
          children: <Widget>[
            // Земля — центр экрана.
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side =
                      math.min(constraints.maxWidth, constraints.maxHeight) *
                          0.55;
                  return SizedBox(
                    key: _earthKey,
                    width: side,
                    height: side,
                    child: EarthView(health: widget.health),
                  );
                },
              ),
            ),
            // Индикатор жизней: верхняя левая безопасная зона, отступ ≥ 24–32 pt.
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(
                    LivesIndicator.safeZonePadding,
                  ),
                  child: LivesIndicator(
                    key: _indicatorKey,
                    health: widget.health,
                  ),
                ),
              ),
            ),
            // Отладочная панель (временно, до US-01).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final kind in ImpactKind.values)
                        FilledButton.tonal(
                          key: Key('debug-${kind.name}'),
                          onPressed: () => _applyDebugImpact(kind),
                          child: Text(
                            '${kind.label} '
                            '${kind.quartersDelta > 0 ? '+' : ''}'
                            '${kind.quartersDelta}/4',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Зелёно-золотой световой импульс от капсулы к индикатору жизней.
class _HealImpulse extends StatefulWidget {
  const _HealImpulse({required this.start, required this.end});

  final Offset start;
  final Offset end;

  @override
  State<_HealImpulse> createState() => _HealImpulseState();
}

class _HealImpulseState extends State<_HealImpulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final pos = Offset.lerp(widget.start, widget.end, t)!;
        return IgnorePointer(
          child: Stack(
            children: <Widget>[
              Positioned(
                left: pos.dx - 10,
                top: pos.dy - 10,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: <Color>[Color(0xFFD9F99D), Color(0xFF4ADE80)],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFF4ADE80).withValues(alpha: 0.8),
                        blurRadius: 14,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
