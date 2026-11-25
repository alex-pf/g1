# g1

G1 — детская игра, первый продукт фабрики Fabric

## Hello world PWA

Точка входа продукта (issue #1): скелет Flutter-приложения с web-сборкой (PWA).
Долгосрочный путь: **PWA (hello world) → функционал → Android → iPhone**.

- Приложение: `lib/main.dart` — экран «Hello world», заголовок **G1**.
- PWA: `web/manifest.json` (имя G1, иконки), service worker генерируется Flutter при сборке.
- CI: `.github/workflows/ci.yml` — `flutter analyze` + `flutter test` + `flutter build web` на каждый PR в main.

## Разработка

Требуется Flutter SDK stable (в git не коммитится, ставится отдельно, например в `~/flutter`).

```sh
flutter pub get        # зависимости
flutter analyze        # статический анализ
flutter test           # тесты
flutter build web      # релизная web-сборка (build/web)
flutter run -d chrome  # локальный запуск
```
