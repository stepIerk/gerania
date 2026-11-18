# Протокол Hermes (проверено на живом gateway)

Источник истины — фикстуры `docs/protocol-samples/*.jsonl` и пробник `tools/probe/gateway_probe.py`.
Всё ниже проверено на Hermes Desktop/CLI gateway 11.11.2026.

## Gateway и WebSocket

```bash
hermes gateway ensure --json
```

В ответе: `endpoint.api_origin` (например `http://127.0.0.1:61040`) и путь `/api/ws`.
Тикет минтится через unix-сокет `<home>/gateway.sock` (или путь из `gateway.sock.path`):

```json
{"protocol":1,"id":1,"verb":"session-ticket","params":{"profile_id":"...","instance_id":"...","purpose":"interactive"}}
```

Ответ: `{"ok":true,"result":{"ticket":"..."}}`, TTL около 30 секунд.
Подключение: `ws://127.0.0.1:61040/api/ws` с subprotocol
`hermes-gateway-v1` и `hermes-gateway-ticket.<ticket>`.

Запущенный gateway обслуживает **canonical authority**: `gateway/run_api.py` →
`tui_gateway.ws.handle_ws` → `AuthorityConnection.dispatch` (`gateway/session_controls.py`).
Маршрут dashboard `hermes_cli/web_routers/chat_ws.py` — отдельный sidecar, не путать.

## Методы

- `client.capabilities {"server_requests": true}` — список server→client запросов.
- `runtime.describe` — возможности. Canonical: `durable-admission-v1`, `event-replay-v1`,
  `local-cli-create-v1`, `acp-editor-policy-v1`, `acp-session-mcp-v1`, `clarify-batch-v1`.
  Источники create: `acp, cli, gui, oneshot, tool, tui`.
- `session.list` — параметры `scope`, `limit`.
- `session.create` — `request_id`, `source`, `cwd`, `title`, `model`, `provider`.
  `cols` — только sidecar, canonical лишние ключи отвергает.
  Ответ: `session_id`, `stored_session_id`, `messages`, `message_count`, `todo_state`,
  `running`, `authority_epoch`, `replay_epoch`, `last_sequence`, `subscription_id`,
  `revision`, `execution_generation: 0`, `pending`, `prompts`, `info`.
- `prompt.submit` — на практике обязателен `submission_id` (или `input_id`), иначе
  `4001 invalid_params`. Ответ обычно `status:"queued"`, `execution_generation:null`.
- `session.interrupt` — `session_id` + `execution_generation` (int из `message.start`,
  не из create и не из submit). Остановка асинхронная.

## События

Envelope:

```json
{"method":"event","params":{"type":"message.delta","session_id":"...","payload":{...},
 "replay_epoch":1,"seq":42,"execution_generation":1,"authority_epoch":2}}
```

- `gateway.ready` — один раз: `skin`, `change_events`, `replay_epoch`.
- `message.start` — пустой payload, `execution_generation` в params.
- `message.delta` — `text, turn_id, segment, offset`; `offset` — символьный,
  `text:null` — граница сегмента.
- `tool.start` — `tool_id, name, context, tool_call_id, tool_name, args`.
- `tool.complete` — то же + `is_error, result` (JSON-строка), `duration_s`,
  `inline_diff`, `image_path`.
- `message.complete` — `text, content, admission_id, outcome, status, usage,
  persisted_turn{row_ids, complete, user_row_id, user_row_ids, final_assistant_row_id,
  submission_id}`, иногда `error_surface`.
- Прочие: `thinking.delta` (спиннер-тексты), `tool.generating`, `status.update`,
  `session.info`, `agent.step`, `session.title`, `session.usage`, `session.created`.

## Подтверждения

`approvals.mode = smart`: команды `rm -f`, `rm -rf /tmp/...`, `touch /etc/...`
авто-одобрены, approval-карточка не приходит. Варианты ответа: `once/session/always/deny`.

Approval в canonical gateway приходит **событием**, а не JSON-RPC server request:

```json
{"method":"event","params":{"type":"approval.request","session_id":"...",
 "execution_generation":1,"admission_id":"...","seq":11,
 "payload":{"kind":"approval","prompt_id":"09ba...","execution_generation":1,
  "command":"curl ... | sh","description":"pipe remote content to shell",
  "choices":["once","deny"],"timeout_s":300}}}
```

Ответ — обычный JSON-RPC вызов (не ответ на server request):

```json
{"jsonrpc":"2.0","id":N,"method":"approval.respond","params":{
 "session_id":"...","execution_generation":1,"prompt_id":"09ba...","choice":"deny"}}
```

Clarify: событие `clarify.request` (payload с `prompt_id`) → метод `clarify.respond`
с `session_id`, `execution_generation`, `prompt_id`, `answer`. Результат обоих —
`{"status":"resolved"|"already_resolved","prompt_id":"..."}`.

