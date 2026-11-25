import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/onboarding/onboarding_constants.dart';
import 'package:g1/game/onboarding/round_scenarios.dart';

void main() {
  group('Сценарий раунда 1 (первые 15 секунд)', () {
    test('расписание фаз: пролёт 0–3, замкнутость 3–6, подсказка 6–9, '
        'контакт 9+', () {
      final beats = RoundScenarios.roundOne;
      expect(beats, hasLength(4));

      expect(beats[0].beat, OnboardingBeat.tangentialFlybyDottedTrail);
      expect(beats[0].start, Duration.zero);
      expect(beats[0].end, const Duration(seconds: 3));

      expect(beats[1].beat, OnboardingBeat.wrapAroundWithEntryMarker);
      expect(beats[1].start, const Duration(seconds: 3));
      expect(beats[1].end, const Duration(seconds: 6));

      expect(beats[2].beat, OnboardingBeat.ghostSwipeWithSlowMo);
      expect(beats[2].start, const Duration(seconds: 6));
      expect(beats[2].end, const Duration(seconds: 9));

      expect(beats[3].beat, OnboardingBeat.firstContactStartsRoundTimer);
      expect(beats[3].start, const Duration(seconds: 9));
      expect(beats[3].end, isNull); // мгновенное событие, 9+ сек
    });

    test('проигрыватель выдаёт события по мере наступления их времени', () {
      final player = ScenarioPlayer(RoundScenarios.roundOne);

      expect(player.tick(const Duration(seconds: 2)), hasLength(1));
      expect(player.elapsed, const Duration(seconds: 2));
      expect(
        player.hasFired(OnboardingBeat.tangentialFlybyDottedTrail),
        isTrue,
      );
      expect(
        player.hasFired(OnboardingBeat.wrapAroundWithEntryMarker),
        isFalse,
      );

      // Переход через 3 и 6 секунд выдаёт обе фазы, каждую один раз.
      final due = player.tick(const Duration(seconds: 5));
      expect(due.map((b) => b.beat), [
        OnboardingBeat.wrapAroundWithEntryMarker,
        OnboardingBeat.ghostSwipeWithSlowMo,
      ]);
      expect(player.tick(const Duration(seconds: 10)), hasLength(1));
      expect(
        player.hasFired(OnboardingBeat.firstContactStartsRoundTimer),
        isTrue,
      );

      // Повторных срабатываний нет.
      expect(player.tick(const Duration(seconds: 5)), isEmpty);
    });

    test('активные окна событий соответствуют фазам', () {
      final player = ScenarioPlayer(RoundScenarios.roundOne);
      expect(
        player
            .activeBeatsAt(const Duration(seconds: 4))
            .map((b) => b.beat),
        [OnboardingBeat.wrapAroundWithEntryMarker],
      );
      expect(
        player
            .activeBeatsAt(const Duration(seconds: 7))
            .map((b) => b.beat),
        [OnboardingBeat.ghostSwipeWithSlowMo],
      );
    });
  });

  group('Сценарий раунда 2 (первые 20 секунд)', () {
    test('синхронный вылет двух астероидов в 0–5 сек', () {
      final beats = RoundScenarios.roundTwo;
      expect(beats[0].beat, OnboardingBeat.syncDualLaunch);
      expect(beats[0].start, Duration.zero);
      expect(beats[0].end, const Duration(seconds: 5));
    });

    test('постановка столкновения в воздухе в 12–18 сек', () {
      final beats = RoundScenarios.roundTwo;
      expect(beats[1].beat, OnboardingBeat.midAirCollisionSetup);
      expect(beats[1].start, const Duration(seconds: 12));
      expect(beats[1].end, const Duration(seconds: 18));
    });
  });

  group('Мультитач-аккорд раунда 2 (окно 0,3 сек)', () {
    test('два отбивания в пределах 0,3 секунды дают аккорд', () {
      final chord = MultiTouchChord();
      expect(chord.registerDeflect(const Duration(seconds: 2)), isFalse);
      expect(
        chord.registerDeflect(const Duration(seconds: 2, milliseconds: 250)),
        isTrue,
      );
    });

    test('отбивания с интервалом больше 0,3 секунды не дают аккорд', () {
      final chord = MultiTouchChord();
      chord.registerDeflect(const Duration(seconds: 2));
      expect(
        chord.registerDeflect(const Duration(seconds: 2, milliseconds: 400)),
        isFalse,
      );
    });

    test('после аккорда пара сбрасывается: третий удар не цепляется', () {
      final chord = MultiTouchChord();
      chord.registerDeflect(const Duration(seconds: 1));
      expect(
        chord.registerDeflect(const Duration(seconds: 1, milliseconds: 200)),
        isTrue,
      );
      expect(
        chord.registerDeflect(const Duration(seconds: 1, milliseconds: 300)),
        isFalse,
      );
    });

    test('окно по умолчанию — константа спецификации 0,3 сек', () {
      expect(MultiTouchChord().window,
          OnboardingTimings.multiTouchChordWindow);
      expect(OnboardingTimings.multiTouchChordWindow,
          const Duration(milliseconds: 300));
    });
  });

  group('Сценарий раунда 3: заставка и первые 15 секунд', () {
    test('заставка гравитационного захвата длится 4 секунды', () {
      final intro = RoundScenarios.roundThreeIntro;
      final capture = intro.firstWhere(
        (b) => b.beat == OnboardingBeat.moonGravityCaptureIntro,
      );
      expect(capture.start, Duration.zero);
      expect(capture.end, OnboardingTimings.moonIntroDuration);
      expect(OnboardingTimings.moonIntroDuration, const Duration(seconds: 4));
    });

    test('дуга гравитационной связки проявляется на 1 секунду', () {
      final intro = RoundScenarios.roundThreeIntro;
      final arc = intro.firstWhere(
        (b) => b.beat == OnboardingBeat.gravityLinkArc,
      );
      expect(arc.end! - arc.start, OnboardingTimings.gravityLinkArcDuration);
      expect(arc.end! - arc.start, const Duration(seconds: 1));
      // Дуга внутри заставки.
      expect(arc.start, greaterThanOrEqualTo(Duration.zero));
      expect(arc.end, lessThanOrEqualTo(OnboardingTimings.moonIntroDuration));
    });

    test('визуальная связка общей защиты в 0–2 сек, воронка Луны в 2–8 сек',
        () {
      final beats = RoundScenarios.roundThree;
      expect(beats[0].beat, OnboardingBeat.sharedHealthPulse);
      expect(beats[0].start, Duration.zero);
      expect(beats[0].end, const Duration(seconds: 2));

      expect(beats[1].beat, OnboardingBeat.gravityFunnelDemo);
      expect(beats[1].start, const Duration(seconds: 2));
      expect(beats[1].end, const Duration(seconds: 8));
    });
  });

  group('Закрепление уязвимости Луны (общая шкала)', () {
    test('попадание в Луну: кратер, −1 звезда из общей шкалы, '
        'синхронная деградация Земли', () {
      final outcome = MoonOnboarding().onMoonImpact();
      expect(outcome.beat, OnboardingBeat.moonImpactCrater);
      expect(outcome.starsLost, 1);
      expect(outcome.leavesCrater, isTrue);
      expect(outcome.earthDegradesSync, isTrue);
      expect(outcome.protectiveRipple, isFalse);
    });

    test('успешная защита Луны: защитная рябь без потерь', () {
      final outcome = MoonOnboarding().onMoonDefended();
      expect(outcome.beat, OnboardingBeat.moonDefendedRipple);
      expect(outcome.starsLost, 0);
      expect(outcome.leavesCrater, isFalse);
      expect(outcome.earthDegradesSync, isFalse);
      expect(outcome.protectiveRipple, isTrue);
    });

    test('общая шкала — 5 звёзд (US-03, UX-спецификация #15)', () {
      expect(MoonOnboarding.sharedPoolStars, 5);
    });
  });

  group('Согласованность со смежными спецификациями', () {
    test('заставка раунда 3 — 4 секунды (спецификация темпа #16)', () {
      // #16: раунд 3 = 55 сек таймера + 4 сек заставка.
      expect(OnboardingTimings.moonIntroDuration, const Duration(seconds: 4));
    });

    test('Slow-Mo замедляет на 40 % (множитель 0,6)', () {
      expect(OnboardingTimings.slowMoFactor, 0.6);
    });

    test('сценарии укладываются в длительности раундов #16: '
        'р1 ≤ 45 сек, р2 ≤ 50 сек, р3 ≤ 55 сек + 4 сек заставка', () {
      Duration lastEnd(List<ScenarioBeat> beats) => beats
          .map((b) => b.end ?? b.start)
          .reduce((a, b) => a > b ? a : b);

      expect(lastEnd(RoundScenarios.roundOne),
          lessThanOrEqualTo(const Duration(seconds: 45)));
      expect(lastEnd(RoundScenarios.roundTwo),
          lessThanOrEqualTo(const Duration(seconds: 50)));
      expect(lastEnd(RoundScenarios.roundThree),
          lessThanOrEqualTo(const Duration(seconds: 55)));
      expect(
        lastEnd(RoundScenarios.roundThreeIntro),
        lessThanOrEqualTo(OnboardingTimings.moonIntroDuration),
      );
    });
  });
}
