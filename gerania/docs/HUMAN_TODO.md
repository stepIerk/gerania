# Что должен сделать человек

## 1. Подключить локальный пакет (выполнено, xcodebuild проходит)
1. Откройте `gerania.xcodeproj` (родительская папка проекта) в Xcode 27.2.
2. `File → Add Package Dependencies… → Add Local…` и выберите папку
   `gerania/Packages/GeraniaKit` (рядом с `AGENTS.md`), либо перетащите эту папку в навигатор.
3. Выберите продукт `GeraniaKit` и добавьте его в таргет `gerania`.
   Проверка: `Gerania` → `General` → `Frameworks, Libraries, and Embedded Content` содержит `GeraniaKit`.
4. Удалите `LIBRARY_SEARCH_PATHS` с путём `$(PROJECT_DIR)/gerania/Packages/GeraniaKit/.build/out/Products/Debug`
   (`Gerania` → `Build Settings` → поиск `Library Search Paths`), если Xcode предложит.

## 2. Настройки таргета
`Gerania` → `General`:
- `Minimum Deployments`: macOS 15.0.
- `Supported Destinations`: оставить только macOS.
- `App Icon`: можно позже, через `scripts/make_iconset.sh`.

`Gerania` → `Build Settings`:
- `Swift Language Version`: Swift 6.
- `Swift Concurrency`: Complete (Strict Concurrency Checking = Complete).
- `Product Bundle Identifier`: например `com.yourname.Gerania`.

`Gerania` → `Signing & Capabilities`:
- Удалить `App Sandbox` (по правилам проекта sandbox запрещён).

## 3. Info / URL-схема / агент
`gerania/Info.plist` (файл уже создан, схема `gerania` прописана — smoke-тест её использует):
- ~~Добавить ключ `LSUIElement` = `YES`~~ **НЕ ДЕЛАЙТЕ.** Приложение стало обычным:
  иконка в Dock, меню приложения, ⌘Q. `LSUIElement` снова спрячет приложение в меню-баре.
  Политика задаётся в коде: `NSApp.setActivationPolicy(.regular)`.
- Роль URL-схемы сейчас `Editor`; для Gerania правильнее `Viewer`.
- `CFBundleIconFile = GeraIcon` уже прописана — иконка работает без Xcode.

## 3а. Иконка и имя приложения (по желанию, два клика)
1. `Gerania` → `General` → `App Icon` → выбрать `AppIcon` (каталог уже собран
   скриптом `scripts/make_icon.sh`). Это нужно только чтобы Xcode знал об иконке:
   сейчас приложение берёт иконку из `GeraIcon.icns` в Resources.
2. `Gerania` → `Build Settings` → `Info.plist` → `Bundle name` = `Гера`
   (`INFOPLIST_KEY_CFBundleName`). Сейчас в меню macOS приложение называется «gerania»:
   `CFBundleName` из файла перебивается системой сборки.

## 5. Голос (этап 7)
1. Установите зависимости: `scripts/setup_voice.sh` (создаёт окружение
   `~/Library/Application Support/Gerania/voice-venv` — внутри папки приложения держать нельзя,
   Xcode копирует её в Resources и сборка падает). Скрипт сам запишет путь в настройки Геры
   (`defaults com.sykorn.gerania pythonPath`).
2. Выдайте доступ к микрофону: Системные настройки → Конфиденциальность и безопасность →
   Микрофон → включите Gerania (приложение спросит при первом запуске голоса).
3. Скачайте русский голос Milena Premium: Системные настройки → Доступность → Речь →
   Системные голоса → Русский → «Milena Premium» → Управлять → Загрузить.
   Без него Геря говорит системным голосом (качество ниже).
4. Проверьте порог микрофона:
   `~/Library/Application\ Support/Gerania/voice-venv/bin/python gerania/Resources/Voice/gera_ears.py --levels`
   — говорите и стучите по столу, подберите `MIN_RMS` в настройках Gerania (по умолчанию 0.005).

## 6. Проверить голос без микрофона (по желанию):
   `say -v Milena -o /tmp/gera.aiff "Гера, какая погода в Москве"` →
   `afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/gera.aiff /tmp/gera.wav` →
   `~/Library/Application\ Support/Gerania/voice-venv/bin/python tools/voice/check_wake.py /tmp/gera.wav`.

7. После этого
`scripts/test.sh` и `scripts/smoke.sh` проходят, этапы 2–7 закрыты. Осталось пройти ручные
чек-листы из `docs/PROGRESS.md` (панели и голос) и доделать интеграцию голоса с Hermes.

## 8. Живой диалог Gemini Live (после релиза, по желанию)
1. Получите ключ Gemini API в Google AI Studio и включите биллинг: live-аудио
   платное (примерно $3/1M токенов аудио-входа и $12/1M аудио-выхода).
