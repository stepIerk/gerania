# AGENTS.md — Gerania (голосовой и текстовый фронтенд Hermes Agent для macOS)

## Продукт
Нативное macOS-приложение (Apple Silicon, macOS 15+, лучший вид на 26+) — «Гера»:
- Плавающая HUD-панель: NSPanel без рамки, не забирает фокус, на всех Spaces, поверх full-screen.
  Показывает: слушаю → распознаю → думаю → потоковый ответ (markdown) → готово.
- Мини-окно ввода текста по глобальному хоткею (по умолчанию ⌃⌥Space), со сменой чата.
- Значок в меню-баре (состояние + меню), автозапуск при входе (SMAppService).
- Приложение обычное (политика `.regular`): своя иконка в Dock, меню приложения, ⌘Q.
  Окно приложения (`GeraniaUI/Main/`): приветствие, кнопка «Запустить Геранию» и все
  настройки. Открывается при запуске, по клику на иконку в Dock, из меню-бара и по ⌘,.
  Голос поднимается по кнопке (микрофон спрашивают в ответ на действие человека);
  при автозапуске при входе голос поднимается тихо, без окна.
- Экран загрузки при запуске: `gerania/GeraLoading.gif` (цветок на чёрном фоне) проигрывается
  целиком **внутри окна приложения**: окно открывается чёрным, потом чёрный слой тает
  и под ним видны настройки. GIF разбирается через ImageIO
  (`GeraniaUI/Main/SplashAnimation.swift`), кадры показываются по своему таймеру.
- Голос: wake word «Гера» (с допуском помех), barge-in, стоп-слова. Распознавание —
  дочерний Python-процесс (mlx-whisper, логика из tools/legacy/wake_agent.py + быстрый
  разбор реплики на ходу). Озвучка — в Swift, потоково, по предложениям.
- Живой диалог (опция, по умолчанию выключен): после «Гера» приложение параллельно
  подключается к Gemini, но Python-уши остаются на микрофоне, пока Whisper не распознает
  первую фразу целиком; затем `suspend`, микрофон забирает Gemini 3.8 Live, полный текст
  уходит первым ходом. Дальше диалог идёт непрерывно; стоп-слова ловит Swift по
  транскрипту Gemini, на выходе Python получает `resume`. Диалог завершается по прощанию
  (`finish_conversation` или `LiveEndMatcher`), а не только по 60 секундам тишины;
  таймаут остаётся страховкой.
- Ответы Hermes идут ПОТОКОМ. Сессии общие с Hermes Desktop/CLI; можно перейти в выбранную сессию.
UI-язык: русский. Код, идентификаторы, комментарии, коммиты — английский.

## Раскладка репозитория
- `gerania.xcodeproj` — создан человеком (в родительской папке, схема `gerania`). **НИКОГДА не редактируй `project.pbxproj`** и файлы `*.xcscheme`.
  Если нужна настройка таргета (capability, Info.plist-ключ, URL type, build setting) — НЕ делай её сам,
  а добавь пункт в `docs/HUMAN_TODO.md` с точной инструкцией «где кликнуть в Xcode» и сообщи в итоговом ответе.
- `Gerania/` — app-таргет, папка СИНХРОНИЗИРУЕМАЯ (файлы на диске попадают в таргет автоматически).
  Здесь только: `GeraniaApp.swift` (тонкий @main), `Assets.xcassets`, `Resources/Voice/*` (Python «уши»),
  `GeraniaIcon.png` (исходник иконки) и `GeraIcon.icns` (иконка для бандла).
  Всё, что лежит в этой папке, попадает в таргет: `.swift`-файлы здесь компилируются,
  поэтому инструмент сборки иконки живёт в `tools/icon/`.
- `Packages/GeraniaKit/` (`gerania/Packages/GeraniaKit` от корня репозитория) — локальный SwiftPM-пакет, ВЕСЬ основной код. Зависимости добавляются ТОЛЬКО сюда.
  Таргеты:
  - `GeraniaCore` — Foundation-only: модели, настройки, конечный автомат, текстовые утилиты
    (MarkdownStreamSanitizer, SentenceChunker, SpeechTextCleaner), логирование.
  - `HermesKit` — Foundation-only: транспорты Hermes (Gateway WebSocket / ACP stdio / one-shot),
    модели событий, SessionStore, поиск бинаря hermes, DesktopLauncher.
  - `VoiceKit` — AVFoundation/AppKit: VoiceBridge (Python IPC), Speaker (TTS), SoundPlayer.
  - `RealtimeKit` — Gemini Live (WebSocket + AVAudioEngine), live-диалог, Keychain-ключ.
  - `GeraniaUI` — AppKit+SwiftUI: панели, вьюхи, меню-бар, окно приложения (`Main/`),
    настройки, AppModel (оркестратор), хоткеи.
  - `gerania-cli` — executable для проверки транспорта без UI: `swift run gerania-cli "текст"`.
  - `live-probe` — CLI-спайк Gemini Live: `swift run live-probe --text "привет"`.
  Продукт-библиотека `GeraniaKit` = [GeraniaCore, HermesKit, VoiceKit, RealtimeKit, GeraniaUI].