Legacy-клиент может получить JSON-RPC server request `approval`/`clarify`; на него
отвечают `{"choice":"..."}` / `{"answers":{...}}`. Неизвестные server-методы получают
JSON-RPC `-32601`.

## state.db (только чтение)

Путь: `~/.hermes/state.db`. Открывать с `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`,
busy timeout 200 мс.

Нужные колонки `sessions`: `id, source, title, started_at, last_activity_at,
message_count, cwd, archived`. `messages`: `session_id, role, content, timestamp, active`.
Список сессий (как в `SessionStore`):

```sql
SELECT s.id, COALESCE(s.title,''), s.source,
       COALESCE(s.last_activity_at, s.started_at, 0),
       COALESCE(s.started_at, 0), COALESCE(s.message_count, 0),
       COALESCE(s.cwd,''),
       COALESCE((SELECT m.content FROM messages m
                 WHERE m.session_id=s.id AND m.role='user' AND m.active=1
                 ORDER BY m.timestamp ASC LIMIT 1),'')
FROM sessions s WHERE s.archived=0
ORDER BY COALESCE(s.last_activity_at, s.started_at, 0) DESC LIMIT ?;
```

## ACP (`hermes acp`)

NDJSON JSON-RPC по stdin/stdout, stderr — только лог. Вызовы:
`initialize {protocolVersion:1, clientCapabilities:{}, clientInfo:{name,version}}` →
`session/new {cwd, mcpServers:[]}` → `session/prompt {sessionId, prompt:[{type:"text",
text}]}`. Ответ prompt — `{stopReason:"end_turn"|"cancelled"|"refusal"|...}`.
Продолжение — `session/load {sessionId, cwd, mcpServers:[]}` (при ошибке — новый session).
Отмена — notification `session/cancel {sessionId}`.

Поток — notification `session/update {sessionId, update:{sessionUpdate:...}}`:
`agent_message_chunk`/`agent_thought_chunk` (`content.text`), `tool_call`
(`toolCallId,title,rawInput`), `tool_call_update` (`toolCallId,status`).

Разрешение инструмента — server request `session/request_permission`
(`sessionId`, `toolCall`, `options[{optionId,name,kind}]`). Ответ:
`{"outcome":{"outcome":"selected","optionId":"..."}}` либо
`{"outcome":{"outcome":"cancelled"}}`.

## One-shot и CLI

- `hermes -z "..."` — только финальный текст.
- `hermes chat -q "..." --format stream-json` — JSONL-поток.
- `--usage-file` содержит `session_id`.
- Для дочерних процессов нужен PATH из legacy `wake_agent.py`
  (`/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`).

## Пробник

```bash
python3 tools/probe/gateway_probe.py simple
python3 tools/probe/gateway_probe.py tool --record docs/protocol-samples/gateway-tool.jsonl
```

Сценарии: `handshake`, `simple`, `markdown`, `tool`, `interrupt`, `approval`.

## Сессии

- `session.list {"scope": "stored", "limit": N}` — недавние сессии. Ответ содержит `id`,
  `title`, `preview`, `source`, `last_activity_at`, `message_count`, `running`.
- `session.create {"request_id", "source", "cwd", "title", "model", "provider"}` — `title`
  можно задать сразу: приложение ставит туда первые слова запроса.
- `session.mutate` — официальное изменение сессии. Переименование:
  `{"session_id": "...", "operation": "rename", "payload": {"title": "..."}}`.
  Полезная нагрузка должна быть ровно `{"title": ...}`; операция требует capability
  `session:control` — клиент без него получает `permission_denied`.
- `session.resume`, `session.info`, `session.detach`, `session.interrupt` — управление сессией.
- Полный список с превью — только через read-only `state.db` (см. выше): gateway отдаёт
  лишь недавние сессии.
- Источники сессий (`source`): `acp, cli, gui, oneshot, tool, tui` (из `runtime.describe`),
  в `state.db` встречаются также внешние клиенты (telegram, slack).

## Hermes Desktop

- Deep link: `hermes://open/session/<session_id>` — открывает сессию в настольном приложении.
  Схему `hermes` регистрирует сам Desktop (`setAsDefaultProtocolClient`) при каждом запуске;
  в LaunchServices она видна как `claimed schemes: hermes:`. Проверено на живом приложении:
  доставка есть и при холодном старте (`[deeplink] delivered open/session/<id>`), и когда
  приложение уже запущено. Второй deep link — `hermes://open/<path>` (маршрут приложения).
- `hermes desktop --skip-build` — запустить уже собранное настольное приложение
  (`apps/desktop/release`), без npm-сборки. Полезно, когда Hermes.app не установлен в /Applications.
- `hermes sessions rename <session> <title>` — то же переименование, что `session.mutate`,
  но из CLI (меняет состояние, поэтому в автоматических проверках не вызывается).
- Продолжить сессию в терминале: `hermes --resume <session_id>`.
