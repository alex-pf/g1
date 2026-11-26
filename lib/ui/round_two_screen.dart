/// Экран раунда 2 «Множественные угрозы» (US-02, issue #5).
///
/// Игровой контур: Земля в центре тёмного звёздного поля, 2–4 астероида
/// на замкнутом поле (wrap-around), гравитация Земли искривляет их
/// траектории, астероиды сталкиваются друг с другом. Игрок отбивает
/// астероиды пальцами обеих рук: настоящий мультитач (Listener с
/// трекингом pointer id) — каждый палец ведёт свой жест, и касания по
/// разным астероидам срабатывают независимо (критерий 1). HUD: индикатор
/// жизней (issue #15) в верхней левой безопасной зоне, таймер раунда
/// (issue #16) в верхней правой. Таймер истёк при живой планете —
/// победа; шкала жизней на нуле — поражение.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/health/planet_health.dart';
import '../game/round2/round_two_controller.dart';
import 'earth_view.dart';
import 'lives_indicator.dart';
import 'round_hud.dart';
import 'round_two_layer.dart';

/// Экран игры раунда 2.
class RoundTwoScreen extends StatefulWidget {
  const RoundTwoScreen({super.key, required this.health, this.controller});

  final PlanetHealth health;

  /// Контроллер раунда; если не передан, создаётся внутри экрана
  /// (и тогда же освобождается). В тестах передаётся снаружи.
  final RoundTwoController? controller;

  /// Геометрия Земли на экране: сторона квадрата EarthView — 0,55 от
  /// короткой стороны экрана, радиус диска — 0,92 половины стороны
  /// (как в [_EarthPainter]). Нужна для привязки симуляции к пикселям.
  static const double earthViewSideFactor = 0.55;
  static const double earthDiscRadiusFactor = 0.92;

  @override
  State<RoundTwoScreen> createState() => _RoundTwoScreenState();
}

class _RoundTwoScreenState extends State<RoundTwoScreen>
    with SingleTickerProviderStateMixin {
  late final RoundTwoController _controller;
  late final bool _ownsController;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Активные касания: pointer id → старт жеста в пикселях поля.
  /// Каждый палец — независимый жест (мультитач, US-02).
  final Map<int, Offset> _touchStarts = <int, Offset>{};

  /// Указатели, чей жест уже завершился отбиванием (один жест — один отбой).
  final Set<int> _deflectedPointers = <int>{};

  /// Верхняя граница шага симуляции: после сворачивания вкладки
  /// кадр не «телепортирует» астероид через поле.
  static const double maxStepSec = 0.05;

  /// Минимальный ход пальца для распознавания свайпа, px.
  static const double swipeThresholdPx = 12;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? RoundTwoController(health: widget.health);
    _controller.addListener(_onController);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.removeListener(_onController);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0) {
      _controller.update(math.min(dt, maxStepSec));
    }
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  /// Пиксели экрана → единицы поля (высота поля = 1.0).
  Offset _toField(Offset px, double fieldHeight) =>
      Offset(px.dx / fieldHeight, px.dy / fieldHeight);

  void _onPointerDown(PointerDownEvent event, double fieldHeight) {
    _touchStarts[event.pointer] = event.localPosition;
  }

  void _onPointerMove(PointerMoveEvent event, double fieldHeight) {
    final start = _touchStarts[event.pointer];
    if (start == null ||
        _deflectedPointers.contains(event.pointer) ||
        !_controller.isAttached) {
      return;
    }
    final delta = event.localPosition - start;
    if (delta.distance < swipeThresholdPx) return;
    // Свайп: направление — по вектору движения пальца (US-01).
    _controller.tryDeflect(
      _toField(start, fieldHeight),
      _toField(delta, fieldHeight),
    );
    _deflectedPointers.add(event.pointer);
  }

  void _onPointerUp(PointerUpEvent event, double fieldHeight) {
    final start = _touchStarts.remove(event.pointer);
    final alreadyDeflected = _deflectedPointers.remove(event.pointer);
    if (start == null || alreadyDeflected || !_controller.isAttached) return;
    // Касание без свайпа: отбивание от точки касания — ближайший
    // астероид отлетает от пальца через свой центр.
    final field = _toField(event.localPosition, fieldHeight);
    final target = _controller.nearestTarget(field);
    if (target != null) {
      _controller.tryDeflect(field, target.sim.position - field);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _touchStarts.remove(event.pointer);
    _deflectedPointers.remove(event.pointer);
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // Привязка симуляции к реальному размеру поля (идемпотентно).
            final earthRadius = RoundTwoScreen.earthViewSideFactor *
                math.min(w, h) *
                RoundTwoScreen.earthDiscRadiusFactor /
                2 /
                h;
            _controller.attachField(aspect: w / h, earthRadius: earthRadius);

            return Stack(
              children: <Widget>[
                // Земля — центр экрана.
                Center(
                  child: SizedBox(
                    width: RoundTwoScreen.earthViewSideFactor * math.min(w, h),
                    height: RoundTwoScreen.earthViewSideFactor * math.min(w, h),
                    child: EarthView(health: widget.health),
                  ),
                ),
                // Астероиды, следы, вспышки + мультитач-жесты игрока.
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _onPointerDown(e, h),
                    onPointerMove: (e) => _onPointerMove(e, h),
                    onPointerUp: (e) => _onPointerUp(e, h),
                    onPointerCancel: _onPointerCancel,
                    child: RoundTwoLayer(controller: _controller),
                  ),
                ),
                // Индикатор жизней: верхняя левая безопасная зона.
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(
                        LivesIndicator.safeZonePadding,
                      ),
                      child: LivesIndicator(health: widget.health),
                    ),
                  ),
                ),
                // Таймер раунда: верхняя правая безопасная зона.
                Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(
                        LivesIndicator.safeZonePadding,
                      ),
                      child: RoundTimer(
                        text: formatRoundTimer(_controller.remainingSec),
                        roundName: _controller.pacing.name,
                      ),
                    ),
                  ),
                ),
                // Оверлеи победы/поражения с рестартом.
                if (_controller.state != RoundState.playing)
                  Positioned.fill(
                    child: RoundOverlay(
                      state: _controller.state,
                      deflections: _controller.deflections,
                      onRestart: _controller.reset,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
