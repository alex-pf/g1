import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const G1App());
}

/// G1 — детская игра, первый продукт фабрики Fabric.
///
/// Точка входа: hello-world PWA, от которой растут следующие этапы
/// (функционал → Android → iPhone). См. issue #1.
class G1App extends StatelessWidget {
  const G1App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G1',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('G1'),
      ),
      body: const Center(
        child: Text(
          'Hello world',
          style: TextStyle(fontSize: 32),
        ),
      ),
    );
  }
}
