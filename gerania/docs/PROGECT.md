# Gerania — обзор проекта (контекст для моделей)

Нативное macOS-приложение (Apple Silicon, macOS 15+, лучший вид на 26+): «Гера» — голосовой и текстовый фронтенд Hermes Agent. Плавающая HUD-панель, мини-окно ввода по глобальному хоткею, иконка в меню-баре, обычное приложение с окном настроек.

## Корень репозитория
`/Users/stepan2/dev/gerania`
- `gerania.xcodeproj/` — Xcode-проект (схема `gerania`, нижний регистр). НЕ редактировать `*.pbxproj`/`*.xcscheme`.
- `gerania/` — синхронизируемая папка app-таргета: `GeraniaApp.swift` (тонкий @main), `Assets.xcassets`, `Resources/Voice/*` (Python «уши»), иконки.
- `gerania/Packages/GeraniaKit/` — локальный SwiftPM-пакет, весь основной код.
- `tools/` — пробники протокола, legacy-скрипт, Python-тесты, сборщик иконки.
- `scripts/` — `build.sh`, `test.sh`, `install.sh`, `setup_voice.sh`, `make_icon.sh`, `make_iconset.sh`, `smoke.sh`.
- `build/` — артефакты (gitignored).
- `gerania/docs/` — документация проекта (этот файл тут).

## Пакет GeraniaKit (`gerania/Packages/GeraniaKit`)
Таргеты (Swift 6, strict concurrency, macOS 15+):
- `GeraniaCore` (Foundation): модели, настройки, конечный автомат `GeraState`, текстовые утилиты (MarkdownStreamSanitizer, SentenceChunker, SpeechTextCleaner), логирование, AuditLog.
- `HermesKit` (Foundation): транспорты Hermes (Gateway WebSocket / ACP stdio / one-shot), события `HermesEvent`, SessionStore, поиск бинаря hermes, DesktopLauncher, ToolDetail/ToolResultSummary.
- `VoiceKit` (AVFoundation/AppKit): VoiceBridge (Python IPC), Speaker (TTS), SoundPlayer.
- `RealtimeKit`: Gemini Live (WebSocket + AVAudioEngine), LiveConversation, LiveStartup, LiveEndMatcher/Detector.
- `GeraniaUI` (AppKit+SwiftUI): панели, вьюхи, меню-бар, окно приложения (`Main/`), настройки, AppModel (оркестратор), хоткеи.
- `gerania-cli` — executable для проверки транспорта: `swift run gerania-cli "текст"`.
- `live-probe` — CLI-спайк Gemini Live.
Продукт-библиотека `GeraniaKit` = все пять.

## Ключевые файлы
- `gerania/GeraniaApp.swift` — @main, тонкий.
- `gerania/Packages/GeraniaKit/Sources/GeraniaUI/AppModel.swift` — оркестратор (294 строк), расширения `AppModel+*.swift`.
- `gerania/Packages/GeraniaKit/Sources/GeraniaCore/Reducer.swift` — конечный автомат `GeraState`.
- `gerania/Packages/GeraniaKit/Sources/HermesKit/HermesTransport` (протокол) + транспорты.
- `gerania/Resources/Voice/gera_ears.py` — «уши» (NDJSON IPC), копия логики `tools/legacy/wake_agent.py` (эталон, не менять).
- `gerania/Info.plist` — URL-схема `gerania://`, `CFBundleIconFile = GeraIcon`.

## Документация (`gerania/docs/`)
- `AGENTS.md` (в `gerania/`) — главные правила проекта, архитектура, команды.
- `HERMES_PROTOCOL.md` — истина о протоколе Hermes.
- `VOICE_IPC.md` — схема NDJSON голоса.
- `PROGRESS.md` — история этапов и известные проблемы.
- `DECISIONS.md` — ADR-lite решения.
- `HUMAN_TODO.md` — ручные шаги в Xcode/системе.
- `ROADMAP.md` — план развития (этапы 1–2 закрыты).
- `protocol-samples/*.jsonl` — записанные кадры протокола (фикстуры).

## Зависимости (только эти)
- `gonzalezreal/textual` — рендер markdown.
- `sindresorhus/KeyboardShortcuts` — глобальные хоткеи.
Автозапуск — `ServiceManagement.SMAppService`. Звуки синтезированы (`SoundCueSynthesizer`).

## Команды
```bash
# из корня репозитория
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path gerania/Packages/GeraniaKit --scratch-path build/swiftpm
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test  --package-path gerania/Packages/GeraniaKit --scratch-path build/swiftpm
xcodebuild -project gerania.xcodeproj -scheme gerania -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
<python> -m pytest tools/voice_tests -q
swiftformat --lint Packages Gerania && swiftlint lint --quiet
```
Всё обёрнуто в `scripts/test.sh` и `/verify`. Задача не считается выполненной, пока не зелёный.

## Запреты (кратко)
- Не редактировать `*.pbxproj`, `*.xcscheme`, `*.entitlements`.
- Не включать App Sandbox. Не добавлять зависимостей без записи в DECISIONS.md.
- Не выполнять команды Hermes, меняющие состояние пользователя.
- Не трогать `tools/legacy/wake_agent.py`.
- `rm -rf` только внутри `build/` и `.build/`. Никаких `sudo`.

## Текущий статус
Этапы 1 (роутер бесплатных моделей) и 2 (компьютер/cua-driver, итоги инструментов, журнал действий) закрыты. Осталось: живой сценарий «Гера, открой YouTube и найди видео про SwiftUI» на бесплатной модели (по желанию). Живой диалог Gemini Live не проверен E2E — нет `GEMINI_API_KEY`.
