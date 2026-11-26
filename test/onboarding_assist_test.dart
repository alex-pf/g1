import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/onboarding/assist_mechanics.dart';
import 'package:g1/game/onboarding/onboarding_constants.dart';

void main() {
  group('SlowMoAssist (правило 1: замедление 40 %)', () {
    test('изначально взведено, замедление не активно', () {
      final slowMo = SlowMoAssist();
      expect(slowMo.state, SlowMoState.armed);
      expect(slowMo.isActive, isFalse);
      expect(slowMo.timeScale, 1.0);
    });

    test('пересечение внешней орбиты включает замедление на 40 %', () {
      final slowMo = SlowMoAssist();
      slowMo.onOuterOrbitCrossed();
      expect(slowMo.isActive, isTrue);
      expect(slowMo.timeScale, OnboardingTimings.slowMoFactor);
      expect(slowMo.timeScale, 0.6);
    });

    test('первое касание мгновенно снимает замедление навсегда', () {
      final slowMo = SlowMoAssist();
      slowMo.onOuterOrbitCrossed();
      slowMo.onPlayerContact();
      expect(slowMo.state, SlowMoState.completed);
      expect(slowMo.timeScale, 1.0);

      // Повторные подлёты замедление не включают.
      slowMo.onOuterOrbitCrossed();
      expect(slowMo.isActive, isFalse);
      expect(slowMo.timeScale, 1.0);
    });

    test('пропуск (астероид врезался в Землю) повторно взводит механику', () {
      final slowMo = SlowMoAssist();
      slowMo.onOuterOrbitCrossed();
      expect(slowMo.isActive, isTrue);

      slowMo.onPlayerMissed();
      expect(slowMo.state, SlowMoState.armed);
      expect(slowMo.isActive, isFalse);

      // При следующем заходе камня замедление срабатывает повторно.
      slowMo.onOuterOrbitCrossed();
      expect(slowMo.isActive, isTrue);
      expect(slowMo.timeScale, 0.6);
    });

    test('касание до включения замедления не завершает механику', () {
      final slowMo = SlowMoAssist();
      slowMo.onPlayerContact();
      expect(slowMo.state, SlowMoState.armed);
      slowMo.onOuterOrbitCrossed();
      expect(slowMo.isActive, isTrue);
    });
  });

  group('GhostSwipeAssist (правило 2: жест-призрак)', () {
    test('показывается для нового целевого жеста', () {
      final ghost = GhostSwipeAssist();
      expect(ghost.visibleFor, isNull);
      ghost.showFor(GhostSwipeTarget.deflectAsteroid);
      expect(ghost.isVisibleFor(GhostSwipeTarget.deflectAsteroid), isTrue);
      expect(ghost.isCompleted(GhostSwipeTarget.deflectAsteroid), isFalse);
    });

    test('отключается навсегда после первого успешного жеста', () {
      final ghost = GhostSwipeAssist();
      ghost.showFor(GhostSwipeTarget.deflectAsteroid);
      ghost.onGestureSuccess(GhostSwipeTarget.deflectAsteroid);
      expect(ghost.visibleFor, isNull);
      expect(ghost.isCompleted(GhostSwipeTarget.deflectAsteroid), isTrue);

      // Повторно не показывается.
      ghost.showFor(GhostSwipeTarget.deflectAsteroid);
      expect(ghost.visibleFor, isNull);
    });

    test('целевые жесты независимы: гигант (4-й раунд) и болид (9-й)', () {
      final ghost = GhostSwipeAssist();
      ghost.showFor(GhostSwipeTarget.deflectAsteroid);
      ghost.onGestureSuccess(GhostSwipeTarget.deflectAsteroid);

      ghost.showFor(GhostSwipeTarget.gentleHoldGiant);
      expect(ghost.isVisibleFor(GhostSwipeTarget.gentleHoldGiant), isTrue);
      expect(ghost.isCompleted(GhostSwipeTarget.twoFingerPushBolide), isFalse);

      ghost.onGestureSuccess(GhostSwipeTarget.gentleHoldGiant);
      ghost.showFor(GhostSwipeTarget.twoFingerPushBolide);
      expect(
        ghost.isVisibleFor(GhostSwipeTarget.twoFingerPushBolide),
        isTrue,
      );
    });

    test('hide() скрывает подсказку без отметки об успехе', () {
      final ghost = GhostSwipeAssist();
      ghost.showFor(GhostSwipeTarget.deflectAsteroid);
      ghost.hide();
      expect(ghost.visibleFor, isNull);
      expect(ghost.isCompleted(GhostSwipeTarget.deflectAsteroid), isFalse);
    });
  });

  group('EdgeEntryMarkers (правило 3: маркер входа за 0,5 сек)', () {
    test('маркер появляется ровно за 0,5 секунды до возврата объекта', () {
      final markers = EdgeEntryMarkers();
      const returnAt = Duration(seconds: 6);
      markers.scheduleReturn(
        objectId: 'asteroid-1',
        returnEdge: ScreenEdge.left,
        returnAt: returnAt,
      );

      // За 0,6 секунды — ещё нет.
      expect(markers.tick(const Duration(milliseconds: 5400)), isEmpty);
      // Ровно за 0,5 секунды — вспыхивает.
      final active = markers.tick(const Duration(milliseconds: 5500));
      expect(active, hasLength(1));
      expect(active.single.objectId, 'asteroid-1');
      expect(active.single.edge, ScreenEdge.left);
    });

    test('маркер виден вплоть до возврата и исчезает после', () {
      final markers = EdgeEntryMarkers();
      const returnAt = Duration(seconds: 6);
      markers.scheduleReturn(
        objectId: 'asteroid-1',
        returnEdge: ScreenEdge.left,
        returnAt: returnAt,
      );

      expect(markers.tick(returnAt), hasLength(1));
      expect(markers.tick(returnAt + const Duration(milliseconds: 100)),
          isEmpty);
      expect(markers.pendingCount, 0);
    });

    test('механика постоянная: работает для любого числа объектов', () {
      final markers = EdgeEntryMarkers();
      for (var i = 0; i < 3; i++) {
        markers.scheduleReturn(
          objectId: 'obj-$i',
          returnEdge: ScreenEdge.right,
          returnAt: Duration(seconds: 10 + i),
        );
      }
      final active = markers.tick(const Duration(milliseconds: 9550));
      expect(active, hasLength(1));
      expect(active.single.objectId, 'obj-0');
    });

    test('lead по умолчанию равен константе спецификации (0,5 сек)', () {
      expect(
        EdgeEntryMarkers().lead,
        OnboardingTimings.edgeEntryMarkerLead,
      );
      expect(OnboardingTimings.edgeEntryMarkerLead,
          const Duration(milliseconds: 500));
    });
  });

  group('SafeStartTrajectory (правило 4: безопасный первый спавн)', () {
    test('первый объект нового типа — безопасная касательная траектория',
        () {
      final safe = SafeStartTrajectory();
      expect(safe.hasSeen(OnboardingThreatKind.asteroid), isFalse);

      final plan = safe.planFor(OnboardingThreatKind.asteroid);
      expect(plan.isSafeIntro, isTrue);
      expect(plan.tangential, isTrue);
      expect(
        plan.timeToContact >= OnboardingTimings.safeTrajectoryMinWindow,
        isTrue,
      );
      expect(
        plan.timeToContact <= OnboardingTimings.safeTrajectoryMaxWindow,
        isTrue,
      );
      expect(safe.hasSeen(OnboardingThreatKind.asteroid), isTrue);
    });

    test('второй и последующие объекты того же типа — обычная траектория',
        () {
      final safe = SafeStartTrajectory();
      safe.planFor(OnboardingThreatKind.asteroid);
      final second = safe.planFor(OnboardingThreatKind.asteroid);
      expect(second.isSafeIntro, isFalse);
      expect(second.tangential, isFalse);
    });

    test('каждый новый тип получает свой безопасный первый спавн', () {
      final safe = SafeStartTrajectory();
      safe.planFor(OnboardingThreatKind.asteroid);

      final giantFirst = safe.planFor(OnboardingThreatKind.fragileGiant);
      expect(giantFirst.isSafeIntro, isTrue);

      final bolideFirst = safe.planFor(OnboardingThreatKind.heavyBolide);
      expect(bolideFirst.isSafeIntro, isTrue);
    });

    test('запас времени ограничен окном 3–4 секунды', () {
      final safe = SafeStartTrajectory();
      final tooFast = safe.planFor(
        OnboardingThreatKind.asteroid,
        requestedWindow: const Duration(seconds: 1),
      );
      expect(tooFast.timeToContact,
          OnboardingTimings.safeTrajectoryMinWindow);

      final safe2 = SafeStartTrajectory();
      final tooSlow = safe2.planFor(
        OnboardingThreatKind.asteroid,
        requestedWindow: const Duration(seconds: 10),
      );
      expect(tooSlow.timeToContact,
          OnboardingTimings.safeTrajectoryMaxWindow);
    });
  });
}