- `tools/` — пробники протокола (`tools/probe/`), legacy-скрипт (`tools/legacy/wake_agent.py` —
  ЭТАЛОН поведения, НЕ МЕНЯТЬ), Python-тесты (`tools/voice_tests/`), сборщик иконки
  (`tools/icon/make_icon.swift`, запускается из `scripts/make_icon.sh`).
- `gerania/Resources/Voice/gera_ears.py` — «уши» приложения: копия логики эталона без Hermes,
  озвучки и звуков. Общается с приложением по NDJSON (схема — `docs/VOICE_IPC.md`).
- `scripts/` — `build.sh`, `test.sh`, `install.sh`, `setup_voice.sh`, `make_icon.sh`, `make_iconset.sh`, `smoke.sh`.
- `docs/` — `HERMES_PROTOCOL.md` (истина о протоколе), `VOICE_IPC.md` (схема голоса),
  `PROGRESS.md`, `DECISIONS.md`, `HUMAN_TODO.md`,
  `protocol-samples/*.jsonl` (записанные реальные кадры протокола — фикстуры для тестов).

## Технологии и версии
- Swift 6 (strict concurrency), swift-tools-version 6.0+, `platforms: [.macOS(.v15)]`.
- SwiftUI + AppKit (NSPanel, NSHostingView). Наблюдаемость — `@Observable` (Observation), не Combine.
- Зависимости (только эти, новые — с обоснованием в DECISIONS.md):
  - `https://github.com/gonzalezreal/textual` — рендер markdown (преемник MarkdownUI).
    Если API Textual не позволяет нужное — fallback `gonzalezreal/swift-markdown-ui` 2.4.x, решение записать.
  - `https://github.com/sindresorhus/KeyboardShortcuts` — глобальные хоткеи (без Accessibility).
- Автозапуск — `ServiceManagement.SMAppService.mainApp` (без сторонних пакетов).
- Звуки — синтезированные куи (`SoundCueSynthesizer` → `SoundPlayer` на `AVAudioEngine`):
  короткие, тише речи, один звук = одно состояние, новый отменяет предыдущий.
- TTS — `AVSpeechSynthesizer` (голос Milena, ru-RU), fallback — процесс `/usr/bin/say`.
- Логи — `os.Logger(subsystem: <bundle id или "com.yourname.Gerania">, category: ...)`. Никаких print в Swift.
- Liquid Glass: `if #available(macOS 26, *) { .glassEffect(...) } else { .background(.ultraThinMaterial) }`.
  Перед использованием API macOS 26 проверь его наличие в SDK: `xcrun --show-sdk-version`, и что код компилируется.

## Архитектурные правила
- UI-код и AppModel — `@MainActor`. Процессы, сокеты, парсинг — `actor`'ы или `Sendable`-типы.
- Все транспорты Hermes реализуют один протокол:
  public protocol HermesTransport: Sendable {
      var kind: TransportKind { get }
      func connect() async throws
      func listSessions(limit: Int) async throws -> [SessionSummary]
      func newSession(title: String?) async throws -> SessionID
      func send(_ text: String, session: SessionID?, mode: PromptMode) -> AsyncThrowingStream<HermesEvent, Error>
      func interrupt(session: SessionID) async
      func respond(to request: ServerRequest, with answer: ServerRequestAnswer) async throws
  }
  public enum HermesEvent: Sendable, Equatable {
      case sessionBound(SessionID)
      case thinkingStarted
      case reasoningDelta(String)
      case textDelta(String)
      case toolStarted(id: String, name: String, detail: String?)
      case toolFinished(id: String, ok: Bool)
      case serverRequest(ServerRequest)      // approval / clarify
      case completed(finalText: String?)
      case cancelled
      case failed(HermesError)
  }
  ```
  Точные имена методов и полей протоколов Hermes берутся ТОЛЬКО из `docs/HERMES_PROTOCOL.md`
  и `docs/protocol-samples/`. Не выдумывай JSON-поля. Если поле неизвестно — разведай (сабагент `protocol-scout`).
- Выбор транспорта: Auto = Gateway → ACP → OneShot, с логированием причины отката. Ручной выбор — в настройках.
- Состояние UI — единый конечный автомат `GeraState`:
  `idle | listening(deadline) | transcribing | thinking(tools:[ToolChip]) | streaming | speaking | done | error(msg) | awaitingApproval(req)`.
  Переходы — только через `AppModel.dispatch(_ action:)`; reducer покрыт тестами.
- Python «уши» общаются с Swift только через NDJSON (stdout → события, stdin ← команды), логи — в stderr.
  Схема — `docs/VOICE_IPC.md` (создаётся на этапе 7), менять только синхронно с обеих сторон и с тестами.
- Никакого HTTP-сервера в приложении. Для тестов/скриптов — URL-схема `gerania://` (см. ниже).

