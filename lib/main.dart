import 'package:material_ui/material_ui.dart';

import 'game/health/planet_health.dart';
import 'ui/game_screen.dart';

void main() {
  runApp(const G1App());
}

/// G1 — детская игра, первый продукт фабрики Fabric.
///
/// Текущий этап: раунд 1 «Базовая защита» (US-01, issue #4) — один
/// астероид в замкнутом поле с гравитацией Земли, отбивание свайпом,
/// таймер раунда (issue #16), шкала жизней и стадии Земли (issue #15).
class G1App extends StatefulWidget {
  const G1App({super.key});

  @override
  State<G1App> createState() => _G1AppState();
}

class _G1AppState extends State<G1App> {
  final PlanetHealth _health = PlanetHealth();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G1',
      theme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: GameScreen(health: _health),
    );
  }
}