2. В окне Геры → «Голос» → «Живой диалог Gemini» вставьте ключ и нажмите
   «Сохранить» (ключ уходит в Keychain, не в UserDefaults). Включите тумблер.
   Если после пересборки HUD пишет «Keychain не отдал ключ Gemini», просто
   сохраните ключ ещё раз: ACL элемента привязан к подписи сборки.
3. Проверьте доступ к микрофону (Системные настройки → Конфиденциальность →
   Микрофон → Gerania) и разрешите уведомления, если нужны отчёты о задачах.
   Для проверки AEC/микрофона без ключа: `build/swiftpm/debug/live-probe
   --audio-only --seconds 3` (в логе должен появиться «first mic chunk»).
4. Ручной чек-лист живого диалога:
   - сказать «Гера» → HUD «Диалог», услышать ответ;
   - перебить Геру голосом → ответ должен замолчать (в режиме эхоподавления);
   - «Гера, открой Safari» → задача запускается, Гера говорит «запущено»;
   - «что с задачей?» → статус; дождаться завершения → Гера сама сообщает итог;
   - «стоп» / «хватит» → диалог закрывается, микрофон возвращается Python;
   - задача просит разрешение → Гера спрашивает, «разреши/отклони» отвечает;
   - задача просит уточнение → Гера задаёт вопрос и передаёт свободный ответ;
   - после паузы 60 с → диалог закрывается сам.
5. Если эхо или микрофон не отпускается: в настройках пока нет переключателя
   режима, полудуплекс включается автоматически; для диагностики используйте
   `live-probe --half-duplex --text "привет"` (нужен `GEMINI_API_KEY` в env),
   а без ключа — `live-probe --audio-only --half-duplex --seconds 3`.

## 9. Управление компьютером: права cua-driver (этап 2)
`computer_use` работает через сторонний драйвер `CuaDriver.app`. Права TCC
принадлежат **ему**, а не Герании и не hermes: драйвер сам кликает и снимает экран.

Точная identity:
- bundle id: `com.trycua.driver`;
- путь: `~/.hermes/tools/cua-driver-<версия>-darwin-arm64/CuaDriver.app`;
- проверка: `hermes computer-use doctor --json` (в отчёте `bundle_identity`,
  `tcc_accessibility`, `tcc_screen_recording`).

Шаги на новой машине:
1. Установить драйвер: `hermes computer-use install`.
2. Запросить права: `hermes computer-use permissions grant`. macOS покажет диалоги,
   привязанные к CuaDriver, а не к терминалу.
3. Если диалог не появился: Системные настройки → Конфиденциальность и безопасность →
   «Универсальный доступ» и «Запись экрана» → включить **CuaDriver** (не Gerania).
4. Проверить: `hermes computer-use doctor` — все проверки `pass`, `overall: ok`.
5. В Герании: Hermes → «Компьютер» → «Проверить»; карточка должна стать зелёной.
6. Если переключатель в System Settings уже включён, а драйвер пишет «нет прав»,
   грант устарел после обновления драйвера:
   `tccutil reset ScreenCapture com.trycua.driver` и снова
   `hermes computer-use permissions grant`.

На этой машине (2026-11-17) оба разрешения уже выданы, `doctor` возвращает `ok`.

## 10. Напоминания: проверка после изменений 2026-11-18
Xcode-настроек и ключей Info.plist не нужно: уведомления не требуют capability
(sandbox выключен), нужен только bundle id, а он уже есть. Проверка:

1. Сборка и тесты из корня репозитория:
   `bash gerania/scripts/test.sh`. Должно закончиться сборкой `gerania.app`.
   Код писался без компилятора, поэтому при ошибке пришлите вывод целиком.
2. Живой Hermes на временной папке (реальные задачи не трогаются):
   `bash gerania/scripts/cron_smoke.sh`. Последняя строка: `OK: ...`.
3. Запустите собранное приложение, нажмите «Запустить Геранию» и разрешите
   уведомления. Если отказали — Системные настройки → Уведомления → gerania →
   «Разрешить уведомления» (стиль «Предупреждения», чтобы баннер не исчезал сам).
4. Окно → «Планы» → «Доставка напоминаний»: должно быть «Планировщик Hermes работает».
   Если нет — «Запустить планировщик».
5. «Создать» → шаблон «Напоминание», расписание `in 2m`, название
   `gerania-test-ui`. Закройте окно (Гера остаётся в меню-баре) и подождите 2–3 минуты:
   должен прийти баннер «Гера: gerania-test-ui» и HUD-карточка; клик по баннеру
   открывает `.md`. Затем удалите задачу во вкладке.
6. Из чата: «Гера, напомни через 2 минуты выпить воды» → задача появится в «Планах»
   после «Обновить», баннер придёт так же.
7. Приложение завершено (⌘Q) во время срабатывания: Hermes выполнит план сам, а
   баннер придёт при следующем запуске Геры. Это ожидаемое поведение (DECISIONS).