## Отладочная URL-схема (для самопроверки агентами)
Обрабатывается в `AppModel.handle(url:)`; debug-маршруты активны только при `GERA_DEBUG=1` или в Debug-сборке:
- `gerania://ask?text=...` — отправить текст в текущий чат (как из мини-окна)
- `gerania://input` — открыть мини-окно ввода (`?text=...` — с текстом, `?chats=1` — со списком чатов)
- `gerania://listen` — эмулировать wake (начать слушать)
- `gerania://start` — запустить Герю (поднять уши); из Shortcuts и из командной строки
- `gerania://stop` — стоп (interrupt + заглушить TTS)
- `gerania://debug/state?name=listening|thinking|streaming|error|done` — показать HUD в состоянии с фейковыми данными
- `gerania://debug/stream?sample=markdown|long|code|table` — проиграть фейковый стрим из фикстуры
- `gerania://session/open?id=...` — переключить текущий чат

## Команды сборки и проверки
```bash
# из корня репозитория (/Users/stepan2/dev/gerania), не из gerania/
# быстрые: пакет (scratch-path — в build/ проекта, НЕ внутри gerania/)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --package-path gerania/Packages/GeraniaKit --scratch-path build/swiftpm
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test  --package-path gerania/Packages/GeraniaKit --scratch-path build/swiftpm
# приложение целиком (схема и проект — в нижнем регистре)
xcodebuild -project gerania.xcodeproj -scheme gerania -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build 2>&1 | xcbeautify
# python-уши
<python> -m pytest tools/voice_tests -q
# стиль
swiftformat --lint Packages Gerania && swiftlint lint --quiet
```
Всё это обёрнуто в `scripts/test.sh` и команду `/verify`. Задача НЕ считается выполненной, пока `/verify` не зелёный.
Запуск собранного приложения для smoke-теста: `scripts/smoke.sh` (собирает, запускает .app, гоняет
`gerania://debug/...`, делает `screencapture -x build/screens/<name>.png`, собирает `log show` за последние 2 минуты).
Если твоя модель умеет читать изображения — открой скриншоты и оцени UI сама.

## Запреты
- Не редактировать `*.pbxproj`, `*.xcscheme`, `*.entitlements` (кроме случая, если человек явно попросил).
- Не включать App Sandbox. Не добавлять зависимостей сверх списка без записи в DECISIONS.md.
- Не выполнять команды Hermes, меняющие состояние пользователя: `sessions delete|prune|rename`, `config set`,
  `model`, `update`, `uninstall`, `gateway stop`. Разрешено: `--help`, `--version`, `acp --check`,
  `gateway ensure --json --timeout N`, `sessions list`, тестовые промпты в НОВОЙ сессии с титулом `gerania-probe-*`.
- Не открывать `~/.hermes/state.db` на запись. Только `sqlite3 -readonly` / `SQLITE_OPEN_READONLY`.
- Не логировать и не коммитить ключи из `~/.hermes/.env`, токены и тикеты gateway.
- `rm -rf` — только внутри `build/` и `.build/`. Никаких `sudo`.
- Не трогать `tools/legacy/wake_agent.py` (эталон поведения). Логику «ушей» держать в
  `gerania/Resources/Voice/gera_ears.py`. Отличия от эталона намеренные и описаны в
  `docs/DECISIONS.md`: допуск помех в wake-слове («Гера.», «ГераОткрой», «Гиро»),
  распознавание реплики на ходу маленькой моделью, отправка команды на паузе.
- Голос: в классическом режиме решения (wake/stop/команда) принимает Python, приложение
  только реагирует на события `docs/VOICE_IPC.md`. Исключение — живой диалог: после wake
  Python получает `suspend`, Gemini сам транскрибирует речь, а стоп-фразу ловит
  `LiveStopMatcher` в Swift (см. `docs/DECISIONS.md`, R2). Не дублировать классическое
  распознавание в Swift.

## Стиль кода
- Маленькие файлы (≤ 300 строк), один тип — один файл. Доступ: `public` только то, что нужно GeraniaUI/app.
- Никаких `!`-распаковок и `try!` вне тестов. Ошибки — типизированные `enum ...: Error, LocalizedError` с русским описанием для UI.
- Анимации: `.spring(response: 0.35, dampingFraction: 0.86)` как базовая; уважать `accessibilityReduceMotion`.
- Каждый новый модуль — с тестами (Swift Testing: `import Testing`, `@Test`, `#expect`).

## Ведение документации (обязательно в конце каждой задачи)
- `docs/PROGRESS.md` — что сделано, что осталось, известные баги (дата, этап).
- `docs/DECISIONS.md` — архитектурные решения и почему (ADR-lite, по 3–6 строк).
- `docs/HUMAN_TODO.md` — что должен сделать человек в Xcode/системе, с точными шагами.
````
