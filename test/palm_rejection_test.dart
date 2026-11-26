import 'package:flutter_test/flutter_test.dart';

import 'package:g1/game/hitboxes/palm_rejection.dart';
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
  group('Конфигурация palm rejection (issue #18, раздел 3)', () {
    test('пороги спецификации: 125 pt, 250 мс, 18 pt, пятно 48–75 pt', () {
      expect(PalmRejectionConfig.maxFingerContactDiameterPt, 125);
      expect(PalmRejectionConfig.stationarySupportMs, 250);
      expect(PalmRejectionConfig.edgeBufferPt, 18);
      expect(PalmRejectionConfig.minFingerContactDiameterPt, 48);
      expect(PalmRejectionConfig.maxTypicalFingerContactDiameterPt, 75);
    });
  });

  group('Фильтр площади и формы пятна контакта', () {
    const filter = ContactShapeFilter();

    test('пятно подушечки пальца 48–75 pt принимается', () {
      expect(filter.accepts(contact(1, 100, 100, 0, diameter: 48)), isTrue);
      expect(filter.accepts(contact(2, 100, 100, 0, diameter: 75)), isTrue);
    });

    test('граница 125 pt: ровно 125 принимается, 126 — ладонь', () {
      expect(filter.accepts(contact(1, 100, 100, 0, diameter: 125)), isTrue);
      expect(filter.accepts(contact(2, 100, 100, 0, diameter: 126)), isFalse);
      expect(
        filter.rejectReason(contact(3, 100, 100, 0, diameter: 126)),
        PalmRejectionReason.oversizedContact,
      );
    });

    test('вытянутое овальное пятно (ребро ладони) отбраковывается', () {
      final palm = contact(1, 100, 100, 0, diameter: 60, elongated: true);
      expect(filter.accepts(palm), isFalse);
      expect(
        filter.rejectReason(palm),
        PalmRejectionReason.elongatedContact,
      );
    });

    test('ладонь не сбивает хрупких гигантов и капсулы: отбраковка полная',
        () {
      // Отбракованное касание не доходит до разрешителя вообще — проверяем,
      // что обе причины ладони дают отказ.
      expect(
        filter.rejectReason(contact(1, 0, 0, 0, diameter: 200)),
        isNotNull,
      );
      expect(
        filter.rejectReason(contact(2, 0, 0, 0, elongated: true)),
        isNotNull,
      );
    });
  });

  group('Фильтр неподвижной опоры (250 мс)', () {
    test('неподвижность 250 мс — ещё касание, 251 мс — опорная рука', () {
      final filter = StationarySupportFilter();
      final point = contact(1, 500, 500, 0);
      expect(filter.isSupportHand(point, 0), isFalse);
      expect(filter.isSupportHand(point, 250), isFalse);
      expect(filter.isSupportHand(point, 251), isTrue);
    });

    test('движущийся палец никогда не становится опорой', () {
      final filter = StationarySupportFilter();
      for (var t = 0; t <= 1000; t += 50) {
        final moving = contact(1, 500 + t * 0.2, 500, t);
        expect(filter.isSupportHand(moving, t), isFalse);
      }
    });

    test('микродрожание в допуске 4 pt не сбрасывает отсчёт', () {
      final filter = StationarySupportFilter();
      expect(filter.isSupportHand(contact(1, 500, 500, 0), 0), isFalse);
      // Дрожание на 2 pt — всё ещё та же неподвижная точка.
      expect(filter.isSupportHand(contact(1, 502, 501, 0), 200), isFalse);
      expect(filter.isSupportHand(contact(1, 501, 502, 0), 251), isTrue);
    });

    test('объект, пролетающий под точкой, сбрасывает отсчёт опоры', () {
      final filter = StationarySupportFilter();
      final point = contact(1, 500, 500, 0);
      expect(filter.isSupportHand(point, 0), isFalse);
      // На 200 мс под пальцем пролетел объект — игрок держит палец над целью.
      expect(
        filter.isSupportHand(point, 200, objectUnderPoint: true),
        isFalse,
      );
      // Отсчёт начался заново: на 400 мс (200 с объекта) ещё не опора.
      expect(filter.isSupportHand(point, 400), isFalse);
      expect(filter.isSupportHand(point, 451), isTrue);
    });

    test('маркировка держится до отрыва, даже если палец снова пошевелился',
        () {
      final filter = StationarySupportFilter();
      final point = contact(1, 500, 500, 0);
      filter.isSupportHand(point, 0);
      expect(filter.isSupportHand(point, 251), isTrue);
      // Опорная рука пошевелилась — всё равно игнорируется до отрыва.
      expect(filter.isSupportHand(contact(1, 520, 500, 0), 300), isTrue);
      // Отрыв от экрана сбрасывает маркировку.
      filter.lift(1);
      expect(filter.isSupportHand(contact(1, 520, 500, 0), 310), isFalse);
    });
  });

  group('Краевой буфер хвата (18 pt)', () {
    // Экран планшета 1024×768 pt.
    const filter = EdgeBufferFilter(screenWidthPt: 1024, screenHeightPt: 768);

    test('касание в буфере, направленное к краю, игнорируется', () {
      // Левый край, движение влево (к краю) — палец, держащий планшет.
      expect(filter.shouldIgnoreStart(10, 500, dxPt: -5), isTrue);
      // Нижний край, движение вниз.
      expect(filter.shouldIgnoreStart(500, 760, dxPt: 0, dyPt: 4), isTrue);
      // Правый край, движение вправо.
      expect(filter.shouldIgnoreStart(1015, 300, dxPt: 3), isTrue);
      // Верхний край, движение вверх.
      expect(filter.shouldIgnoreStart(500, 8, dxPt: 0, dyPt: -3), isTrue);
    });

    test('статичное касание в буфере — хват корпуса, игнорируется', () {
      expect(filter.shouldIgnoreStart(10, 500), isTrue);
    });

    test('касание в буфере, направленное в игровое поле, принимается', () {
      // Свайп начался у самого края, но идёт в поле — это жест игрока.
      expect(filter.shouldIgnoreStart(10, 500, dxPt: 6), isFalse);
      expect(filter.shouldIgnoreStart(500, 760, dxPt: 0, dyPt: -4), isFalse);
    });

    test('касание вне буфера никогда не игнорируется этим фильтром', () {
      expect(filter.shouldIgnoreStart(100, 500, dxPt: -5), isFalse);
      expect(filter.shouldIgnoreStart(500, 100, dxPt: 0, dyPt: -5), isFalse);
    });

    test('активный свайп из поля за край экрана не обрывается', () {
      final start = contact(1, 100, 500, 0);
      // Свайп ушёл за левый край вслед за астероидом.
      expect(filter.shouldInterruptActiveSwipe(start, -20, 500), isFalse);
      // И даже внутри буфера обрыва нет.
      expect(filter.shouldInterruptActiveSwipe(start, 10, 500), isFalse);
    });
  });
}
