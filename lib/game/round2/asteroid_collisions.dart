/// Столкновения астероидов в воздухе (US-02, issue #5).
///
/// Чистая функция над [AsteroidSim]: упругое столкновение двух шаров
/// равной массы — обмен нормальными компонентами скорости вдоль линии
/// центров, тангенциальные компоненты сохраняются. Направление полёта
/// меняется мгновенно; модуль скорости перезадаётся темпом раунда на
/// следующем шаге интеграции (см. [AsteroidSim.update]).
library;

import 'dart:ui' show Offset;

import '../round1/asteroid_sim.dart';

/// Проверяет пару астероидов на столкновение и разрешает его.
///
/// Столкновение считается при пересечении дисков (дистанция центров
/// меньше суммы радиусов) и сближении тел (относительная скорость
/// вдоль нормали направлена друг к другу). Пересекающиеся тела
/// разводятся по линии центров, чтобы не «залипали» друг в друге.
///
/// Возвращает `true`, если столкновение произошло (для VFX/SFX).
bool resolveAsteroidCollision(AsteroidSim a, AsteroidSim b) {
  final d = b.position - a.position;
  final dist = d.distance;
  final minDist = a.asteroidRadius + b.asteroidRadius;
  if (dist >= minDist) return false;

  // Нормаль от a к b; при полном совпадении центров — произвольная ось.
  final Offset n = dist < 1e-9 ? const Offset(1, 0) : d / dist;

  final vaN = a.velocity.dx * n.dx + a.velocity.dy * n.dy;
  final vbN = b.velocity.dx * n.dx + b.velocity.dy * n.dy;

  // Уже расходятся — столкновения нет, только разведение позиций ниже
  // не требуется: следующий шаг сам разведёт их движением.
  if (vaN - vbN <= 0) return false;

  // Равные массы: обмен нормальными компонентами скорости.
  a.velocity += n * (vbN - vaN);
  b.velocity += n * (vaN - vbN);

  // Разведение пересекающихся дисков по линии центров.
  final overlap = minDist - dist;
  a.position -= n * (overlap / 2);
  b.position += n * (overlap / 2);
  return true;
}
