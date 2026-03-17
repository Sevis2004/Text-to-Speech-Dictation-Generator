# Dictation Project

## Назначение
Генерация аудио-диктантов:
- TTS (Yandex Cloud)
- разбиение текста
- сборка аудио
- генерация сайта

---

## Архитектура

- `generate_dictations.ps1` — основной скрипт
- `test_split.ps1` — тест разбиения (legacy vs improved)
- `index.template.html` — шаблон страницы
- `dictations.json` — данные

---

## Разбиение текста

Режимы:
- `legacy`
- `improved` — используется сейчас

```json
"SplitMode": "improved"

## Git policy

- `master` — stable working version
- all changes are developed in `feature/*` or `fix/*` branches
- every usable cross-PC stable state gets a version tag `vX.Y.Z`
- do not commit experiments directly to `master`