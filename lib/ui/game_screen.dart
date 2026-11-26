/// Экран раунда 1 «Базовая защита» (US-01, issue #4).
///
/// Игровой контур: Земля в центре тёмного звёздного поля, один астероид
/// на замкнутом поле (wrap-around), гравитация Земли искривляет его
/// траекторию. Игрок отбивает астероид касанием/свайпом. HUD: индикатор
/// жизней (issue #15) в верхней левой безопасной зоне, таймер раунда
/// (issue #16) в верхней правой. Таймер истёк при живой планете —
/// победа; шкала жизней на нуле — поражение.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/health/planet_health.dart';
import '../game/round1/round_one_controller.dart';
import 'asteroid_layer.dart';
import 'earth_view.dart';
import 'lives_indicator.dart';
import 'round_hud.dart';

/// Экран игры раунда 1.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.health, this.controller});

  final PlanetHealth health;

  /// Контроллер раунда; если не передан, создаётся внутри экрана
  /// (и тогда же освобождается). В тестах передаётся снаружи.
  final RoundOneController? controller;

  /// Геометрия Земли на экране: сторона квадрата EarthView — 0,55 от
  /// короткой стороны экрана, радиус диска — 0,92 половины стороны
  /// (как в [_EarthPainter]). Нужна для привязки симуляции к пикселям.
  static const double earthViewSideFactor = 0.55;
  static const double earthDiscRadiusFactor = 0.92;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final RoundOneController _controller;
  late final bool _ownsController;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Старт текущего пана в пикселях поля (для вектора свайпа).
  Offset? _panStartPx;

  /// Отбивание уже выполнено для текущего пана (один жест — один отбой).
  bool _panDeflected = false;

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
        widget.controller ?? RoundOneController(health: widget.health);
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

  void _onPanDown(DragDownDetails details, double fieldHeight) {
    _panStartPx = details.localPosition;
    _panDeflected = false;
  }

  void _onPanUpdate(DragUpdateDetails details, double fieldHeight) {
    final start = _panStartPx;
    if (start == null || _panDeflected || !_controller.isAttached) return;
    final delta = details.localPosition - start;
    if (delta.distance < swipeThresholdPx) return;
    // Свайп: направление — по вектору движения пальца (US-01).
    _controller.tryDeflect(
      _toField(start, fieldHeight),
      _toField(delta, fieldHeight),
    );
    _panDeflected = true;
  }

  void _onTapUp(TapUpDetails details, double fieldHeight) {
    if (!_controller.isAttached) return;
    // Касание без свайпа: отбивание от точки касания — астероид
    // отлетает от пальца через свой центр.
    final field = _toField(details.localPosition, fieldHeight);
    _controller.tryDeflect(field, _controller.sim.position - field);
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
            final earthRadius = GameScreen.earthViewSideFactor *
                math.min(w, h) *
                GameScreen.earthDiscRadiusFactor /
                2 /
                h;
            _controller.attachField(aspect: w / h, earthRadius: earthRadius);

            return Stack(
              children: <Widget>[
                // Земля — центр экрана.
                Center(
                  child: SizedBox(
                    width: GameScreen.earthViewSideFactor * math.min(w, h),
                    height: GameScreen.earthViewSideFactor * math.min(w, h),
                    child: EarthView(health: widget.health),
                  ),
                ),
                // Астероид, след, вспышки, маркер входа + жесты игрока.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (d) => _onPanDown(d, h),
                    onPanUpdate: (d) => _onPanUpdate(d, h),
                    onTapUp: (d) => _onTapUp(d, h),
                    child: AsteroidLayer(controller: _controller),
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
