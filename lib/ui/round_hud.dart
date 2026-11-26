/// Общие HUD-элементы экранов раундов: таймер раунда (issue #16) и
/// оверлей завершения с рестартом. Используются экранами раундов 1 и 2.
library;

import 'package:material_ui/material_ui.dart';

import '../game/round1/round_one_controller.dart' show RoundState;

/// Форматирует остаток таймера раунда как «м:сс».
String formatRoundTimer(double remainingSec) {
  final total = remainingSec.ceil();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Индикатор таймера раунда (issue #16: длительность — из конфигурации).
class RoundTimer extends StatelessWidget {
  const RoundTimer({super.key, required this.text, required this.roundName});

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
class RoundOverlay extends StatelessWidget {
  const RoundOverlay({
    super.key,
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
