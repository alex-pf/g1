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

  String _formatTimer(double remainingSec) {
    final total = remainingSec.ceil();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
                      child: _RoundTimer(
                        text: _formatTimer(_controller.remainingSec),
                        roundName: _controller.pacing.name,
                      ),
                    ),
                  ),
                ),
                // Оверлеи победы/поражения с рестартом.
                if (_controller.state != RoundState.playing)
                  Positioned.fill(
                    child: _RoundOverlay(
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

/// Индикатор таймера раунда (issue #16: длительность — из конфигурации).
class _RoundTimer extends StatelessWidget {
  const _RoundTimer({required this.text, required this.roundName});

  final String text;
  final String roundName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          roundName,
          style: const TextStyle(
            color: Color(0xFF9FB6DA),
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          key: const Key('round-timer'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Оверлей завершения раунда: «Раунд пройден» / «Поражение» + рестарт.
class _RoundOverlay extends StatelessWidget {
  const _RoundOverlay({
    required this.state,
    required this.deflections,
    required this.onRestart,
  });

  final RoundState state;
  final int deflections;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final victory = state == RoundState.victory;
    return Container(
      key: Key(victory ? 'round-victory-overlay' : 'round-defeat-overlay'),
      color: const Color(0xCC05070F),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              victory ? 'Раунд пройден!' : 'Поражение',
              style: TextStyle(
                color: victory ? const Color(0xFF9BE15D) : const Color(0xFFFF6A5A),
                fontSize: 40,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              victory
                  ? 'Земля устояла. Отбиваний: $deflections'
                  : 'Земля разрушена. Отбиваний: $deflections',
              style: const TextStyle(color: Color(0xFF9FB6DA), fontSize: 16),
            ),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('round-restart-button'),
              onPressed: onRestart,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text('Играть ещё раз', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
