import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/pacing/pacing_rules.dart';
import 'package:g1/game/pacing/round_pacing.dart';
import 'package:g1/game/pacing/rounds.dart';
import 'package:g1/game/pacing/threat_type.dart';

void main() {
  group('Конфигурация раундов (таблица темпа, issue #16)', () {
    test('ровно 10 раундов с номерами 1..10 по порядку', () {
      expect(gameRounds, hasLength(10));
      for (var i = 0; i < gameRounds.length; i++) {
        expect(gameRounds[i].roundNumber, i + 1);
      }
    });

    test('длительности раундов: 45/50/55/60/65/70/75/75/80/90 сек', () {
      expect(
        gameRounds.map((r) => r.durationSec).toList(),
        [45, 50, 55, 60, 65, 70, 75, 75, 80, 90],
      );
    });

    test('заставки: раунд 3 — 4 сек, раунд 7 — 3 сек, раунд 10 — 4 сек', () {
      final intros = {
        for (final r in gameRounds) r.roundNumber: r.introSec,
      };
      expect(intros[1], 0);
      expect(intros[2], 0);
      expect(intros[3], 4);
      expect(intros[4], 0);
      expect(intros[5], 0);
      expect(intros[6], 0);
      expect(intros[7], 3);
      expect(intros[8], 0);
      expect(intros[9], 0);
      expect(intros[10], 4);
    });

    test('длительность сессии растёт от 45 до 90 секунд (эргономика)', () {
      final durations = gameRounds.map((r) => r.durationSec).toList();
      for (var i = 1; i < durations.length; i++) {
        expect(durations[i], greaterThanOrEqualTo(durations[i - 1]));
      }
      expect(durations.first, 45);
      expect(durations.last, 90);
    });

    test('лимиты объектов на экране: 1/4/4/6/6/6/7/7/7/8', () {
      expect(
        gameRounds.map((r) => r.maxObjectsOnScreen).toList(),
        [1, 4, 4, 6, 6, 6, 7, 7, 7, 8],
      );
    });

    test('интервалы спавна: нет/18/18/22/18/16/15/15/28/13–15 сек', () {
      final intervals = gameRounds
          .map((r) => (r.spawnIntervalSec, r.spawnIntervalMaxSec))
          .toList();
      expect(intervals[0], (null, null));
      expect(intervals[1], (18, null));
      expect(intervals[2], (18, null));
      expect(intervals[3], (22, null));
      expect(intervals[4], (18, null));
      expect(intervals[5], (16, null));
      expect(intervals[6], (15, null));
      expect(intervals[7], (15, null));
      expect(intervals[8], (28, null));
      expect(intervals[9], (13, 15));
    });

    test('стартовые составы по таблице', () {
      expect(gameRounds[0].initialThreats, {ThreatType.asteroid: 1});
      expect(gameRounds[1].initialThreats, {ThreatType.asteroid: 2});
      expect(gameRounds[2].initialThreats, {ThreatType.asteroid: 2});
      expect(gameRounds[3].initialThreats,
          {ThreatType.asteroid: 2, ThreatType.giant: 1});
      expect(gameRounds[4].initialThreats,
          {ThreatType.asteroid: 2, ThreatType.giant: 1});
      expect(gameRounds[5].initialThreats,
          {ThreatType.asteroid: 2, ThreatType.probe: 1});
      expect(gameRounds[6].initialThreats, {
        ThreatType.asteroid: 2,
        ThreatType.giant: 1,
        ThreatType.probe: 1,
      });
      // Раунд 8: старт — 3 угрозы разных типов.
      expect(gameRounds[7].initialObjectCount, 3);
      expect(gameRounds[7].initialThreats.keys.toSet(),
          {ThreatType.asteroid, ThreatType.giant, ThreatType.probe});
      expect(gameRounds[8].initialThreats,
          {ThreatType.asteroid: 2, ThreatType.heavyBolide: 1});
    });

    test('потиповые лимиты: раунд 6 — до 2 зондов, раунд 9 — до 2 болидов',
        () {
      expect(gameRounds[5].perTypeCaps, {ThreatType.probe: 2});
      expect(gameRounds[8].perTypeCaps, {ThreatType.heavyBolide: 2});
    });

    test('раунд 1: новые объекты не появляются', () {
      expect(gameRounds[0].spawnIntervalSec, isNull);
      expect(gameRounds[0].initialThreats, {ThreatType.asteroid: 1});
      expect(gameRounds[0].maxObjectsOnScreen, 1);
    });

    test('раунд 4: лимит 6 объектов с учётом осколков', () {
      final round4 = gameRounds[3];
      expect(round4.maxObjectsOnScreen, 6);
      expect(round4.spawnTypes, {ThreatType.giant});
    });
  });

  group('Прирост скорости', () {
    test('раунд 1: +15% каждые 15 сек, 3 ступени (макс. +45%)', () {
      final growth = gameRounds[0].speedGrowth;
      expect(growth, isA<SteppedSpeedGrowth>());
      expect(speedMultiplierAt(gameRounds[0], 0), 1.0);
      expect(speedMultiplierAt(gameRounds[0], 15), closeTo(1.15, 1e-9));
      expect(speedMultiplierAt(gameRounds[0], 30), closeTo(1.30, 1e-9));
      expect(speedMultiplierAt(gameRounds[0], 45), closeTo(1.45, 1e-9));
    });

    test('плавный рост к концу таймера по таблице', () {
      final expected = {2: 35.0, 3: 35.0, 4: 40.0, 5: 40.0, 6: 45.0,
          7: 45.0, 8: 50.0, 9: 50.0};
      for (final entry in expected.entries) {
        final round = gameRounds[entry.key - 1];
        expect(round.speedGrowth, isA<LinearSpeedGrowth>());
        expect(speedMultiplierAt(round, 0), 1.0);
        expect(
          speedMultiplierAt(round, round.durationSec.toDouble()),
          closeTo(1 + entry.value / 100, 1e-9),
          reason: 'раунд ${entry.key}',
        );
      }
    });

    test('раунд 10: +60% достигается к финальным 15 секундам (75-я сек)',
        () {
      final round10 = gameRounds[9];
      expect(speedMultiplierAt(round10, 75), closeTo(1.60, 1e-9));
      expect(speedMultiplierAt(round10, 90), closeTo(1.60, 1e-9));
      expect(speedMultiplierAt(round10, 37.5), closeTo(1.30, 1e-9));
    });

    test('раунд 6: пауза наведения зонда сокращается 1,2 → 0,7 сек', () {
      final pause = gameRounds[5].probeAimPause;
      expect(pause, isNotNull);
      expect(pause!.startSec, 1.2);
      expect(pause.endSec, 0.7);
    });

    test('раунд 7: аномалия меняет позицию каждые 25 сек + выбросы', () {
      expect(gameRounds[6].anomalyRepositionIntervalSec, 25);
      expect(gameRounds[6].anomalySpeedBursts, isTrue);
    });
  });

  group('Солнечные штормы (US-08)', () {
    test('расписание штормов по таблице', () {
      expect(gameRounds[7].storms.map((s) => s.warningAtSec), [22, 50]);
      expect(gameRounds[7].storms.map((s) => s.flashDurationSec), [4.5, 4.5]);
      expect(gameRounds[8].storms.map((s) => s.warningAtSec), [25, 55]);
      expect(gameRounds[8].storms.map((s) => s.flashDurationSec), [5, 5]);
      expect(gameRounds[9].storms.map((s) => s.warningAtSec), [20, 48, 72]);
      expect(gameRounds[9].storms.map((s) => s.flashDurationSec), [5, 5, 5]);
      for (final round in gameRounds.sublist(0, 7)) {
        expect(round.storms, isEmpty, reason: 'раунд ${round.roundNumber}');
      }
    });

    test('вспышка начинается через ~2 сек после предупреждения (US-08)',
        () {
      const storm = StormWindow(warningAtSec: 22, flashDurationSec: 4.5);
      expect(storm.flashStartSec, 24);
      expect(storm.flashEndSec, 28.5);
    });
  });

  group('Спасательные капсулы (US-05)', () {
    test('тайминги капсул по таблице', () {
      expect(gameRounds[0].capsuleSpawnsSec, isEmpty);
      expect(gameRounds[1].capsuleSpawnsSec, isEmpty);
      expect(gameRounds[2].capsuleSpawnsSec, isEmpty);
      expect(gameRounds[3].capsuleSpawnsSec, isEmpty);
      expect(gameRounds[4].capsuleSpawnsSec, [24, 48]);
      expect(gameRounds[5].capsuleSpawnsSec, [25, 52]);
      expect(gameRounds[6].capsuleSpawnsSec, [20, 42, 60]);
      expect(gameRounds[7].capsuleSpawnsSec, [16, 38, 62]);
      expect(gameRounds[8].capsuleSpawnsSec, [18, 44, 66]);
      expect(gameRounds[9].capsuleSpawnsSec, [15, 36, 58, 78]);
    });

    test('капсулы появляются вне запрещённых зон штормов '
        '(кроме известного расхождения раунда 10)', () {
      // Известное расхождение таблицы issue #16: капсула на 78-й сек
      // раунда 10 попадает внутрь вспышки третьего шторма
      // (предупреждение 72 сек + 2 сек + вспышка 5 сек = 74–79 сек).
      // Зафиксировано автору issue; до решения держим список отклонений
      // явным, чтобы любое новое нарушение ломало тест.
      final violations = <String>[];
      for (final round in gameRounds) {
        for (final capsuleAt in round.capsuleSpawnsSec) {
          if (isCapsuleSpawnForbiddenAt(round, capsuleAt.toDouble())) {
            violations.add('${round.roundNumber}:$capsuleAt');
          }
        }
      }
      expect(violations, ['10:78']);
    });

    test('чистое время капсул: минимум 5 секунд (кроме того же кейса)', () {
      final violations = <String>[];
      for (final round in gameRounds) {
        for (final capsuleAt in round.capsuleSpawnsSec) {
          final clear = capsuleClearTimeSec(round, capsuleAt.toDouble());
          if (clear < RoundPacing.capsuleMinClearTimeSec) {
            violations.add('${round.roundNumber}:$capsuleAt=$clear');
          }
        }
      }
      expect(violations, isEmpty);
    });

    test('окна между штормами раунда 8 честные: капсулы 16/38/62', () {
      final round8 = gameRounds[7];
      expect(isCapsuleWindowFair(round8, 16), isTrue);
      expect(isCapsuleWindowFair(round8, 38), isTrue);
      expect(isCapsuleWindowFair(round8, 62), isTrue);
      // Внутри вспышки и за 3 секунды до неё капсула запрещена.
      expect(isCapsuleWindowFair(round8, 21), isFalse);
      expect(isCapsuleWindowFair(round8, 26), isFalse);
    });
  });

  group('Правила балансировки темпа', () {
    test('стоп-спавн: за 10 секунд до конца любого раунда спавн закрыт',
        () {
      for (final round in gameRounds) {
        final before = round.stopSpawnAtSec - 0.001;
        final at = round.stopSpawnAtSec;
        expect(isStopSpawnActive(round, before), isFalse,
            reason: 'раунд ${round.roundNumber} до стоп-спавна');
        expect(isStopSpawnActive(round, at), isTrue,
            reason: 'раунд ${round.roundNumber} на границе');
        expect(isStopSpawnActive(round, round.durationSec.toDouble()), isTrue);
      }
      expect(RoundPacing.stopSpawnBeforeEndSec, 10);
    });

    test('Screen Density Cap: спавн откладывается при заполненном экране',
        () {
      final round4 = gameRounds[3]; // лимит 6 объектов
      // 6 объектов (гигант разбит на 4 осколка + 2 астероида) — слота нет.
      expect(
        canSpawnThreat(round4,
            elapsedSec: 30, activeObjects: 6, incomingType: ThreatType.giant),
        isFalse,
      );
      // Освободился слот — спавн снова возможен.
      expect(
        canSpawnThreat(round4,
            elapsedSec: 30, activeObjects: 5, incomingType: ThreatType.giant),
        isTrue,
      );
    });

    test('Screen Density Cap: потиповой лимит (до 2 зондов в раунде 6)',
        () {
      final round6 = gameRounds[5];
      expect(
        canSpawnThreat(round6,
            elapsedSec: 30,
            activeObjects: 3,
            activeByType: {ThreatType.probe: 2},
            incomingType: ThreatType.probe),
        isFalse,
      );
      expect(
        canSpawnThreat(round6,
            elapsedSec: 30,
            activeObjects: 3,
            activeByType: {ThreatType.probe: 1},
            incomingType: ThreatType.probe),
        isTrue,
      );
    });

    test('стоп-спавн сильнее свободных слотов', () {
      final round2 = gameRounds[1]; // 50 сек, стоп-спавн с 40-й
      expect(
        canSpawnThreat(round2,
            elapsedSec: 39.9, activeObjects: 0, incomingType: ThreatType.asteroid),
        isTrue,
      );
      expect(
        canSpawnThreat(round2,
            elapsedSec: 40, activeObjects: 0, incomingType: ThreatType.asteroid),
        isFalse,
      );
    });
  });

  group('Согласованность со спецификацией баланса (issue #7)', () {
    test('типы угроз и урон по таблице взаимодействий', () {
      expect(ThreatType.asteroid.starDamage, 1.0);
      expect(ThreatType.giant.starDamage, 1.0);
      expect(ThreatType.giantFragment.starDamage, 0.25);
      expect(ThreatType.probe.starDamage, 1.0);
      expect(ThreatType.heavyBolide.starDamage, 1.5);
      expect(ThreatType.escapeCapsule.starDamage, -0.25);
      expect(ThreatType.escapeCapsule.isHostile, isFalse);
    });

    test('спавнеры не порождают капсулы и осколки напрямую', () {
      for (final round in gameRounds) {
        expect(round.spawnTypes.contains(ThreatType.escapeCapsule), isFalse,
            reason: 'раунд ${round.roundNumber}');
        expect(round.spawnTypes.contains(ThreatType.giantFragment), isFalse,
            reason: 'раунд ${round.roundNumber}');
      }
    });
  });

  group('Валидация конфигурации', () {
    test('все раунды валидны, кроме известного расхождения раунда 10', () {
      final problems = <String>[];
      for (final round in gameRounds) {
        problems.addAll(validateRoundPacing(round));
      }
      // Единственное ожидаемое нарушение — капсула 78-й секунды раунда 10
      // (см. тест окон капсул выше).
      expect(problems, hasLength(1));
      expect(problems.single, contains('Раунд 10'));
      expect(problems.single, contains('78'));
    });

    test('стартовый состав каждого раунда в пределах лимита', () {
      for (final round in gameRounds) {
        expect(round.initialObjectCount,
            lessThanOrEqualTo(round.maxObjectsOnScreen),
            reason: 'раунд ${round.roundNumber}');
      }
    });
  });
}
