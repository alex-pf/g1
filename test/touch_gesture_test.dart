import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/hitboxes/touch_gesture.dart';

TouchContact contact(
  int id,
  double x,
  double y,
  int downAtMs, {
  double diameter = TouchContact.typicalFingerContactDiameterPt,
  bool elongated = false,
}) =>
    TouchContact(
      id: id,
      xPt: x,
      yPt: y,
      downAtMs: downAtMs,
      contactDiameterPt: diameter,
      isElongated: elongated,
    );

void main() {
  const classifier = TwoFingerGestureClassifier();

  group('Конфигурация жеста двумя пальцами (issue #18, раздел 2)', () {
    test('пороги спецификации: 26 pt, 240 pt, 140 мс', () {
      expect(TwoFingerGestureConfig.minFingerDistancePt, 26);
      expect(TwoFingerGestureConfig.maxArcReachPt, 240);
      expect(TwoFingerGestureConfig.syncWindowMs, 140);
    });
  });

  group('Минимальная дистанция между пальцами 26 pt', () {
    test('дистанция 25,9 pt — один широкий палец, толчок не активируется', () {
      final first = contact(1, 100, 100, 0);
      final second = contact(2, 125.9, 100, 50);
      expect(
        classifier.classify(first, second),
        TwoFingerVerdict.singleWideFinger,
      );
    });

    test('дистанция ровно 26 pt — два пальца, толчок возможен', () {
      final first = contact(1, 100, 100, 0);
      final second = contact(2, 126, 100, 50);
      expect(classifier.classify(first, second), TwoFingerVerdict.powerPush);
    });

    test('слияние пятен важнее окна синхронности', () {
      // Пальцы ближе 26 pt даже в пределах окна 140 мс — один палец.
      final first = contact(1, 100, 100, 0);
      final second = contact(2, 120, 100, 10);
      expect(
        classifier.classify(first, second),
        TwoFingerVerdict.singleWideFinger,
      );
    });
  });

  group('Максимальный захват силовой дуги 240 pt', () {
    test('дуга 240 pt — толчок собирается (граница включительно)', () {
      final first = contact(1, 100, 100, 0);
      final second = contact(2, 340, 100, 50);
      expect(classifier.classify(first, second), TwoFingerVerdict.powerPush);
    });

    test('дуга 241 pt — слишком широко, толчка нет', () {
      final first = contact(1, 100, 100, 0);
      final second = contact(2, 341, 100, 50);
      expect(classifier.classify(first, second), TwoFingerVerdict.arcTooWide);
    });

    test('игрок может упереться пальцами по бокам от болида', () {
      // Болид между пальцами: дистанция 200 pt по диагонали — в пределах дуги.
      final first = contact(1, 300, 300, 0);
      final second = contact(1 + 1, 300 + 141.4, 300 + 141.4, 80);
      expect(classifier.classify(first, second), TwoFingerVerdict.powerPush);
    });
  });

  group('Окно синхронности касания 140 мс', () {
    test('второй палец на 139 мс — единый двуручный толчок', () {
      final first = contact(1, 100, 100, 1000);
      final second = contact(2, 200, 100, 1139);
      expect(classifier.classify(first, second), TwoFingerVerdict.powerPush);
    });

    test('второй палец ровно на 140 мс — ещё в окне', () {
      final first = contact(1, 100, 100, 1000);
      final second = contact(2, 200, 100, 1140);
      expect(classifier.classify(first, second), TwoFingerVerdict.powerPush);
    });

    test('второй палец на 141 мс — первое касание становится слабым ударом',
        () {
      final first = contact(1, 100, 100, 1000);
      final second = contact(2, 200, 100, 1141);
      expect(
        classifier.classify(first, second),
        TwoFingerVerdict.lateSecondTouch,
      );
      expect(classifier.isWeakSingleStrike(first, second), isTrue);
    });

    test('одновременное касание (0 мс) — толчок', () {
      final first = contact(1, 100, 100, 1000);
      final second = contact(2, 200, 100, 1000);
      expect(classifier.classify(first, second), TwoFingerVerdict.powerPush);
    });
  });

  group('Физиология касания', () {
    test('расстояние считается между центрами точек касания', () {
      final a = contact(1, 0, 0, 0);
      final b = contact(2, 30, 40, 0); // 3-4-5: ровно 50 pt
      expect(a.distanceTo(b), closeTo(50, 0.001));
    });

    test('сценарий «два пальца одной руки» и «пальцы обеих рук» равнозначны',
        () {
      // Классификатор оперирует только дистанцией и временем: близкая
      // пара (указательный+средний одной руки, ~60 pt) и дальняя
      // (большие пальцы обеих рук, ~230 pt) дают одинаковый вердикт.
      final near1 = contact(1, 100, 100, 0);
      final near2 = contact(2, 160, 100, 60);
      final far1 = contact(3, 100, 100, 0);
      final far2 = contact(4, 330, 100, 60);
      expect(
        classifier.classify(near1, near2),
        TwoFingerVerdict.powerPush,
      );
      expect(classifier.classify(far1, far2), TwoFingerVerdict.powerPush);
    });
  });
}
