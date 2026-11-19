#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GERANIA ears — голосовой фронтенд без Hermes.

Скрипт только слушает микрофон и распознаёт речь. Всё остальное (Hermes, озвучка,
звуки, оверлей, уведомления) делает приложение на Swift.

Режимы:
  * `--ipc`   — рабочий режим: stdout только NDJSON-события, stderr — логи,
                команды приложения приходят в stdin;
  * без флагов — интерактивный режим для ручной отладки (консольные логи);
  * `--levels` — подбор порога микрофона.

Поведение (VAD, фильтры, wake/stop) повторяет эталон `tools/legacy/wake_agent.py`.
"""
import json
import os
import queue
import re
import sys
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np
import sounddevice as sd
import mlx_whisper

# The helper module lives next to this script (also inside the app bundle).
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gera_wake  # noqa: E402

# ============================== НАСТРОЙКИ ==============================

# --- распознавание речи ---
MODEL_NAME = "mlx-community/whisper-large-v3-turbo"
# Маленькая модель — только для распознавания на ходу: она в 10–20 раз быстрее
# большой, поэтому Гера просыпается и отправляет команду заметно раньше.
# Финальный текст реплики всегда разбирает большая модель.
PARTIAL_MODEL_NAME = "mlx-community/whisper-base-mlx"
LANGUAGE = "ru"
# ВАЖНО: подсказка вроде "Гера." заставляла Whisper "слышать" Геру в шуме.
WAKE_PROMPT = None

# --- wake word ---
# Любое «гера» — призыв. Whisper регулярно пишет его с хвостом в том же слове
# («ГераОткрой», «Герам»), с «ё» («Гёра»), с буквой-латиницей («Gera») или с
# точкой («Гера.»), поэтому справа границы слова нет. Слева — либо граница
# слова, либо прилипший слог («НуГера»). «гер», «геры», «германия», «герой»
# не содержат «гера» и по-прежнему НЕ срабатывают.
WAKE_FORMS = ("гера", "гёра", "гэра", "гира")
# Буквы wake-слова с допуском помех: г + е/ё/э/и + р/п + а.
WAKE_CORE_CYR = r"г\s*[еёэиe]\s*[рp]\s*[аa]"
# Whisper часто слышит «Гера» как «Гира» или «Гиро» — принимаем и «о» на конце,
# но только если слово на этом заканчивается: «герой» — не призыв.
WAKE_CORE_CYR_O = r"г\s*[еёэиe]\s*[рp]\s*[оo](?![А-Яа-яЁёA-Za-z])"
# То же самое латиницей («Gera», «Gepa») — Whisper так тоже пишет.
WAKE_CORE_LAT = r"g\s*[e]\s*[rp]\s*[a]"
# Строгий шаблон: wake-слово начинается с границы слова.
WAKE_STRICT_RE = re.compile(
    r"(?<![А-Яа-яЁёA-Za-z])(?:эй[,\s]+)?(?:"
    + WAKE_CORE_CYR + "|" + WAKE_CORE_CYR_O + "|" + WAKE_CORE_LAT + ")",
    re.IGNORECASE,
)
# Мягкий шаблон: wake-слово приклеено к предыдущему слову («НуГера»).
# Латиница в мягкий шаблон не входит: «genera» не должен будить Геру.
WAKE_LOOSE_RE = re.compile(
    WAKE_CORE_CYR + "|" + WAKE_CORE_CYR_O, re.IGNORECASE
)
WAKE_MAX_PREFIX_WORDS = 2      # перед "Гера" допускается не больше 2 слов ("ну", "слушай")
AWAIT_COMMAND_SEC = 8.0
# After Porcupine hears «Гера», Whisper may read the phrase for this long.
KEYWORD_WINDOW_SEC = 4.0
MIN_COMMAND_CHARS = 3

# --- быстрый wake ---
# Реплика распознаётся на ходу: как только в тексте появилось wake-слово,
# приложение уже знает, что Гера слушает, и не ждёт конца фразы.
PARTIAL_INTERVAL = 0.25        # как часто пересчитывать текст реплики
PARTIAL_MIN_SEC = 0.6          # короче Whisper не разбирает
PARTIAL_MAX_SEC = 10.0         # длинные диктовки не пересчитываем
PARTIAL_NO_SPEECH_MAX = 0.6    # для коротких кусков порог строже финального
PARTIAL_LOGPROB_MIN = -1.2
# Пауза после реплики — команда сказана: отправляем её, не дожидаясь конца фразы.
COMMAND_PAUSE_SEC = 0.45

# --- стоп-слова ---
STOP_WORDS = ["хватит", "стоп", "стой", "отмена", "отбой", "отставить",
              "ничего", "нет", "забудь", "stop"]
STOP_PHRASES = ["не надо", "не нужно", "не слушай", "все хватит", "ладно хватит"]
# «Гиро» и «герания» — частые ослышки «Гера»: без них «Гиро, стоп» не считался стопом.
STOP_FILLERS = ({"эй", "ну", "так", "уже", "все", "ладно", "пожалуйста", "да"}
                | set(WAKE_FORMS) | {"гиро", "герания"})
STOP_WHEN_BUSY = True          # реагировать на стоп-слово без "Гера", пока агент работает/говорит

# --- фильтры ложных срабатываний ---
NO_SPEECH_MAX = 0.65           # выше — Whisper считает, что речи нет
LOGPROB_MIN = -0.9             # ниже — Whisper сам не уверен в тексте
USE_SPECTRAL_GATE = True
BAND_RATIO_MIN = 0.045         # доля энергии в голосовой полосе 300–3400 Гц
FLATNESS_MAX = 0.55            # у голоса спектр "гребенчатый", у шума/хлопка — плоский
MIN_TONAL_FRAMES = 2           # минимум "голосовых" кадров в фразе (~0.06 с)
MIN_TONAL_FRAC = 0.16

# --- аудио / VAD ---
SAMPLE_RATE = 16000
FRAME = 480                              # 30 мс
FRAME_SEC = FRAME / SAMPLE_RATE
PRE_ROLL_FRAMES = int(0.4 / FRAME_SEC)
START_FRAMES = 2                      # быстрее цепляем начало фразы
END_SILENCE_FRAMES = int(0.8 / FRAME_SEC)
MAX_UTT_FRAMES = int(15.0 / FRAME_SEC)
MIN_VOICED_FRAMES = 2
NOISE_MULT = 3.0                         # было 3.0
MIN_RMS = 0.003                          # было 0.006; подберите через --levels
SPEAKING_THRESHOLD_MULT = 3.0
# Мягкий mute: кадры нашего собственного звука пропускаем, но реплику не рвём.
# Дольше секунды не глушим: иначе фраза может растянуться бесконечно.
MAX_MUTE_KEEP_SEC = 1.0
MAX_SKIP_FRAMES = int(MAX_MUTE_KEEP_SEC / FRAME_SEC)

HALLUCINATIONS = (
    "субтитры", "dimatorzok", "продолжение следует", "спасибо за просмотр",
    "подписывайтесь", "редактор субтитров", "корректор",
)

DEBUG = os.environ.get("GERA_DEBUG") == "1"
IPC_MODE = "--ipc" in sys.argv
LEVELS_MODE = "--levels" in sys.argv

# Порог частоты событий уровня (15 Гц).
LEVEL_INTERVAL = 1.0 / 15.0


# ============================== IPC ==============================
class IPC:
    """Поток NDJSON-событий в stdout и команды приложения из stdin."""

    def __init__(self):
        self._lock = threading.Lock()
        self.levels_on = False
        self.busy = False
        self.speaking = False
        self.mute_until = 0.0
        self.mute_keep_phrase = True
        self.suspended = False
        self.should_exit = False
        self.listen_mode = gera_wake.LISTEN_ALWAYS
        self.owner_gate = True

    # --- исходящие события ---
    def emit(self, kind: str, **fields) -> None:
        if not IPC_MODE:
            return
        payload = {"type": kind}
        payload.update(fields)
        line = json.dumps(payload, ensure_ascii=False)
        with self._lock:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()

    def log(self, text: str) -> None:
        print(text, file=sys.stderr, flush=True)

    # --- состояние от приложения ---
    def deaf_until(self) -> float:
        return self.mute_until

    def mute(self, sec: float, keep_phrase: bool = True) -> None:
        """Не слушаем наш собственный звук.

        `keep_phrase=True` — кадры пропускаем, но текущую фразу не рвём: звук
        приложения может прозвучать посреди команды, и раньше он сбрасывал VAD
        вместе с уже сказанными словами.
        """
        self.mute_until = max(self.mute_until, time.time() + float(sec))
        self.mute_keep_phrase = bool(keep_phrase)

    def apply(self, command: dict) -> None:
        kind = command.get("type")
        if kind == "state":
            self.busy = bool(command.get("busy"))
            self.speaking = bool(command.get("speaking"))
        elif kind == "mute":
            self.mute(float(command.get("sec", 0.25)),
                      bool(command.get("keep_phrase", True)))
        elif kind == "arm":
            # Late arm can arrive while the microphone is already handed over
            # to the live session; it must not revive the expectation on resume.
            if not self.suspended:
                State.awaiting = True
                State.await_deadline = time.time() + AWAIT_COMMAND_SEC
        elif kind == "disarm":
            State.awaiting = False
        elif kind == "levels_on":
            self.levels_on = True
        elif kind == "levels_off":
            self.levels_on = False
        elif kind == "suspend":
            self.suspended = True
            State.awaiting = False
        elif kind == "resume":
            self.suspended = False
        elif kind == "config":
            apply_config(command)
        elif kind == "listen_mode":
            mode = command.get("mode")
            if mode in gera_wake.LISTEN_MODES:
                self.listen_mode = mode
        elif kind == "owner_gate":
            self.owner_gate = bool(command.get("enabled"))
        elif kind == "flush":
            State.flush = True
        elif kind == "shutdown":
            self.should_exit = True

    def start_reader(self) -> threading.Thread:
        def loop():
            for line in sys.stdin:
                text = line.strip()
                if not text:
                    continue
                try:
                    command = json.loads(text)
                except Exception:
                    self.log(f"⚠️  некорректная команда: {text!r}")
                    continue
                if isinstance(command, dict):
                    if DEBUG:
                        self.log(f"📥 команда: {command.get('type')}")
                    self.apply(command)
                    if self.should_exit:
                        return
            # stdin закрыт — приложение исчезло, выходим, чтобы не остаться сиротой.
            self.should_exit = True

        thread = threading.Thread(target=loop, daemon=True)
        thread.start()
        return thread


def apply_config(command: dict) -> None:
    """Переопределение порогов из настроек приложения."""
    global NO_SPEECH_MAX, LOGPROB_MIN, MIN_RMS, NOISE_MULT, AWAIT_COMMAND_SEC
    global BAND_RATIO_MIN, FLATNESS_MAX, MIN_TONAL_FRAMES, MIN_TONAL_FRAC
    global PARTIAL_INTERVAL, PARTIAL_MIN_SEC, PARTIAL_MAX_SEC, COMMAND_PAUSE_SEC
    values = command.get("values") or {}
    for key, value in values.items():
        try:
            number = float(value)
        except (TypeError, ValueError):
            continue
        if key == "no_speech_max":
            NO_SPEECH_MAX = number
        elif key == "logprob_min":
            LOGPROB_MIN = number
        elif key == "min_rms":
            MIN_RMS = number
        elif key == "noise_mult":
            NOISE_MULT = number
        elif key == "await_command_sec":
            AWAIT_COMMAND_SEC = number
        elif key == "band_ratio_min":
            BAND_RATIO_MIN = number
        elif key == "flatness_max":
            FLATNESS_MAX = number
        elif key == "min_tonal_frames":
            MIN_TONAL_FRAMES = int(number)
        elif key == "min_tonal_frac":
            MIN_TONAL_FRAC = number
        elif key == "partial_interval":
            PARTIAL_INTERVAL = number
        elif key == "partial_min_sec":
            PARTIAL_MIN_SEC = number
        elif key == "partial_max_sec":
            PARTIAL_MAX_SEC = number
        elif key == "command_pause_sec":
            COMMAND_PAUSE_SEC = number


# ============================== СОСТОЯНИЕ ==============================
class State:
    awaiting = False
    await_deadline = 0.0
    keyword_at = 0.0     # when Porcupine heard «Гера»
    flush = False        # hold-to-talk released: send the command now


# ============================ "ЭТО ПОХОЖЕ НА ГОЛОС?" (спектр) ======================
def speech_check(audio: np.ndarray):
    """Отсекает хлопки, стук, падение предметов, шипение. Возвращает (ok, описание)."""
    n = len(audio) // FRAME
    if n < MIN_VOICED_FRAMES:
        return False, "слишком коротко"
    fr = audio[: n * FRAME].reshape(n, FRAME)
    rms = np.sqrt((fr * fr).mean(axis=1))
    strong = rms > max(float(rms.max()) * 0.25, MIN_RMS)
    n_strong = int(strong.sum())
    if n_strong < MIN_TONAL_FRAMES:
        return False, f"импульс: громких кадров {n_strong}"

    spec = np.abs(np.fft.rfft(fr[strong] * np.hanning(FRAME), axis=1)) ** 2
    freqs = np.fft.rfftfreq(FRAME, 1.0 / SAMPLE_RATE)
    band = (freqs >= 300) & (freqs <= 3400)
    total = spec[:, freqs >= 60].sum(axis=1) + 1e-12
    ratio = spec[:, band].sum(axis=1) / total
    pb = spec[:, band] + 1e-12
    flat = np.exp(np.log(pb).mean(axis=1)) / pb.mean(axis=1)

    tonal = (ratio > BAND_RATIO_MIN) & (flat < FLATNESS_MAX)
    n_tonal = int(tonal.sum())
    info = (f"голосовых кадров {n_tonal}/{n_strong}, "
            f"полоса {ratio.mean():.2f}, плоскость {flat.mean():.2f}")
    ok = n_tonal >= MIN_TONAL_FRAMES and (n_tonal / n_strong) >= MIN_TONAL_FRAC
    return ok, info


# ================================ VAD ================================
class VAD:
    def __init__(self):
        self.noise = 0.003
        self.pre = deque(maxlen=PRE_ROLL_FRAMES)
        self.reset()

    def reset(self):
        """Полный сброс (например, после нашего собственного звука)."""
        self.pre.clear()
        self._reset()

    def _reset(self):
        self.active = False
        self.buf = []
        self.speech_run = 0
        self.silence_run = 0
        self.voiced = 0
        self.skipped = 0
        self.started_at = 0.0

    def snapshot(self) -> np.ndarray:
        """Текущая реплика целиком — для распознавания на ходу."""
        if not self.buf:
            return np.zeros(0, dtype=np.float32)
        return np.concatenate(self.buf)

    def duration(self) -> float:
        """Сколько секунд длится текущая реплика."""
        return len(self.buf) * FRAME_SEC

    def trailing_silence(self) -> float:
        """Сколько секунд тишины в конце текущей реплики."""
        return self.silence_run * FRAME_SEC

    def voiced_samples(self) -> int:
        """Сколько samples речи в текущей реплике (без тишины)."""
        return self.voiced * FRAME

    def skip(self, frame: np.ndarray) -> None:
        """Пропускает кадр нашего собственного звука, не разрывая фразу.

        Кадр заменяется тишиной, чтобы не потерять длину реплики, а счётчик
        тишины не растёт: иначе наш короткий звук завершил бы фразу.  Если
        mute завис, реплика всё равно сбрасывается по MAX_SKIP_FRAMES.
        """
        if not self.active:
            return
        self.skipped += 1
        if self.skipped > MAX_SKIP_FRAMES:
            self.reset()
            return
        self.buf.append(np.zeros_like(frame))

    def feed(self, frame: np.ndarray, mult: float = 1.0):
        rms = float(np.sqrt(np.mean(frame * frame)))
        thr = max(MIN_RMS, self.noise * NOISE_MULT) * mult
        loud = rms > thr
        if DEBUG and int(time.time() * 4) % 4 == 0:
            # Только stderr: stdout — NDJSON, любая строка ломает событие.
            print(f"\rrms={rms:.4f} thr={thr:.4f} active={self.active}   ",
                  file=sys.stderr, end="")

        if not self.active:
            if not loud:
                self.noise = 0.95 * self.noise + 0.05 * rms
            self.pre.append(frame)
            self.speech_run = self.speech_run + 1 if loud else 0
            if self.speech_run >= START_FRAMES:
                self.active = True
                self.buf = list(self.pre)
                self.voiced = self.speech_run
                self.silence_run = 0
                self.started_at = time.time()
            return None

        self.buf.append(frame)
        if loud:
            self.silence_run = 0
            self.voiced += 1
        else:
            self.silence_run += 1
        if self.silence_run >= END_SILENCE_FRAMES or len(self.buf) >= MAX_UTT_FRAMES:
            audio = np.concatenate(self.buf)
            voiced = self.voiced
            duration = time.time() - self.started_at
            self.reset()
            if voiced < MIN_VOICED_FRAMES:
                return ("filtered", "короткий звук", duration)
            if USE_SPECTRAL_GATE:
                ok, info = speech_check(audio)
                if not ok:
                    return ("filtered", f"не похоже на речь ({info})", duration)
            return ("utterance", audio, duration)
        return None


# ============================ РАСПОЗНАВАНИЕ ============================
def transcribe(audio: np.ndarray, prompt=None, model: str = MODEL_NAME):
    """Возвращает (текст, no_speech_prob, avg_logprob)."""
    kw = dict(
        path_or_hf_repo=model,
        language=LANGUAGE,
        verbose=False,
        temperature=0.0,
        condition_on_previous_text=False,
        no_speech_threshold=0.6,
    )
    if prompt:
        kw["initial_prompt"] = prompt
    try:
        res = mlx_whisper.transcribe(audio.astype(np.float32), **kw)
    except Exception as e:
        print(f"Ошибка распознавания: {e}", file=sys.stderr)
        return "", 1.0, -9.0
    segs = res.get("segments") or []
    nsp = max((s.get("no_speech_prob", 0.0) for s in segs), default=0.0)
    lp = min((s.get("avg_logprob", 0.0) for s in segs), default=0.0)
    return (res.get("text") or "").strip(), float(nsp), float(lp)


def probe_model(model: str) -> None:
    """Грузит модель и бросает исключение, если она недоступна.

    `transcribe()` намеренно глотает ошибки и возвращает пустой результат,
    поэтому доступность модели проверяется отдельным вызовом: иначе фолбэк
    на большую модель никогда не срабатывал.
    """
    mlx_whisper.transcribe(
        np.zeros(SAMPLE_RATE, dtype=np.float32),
        path_or_hf_repo=model,
        language=LANGUAGE,
        verbose=False,
    )


def norm(s: str) -> str:
    s = s.lower().replace("ё", "е")
    s = re.sub(r"[^\w\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def clean_command(cmd: str) -> str:
    return cmd.strip(" ,.!?:;-—…\n\t")


def is_real_command(cmd: str) -> bool:
    low = cmd.lower()
    return len(cmd) >= MIN_COMMAND_CHARS and not any(h in low for h in HALLUCINATIONS)


def find_wake(text: str):
    """Wake word в начале фразы: до двух слов перед ним, с допуском помех.

    Берётся самое раннее совпадение из строгого и мягкого шаблонов, поэтому
    «Гера.», «Гера!», «ГераОткрой», «Гёра» и «НуГера» подходят, а «герой»,
    «геры» и «германия» — нет.
    """
    matches = [m for m in (WAKE_STRICT_RE.search(text), WAKE_LOOSE_RE.search(text)) if m]
    if not matches:
        return None
    best = min(matches, key=lambda m: m.start())
    if len(norm(text[: best.start()]).split()) > WAKE_MAX_PREFIX_WORDS:
        return None
    return best


def command_after_wake(text: str) -> str:
    """Команда, сказанная после wake-слова."""
    match = find_wake(text)
    return clean_command(text[match.end():]) if match else ""


class WhisperWorker:
    """Распознаёт фрагменты реплики в отдельном потоке.

    Whisperlarge-v3-turbo думает дольше, чем кадр микрофона, поэтому блокировать
    цикл VAD нельзя: иначе аудио копится в очереди и реплика заканчивается с
    опозданием. Пока поток занят, новые куски просто пропускаются.
    """

    def __init__(self, model: str = PARTIAL_MODEL_NAME, fallback: str = MODEL_NAME):
        self._lock = threading.Lock()
        self._audio = None
        self._token = 0
        self._result = None
        self._busy = False
        self.model = model
        self.fallback = fallback

    def warmup(self) -> None:
        """Готовит модель частичного распознавания заранее (в фоне)."""
        def load():
            try:
                probe_model(self.model)
            except Exception as error:  # noqa: BLE001 — нет сети или нет модели
                print(f"Малая модель недоступна ({error}), работаем большой",
                      file=sys.stderr, flush=True)
                self.model = self.fallback

        threading.Thread(target=load, daemon=True).start()

    def submit(self, audio: np.ndarray, token: int = 0) -> bool:
        """Отдаёт кусок реплики на распознавание. False — поток уже занят."""
        with self._lock:
            if self._busy:
                return False
            self._busy = True
            self._audio = audio
            self._token = token
        threading.Thread(target=self._run, daemon=True).start()
        return True

    def _run(self) -> None:
        with self._lock:
            audio = self._audio
            token = self._token
            self._audio = None
        text, nsp, lp = transcribe(audio, None, self.model)
        if nsp >= 1.0 and lp <= -9.0:
            # Sentinel `transcribe()`: модель не загрузилась. Дальше — большая.
            print("Малая модель не отвечает, переключаюсь на большую",
                  file=sys.stderr, flush=True)
            self.model = self.fallback
            text, nsp, lp = transcribe(audio, None, self.model)
        with self._lock:
            self._result = (text, nsp, lp, len(audio), token)
            self._busy = False

    def take(self):
        """Забирает готовый результат, если он есть."""
        with self._lock:
            result = self._result
            self._result = None
            return result


class WakeTracker:
    """Состояние текущей реплики: нашли ли wake-слово и что уже отправили."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.woke = False        # wake-слово нашли в тексте
        self.wake_sent = False   # событие wake уже отправлено
        self.stop_sent = False   # стоп-слово уже отправлено
        self.command = ""        # текущая гипотеза команды
        self.dispatched = ""     # команда, которую уже отправили
        self.covered = 0         # сколько samples аудио покрывает гипотеза

    def observe(self, text: str) -> bool:
        """Обновляет состояние по новой гипотезе. True — wake-слово найдено."""
        match = find_wake(text)
        if match:
            self.woke = True
            command = clean_command(text[match.end():])
            # Гипотеза только с «Гера» не должна стирать уже услышанную
            # команду: аудио реплики только растёт.
            if command:
                self.command = command
            return True
        if self.woke:
            # Малая модель часто теряет «Гера» в следующих гипотезах, хотя
            # реплика началась с призыва. Раньше команда оставалась на первой
            # короткой гипотезе, и в live уходил только огрызок фразы.
            command = clean_command(text)
            if command:
                self.command = command
        return False

    @property
    def has_new_command(self) -> bool:
        """Команда отличается от той, что уже отправлена."""
        return bool(self.command) and norm(self.command) != norm(self.dispatched)


_STOP_SINGLE = {w for w in STOP_WORDS if " " not in w}
_STOP_ALL = set(STOP_WORDS) | set(STOP_PHRASES)


def is_stop(text: str) -> bool:
    words = [w for w in norm(text).split() if w not in STOP_FILLERS]
    if not words:
        return False
    if " ".join(words) in _STOP_ALL:
        return True
    return all(w in _STOP_SINGLE for w in words)


# ============================== MAIN ==============================
def levels_mode():
    print("Говорите, потом стучите по столу/хлопайте. Ctrl+C — выход.")
    print("MIN_RMS должен быть выше шума комнаты и стука, но ниже вашей речи.")

    def cb(indata, frames, t, status):
        rms = float(np.sqrt(np.mean(indata ** 2)))
        print(f"\rRMS {rms:.4f} " + "█" * min(60, int(rms * 600)) + " " * 20, end="")

    with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, blocksize=FRAME, callback=cb):
        while True:
            time.sleep(1)


def enroll_mode(out_path: str) -> int:
    """Records the owner voice profile: `--enroll-voice PATH --ipc`."""
    ipc = IPC()
    if IPC_MODE:
        ipc.start_reader()
    frames: "queue.Queue[np.ndarray]" = queue.Queue()

    def callback(indata, count, t, status):  # noqa: ARG001
        frames.put(indata[:, 0].copy())

    def read_frame():
        if ipc.should_exit:
            return None
        try:
            return frames.get(timeout=5.0)
        except queue.Empty:
            return None

    try:
        with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                            blocksize=FRAME, callback=callback):
            ipc.emit("enroll_started")
            ok = gera_wake.enroll_owner(out_path, read_frame, ipc.emit)
    except Exception as error:  # noqa: BLE001
        ipc.emit("error", message=f"микрофон: {error}")
        ok = False
    ipc.emit("bye")
    return 0 if ok else 1


def main():
    if LEVELS_MODE:
        return levels_mode()
    if "--enroll-voice" in sys.argv:
        index = sys.argv.index("--enroll-voice")
        if index + 1 >= len(sys.argv):
            print("--enroll-voice требует путь к файлу профиля", file=sys.stderr, flush=True)
            return 2
        return enroll_mode(sys.argv[index + 1])

    ipc = IPC()
    if IPC_MODE:
        ipc.start_reader()

    print("=== GERANIA ears ===", file=sys.stderr, flush=True)
    print(f"🎙️  Загрузка {MODEL_NAME} ...", file=sys.stderr, flush=True)
    transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32))
    detector, wake_detail = gera_wake.KeywordDetector.create()
    verifier, owner_detail = gera_wake.OwnerVerifier.create()
    print(f"🔔 wake: {wake_detail}; 🧑 голос владельца: {owner_detail}", file=sys.stderr, flush=True)
    ipc.emit("ready", model=MODEL_NAME)
    ipc.emit("engines", keyword=detector is not None, keyword_detail=wake_detail,
             owner=verifier is not None, owner_detail=owner_detail)

    def keyword_recent() -> bool:
        """Porcupine heard «Гера» a moment ago: Whisper may read this phrase."""
        return time.time() - State.keyword_at < KEYWORD_WINDOW_SEC

    def whisper_needed() -> bool:
        """With Porcupine, Whisper runs only after the wake word or for stop words."""
        return (detector is None or State.awaiting or keyword_recent()
                or ipc.busy or ipc.speaking)

    def owner_gate_active() -> bool:
        return ipc.owner_gate and verifier is not None

    def owner_ok() -> bool:
        """The phrase was said by the owner (always true without the gate)."""
        if not owner_gate_active():
            return True
        return max(utt_owner_best, verifier.score()) >= verifier.gate.threshold

    def on_keyword() -> None:
        """Porcupine heard «Гера»."""
        if not gera_wake.wake_allowed(ipc.listen_mode, ipc.speaking, owner_gate_active()):
            return
        if owner_gate_active() and not verifier.is_owner():
            ipc.emit("wake_rejected", reason="чужой голос", score=round(verifier.score(), 2))
            print(f"🙅 «Гера» чужим голосом: {verifier.score():.2f}", file=sys.stderr, flush=True)
            return
        now = time.time()
        if now - State.keyword_at < 1.0:
            return
        State.keyword_at = now
        State.awaiting = True
        State.await_deadline = now + AWAIT_COMMAND_SEC
        tracker.wake_sent = True
        ipc.emit("wake", inline_command=None, via="keyword")
        print("🔔 проснулись: Porcupine", file=sys.stderr, flush=True)
    print("✅ Готово.", file=sys.stderr, flush=True)

    def dispatch(cmd: str, via: str):
        cmd = clean_command(cmd)
        if not is_real_command(cmd):
            ipc.emit("filtered", reason="не расслышала команду")
            return
        ipc.emit("command", text=cmd, via=via)

    def send_once(cmd: str, via: str):
        """Отправляет команду, если она ещё не уходила (частичный ответ не дублируем)."""
        if tracker.stop_sent:
            return              # быстрый стоп уже отправлен
        if not owner_ok():
            ipc.emit("speaker_rejected", score=round(verifier.score(), 2))
            print("🙅 команда чужим голосом — пропускаю", file=sys.stderr, flush=True)
            return
        cmd = clean_command(cmd)
        if not is_real_command(cmd):
            return
        if norm(cmd) == norm(tracker.dispatched):
            return
        tracker.dispatched = cmd
        if is_stop(cmd):
            # «Гера, стоп» — это остановка, а не запрос к агенту. Раньше стоп-слово
            # уходило как обычная команда и Hermes начинал её выполнять.
            tracker.stop_sent = True
            ipc.emit("stop", scope="explicit" if tracker.woke else "busy")
            return
        dispatch(cmd, via)

    def best_command(cmd: str) -> str:
        """Не отдаёт короткий фрагмент вместо уже накопленной полной команды.

        Whisper иногда обрезает начало или конец уже накопленной гипотезы.
        Если новый текст — только её кусок, остаётся более полный вариант.
        """
        previous = tracker.command
        if not previous:
            return cmd
        new, old = norm(cmd), norm(previous)
        if len(new) < len(old) and (old.startswith(new) or old.endswith(new)):
            return previous
        return cmd

    def send_final(cmd: str) -> None:
        """Финальный текст без «Гера» после призыва: не терять хвост фразы."""
        if not is_real_command(cmd):
            return
        send_once(best_command(cmd), "final")

    def cancel_input():
        State.awaiting = False
        ipc.emit("stop", scope="input")

    def handle(utt: np.ndarray):
        """Финальный разбор реплики: она закончилась."""
        waiting = State.awaiting
        if tracker.stop_sent:
            return              # быстрый стоп уже сработал на частичном тексте
        text, nsp, lp = transcribe(utt, None if waiting else WAKE_PROMPT)
        if not text:
            return
        if nsp > NO_SPEECH_MAX or lp < LOGPROB_MIN:
            ipc.emit("filtered", reason="Whisper не уверен")
            print(f"🚫 отсеяно: Whisper не уверен (no_speech={nsp:.2f}, logprob={lp:.2f}): {text!r}",
                  file=sys.stderr, flush=True)
            return
        ipc.emit("transcript", text=text, no_speech=round(nsp, 3), logprob=round(lp, 3))
        print(f"👂 {text}", file=sys.stderr, flush=True)

        m = find_wake(text)
        stop = is_stop(text)

        # --- Гера слушает команду ---
        if waiting:
            State.awaiting = False
            if stop:
                cancel_input()
                return
            cmd = clean_command(text[m.end():] if m else text)
            if m and not is_real_command(cmd):   # просто повторили "Гера" — ждём дальше
                State.awaiting = True
                State.await_deadline = time.time() + AWAIT_COMMAND_SEC
                return
            send_once(cmd, "followup")
            return

        # --- стоп-слова вне режима ввода ---
        # `tracker.woke` — призыв был в этой же реплике, просто финальная
        # расшифровка потеряла «Гера»: «Гера, стоп» остаётся явным стопом.
        if stop and owner_ok() and (m or tracker.woke or (STOP_WHEN_BUSY and (ipc.busy or ipc.speaking))):
            scope = "explicit" if (m or tracker.woke) else "busy"
            ipc.emit("stop", scope=scope)
            return

        # Пока Гера говорит, микрофон слышит её саму: не будимся на своей озвучке.
        if ipc.speaking:
            return

        # С Porcupine wake-слово ловит он, а не Whisper по тексту.
        if detector is not None and not keyword_recent():
            return

        if not m:
            # Большая модель иногда выбрасывает «Гера» из финального текста,
            # хотя малая уже поймала призыв на ходу. Весь текст — команда;
            # именно этот полный вариант уходит в live-сессию.
            if tracker.woke:
                send_final(clean_command(text))
            return

        # --- wake word ---
        cmd = best_command(clean_command(text[m.end():]))
        inline = cmd if is_real_command(cmd) else None
        if not tracker.wake_sent:
            tracker.wake_sent = True
            ipc.emit("wake", inline_command=inline)
        if inline:
            send_once(inline, "inline")
        else:
            # Ждём команду следующей фразой (как в эталоне).
            State.awaiting = True
            State.await_deadline = time.time() + AWAIT_COMMAND_SEC

    def apply_text(text: str, covered: int = 0) -> None:
        """Новая гипотеза текста: проснулись? что за команда?"""
        if covered:
            tracker.covered = covered
        if not tracker.woke and not tracker.stop_sent and (ipc.busy or ipc.speaking):
            # Быстрый стоп: короткое «стоп» во время работы не ждём конца фразы.
            if is_stop(text) and owner_ok():
                tracker.stop_sent = True
                ipc.emit("stop", scope="busy")
                print(f"🛑 быстрый стоп: {text!r}", file=sys.stderr, flush=True)
                return
        if detector is not None and not (State.awaiting or keyword_recent()):
            return      # Porcupine owns the wake word: Whisper only checks stop words here
        if tracker.observe(text):
            if not tracker.wake_sent and not keyword_recent():
                tracker.wake_sent = True
                inline = tracker.command if is_real_command(tracker.command) else None
                ipc.emit("wake", inline_command=inline)
                if inline:
                    send_once(inline, "inline")
                print(f"🔔 проснулись: {text!r}", file=sys.stderr, flush=True)
        if tracker.woke and tracker.command and not tracker.stop_sent:
            ipc.emit("partial", text=tracker.command)

    def process_partial() -> None:
        """Отдаёт реплику на фоновое распознавание: цикл VAD не должен ждать Whisper."""
        nonlocal last_partial_at
        if not whisper_needed():
            return
        duration = vad.duration()
        if duration < PARTIAL_MIN_SEC:
            return
        now = time.time()
        if duration > PARTIAL_MAX_SEC or now - last_partial_at < PARTIAL_INTERVAL:
            return
        audio = vad.snapshot()
        if audio.size == 0:
            return
        last_partial_at = now
        worker.submit(audio, utterance_id)

    def drain_partials() -> None:
        """Забирает готовые частичные распознавания и применяет их."""
        while True:
            result = worker.take()
            if result is None:
                return
            text, nsp, lp, covered, token = result
            if not vad.active:
                return          # результат устарел: реплика уже закончилась
            if token != utterance_id:
                continue        # результат посчитан для предыдущей реплики
            if DEBUG:
                print(f"🅿 {covered / SAMPLE_RATE:.2f}с nsp={nsp:.2f} lp={lp:.2f} {text!r}",
                      file=sys.stderr, flush=True)
            if not text or nsp > PARTIAL_NO_SPEECH_MAX or lp < PARTIAL_LOGPROB_MIN:
                continue
            apply_text(text, covered)

    def send_paused_command() -> None:
        """Пользователь замолчал — команду отправляем по свежему тексту реплики.

        Если последняя гипотеза покрывает всю реплику, берём её: она уже готова,
        и команда уходит мгновенно. Иначе разбираем реплику заново большой моделью.
        """
        if not whisper_needed():
            return
        audio = vad.snapshot()
        if audio.size == 0:
            return
        if DEBUG:
            print(f"⏸ пауза: covered={tracker.covered} voiced={vad.voiced_samples()} "
                  f"size={audio.size} cmd={tracker.command!r}", file=sys.stderr, flush=True)
        # Свежесть считаем по речи: тишина в конце реплики текст не меняет.
        fresh = tracker.covered >= vad.voiced_samples() - int(0.3 * SAMPLE_RATE)
        if fresh and tracker.command:
            if tracker.woke:
                send_once(tracker.command, "partial")
            elif State.awaiting:
                State.awaiting = False
                send_once(tracker.command, "followup")
            return
        text, nsp, lp = transcribe(audio, None)
        if not text or nsp > NO_SPEECH_MAX or lp < LOGPROB_MIN:
            return
        apply_text(text, audio.size)
        if tracker.woke:
            command = best_command(command_after_wake(text) or tracker.command)
            send_once(command, "partial")
        elif State.awaiting:
            # Команда ушла (push-to-talk) — ожидание снимаем, иначе придёт таймаут.
            State.awaiting = False
            send_once(clean_command(command_after_wake(text) or text), "followup")

    q: "queue.Queue[np.ndarray]" = queue.Queue()
    tracker = WakeTracker()
    worker = WhisperWorker()
    worker.warmup()
    last_partial_at = 0.0
    pause_handled = False
    utterance_id = 0

    def callback(indata, frames, t, status):
        if status:
            print(status, file=sys.stderr, flush=True)
        q.put(indata[:, 0].copy())

    def open_stream():
        stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                                blocksize=FRAME, callback=callback)
        stream.start()
        return stream

    def close_stream(stream):
        try:
            stream.stop()
            stream.close()
        except Exception as error:  # noqa: BLE001 — устройство могло исчезнуть
            print(f"Не удалось закрыть микрофон: {error}", file=sys.stderr, flush=True)

    def clear_queue():
        while True:
            try:
                q.get_nowait()
            except queue.Empty:
                return

    vad = VAD()
    last_level_at = 0.0
    stream = None
    utt_owner_best = 0.0
    speakers = gera_wake.SpeakerTracker()
    try:
        stream = open_stream()
        while True:
            if ipc.should_exit or os.getppid() == 1:
                break

            # Приложение забирает микрофон на время live-сессии Gemini.
            if ipc.suspended:
                # With the owner gate the microphone stays open (macOS lets two
                # clients record): the ears tell the live dialog who is talking.
                monitor = owner_gate_active()
                if stream is not None and not monitor:
                    close_stream(stream)
                    stream = None
                ipc.emit("suspended", monitoring=monitor)
                State.awaiting = False
                vad.reset()
                tracker.reset()
                clear_queue()
                pause_handled = False
                speakers.reset()
                while not ipc.should_exit and ipc.suspended:
                    if os.getppid() == 1:
                        break
                    if not monitor:
                        time.sleep(0.05)
                        continue
                    try:
                        frame = q.get(timeout=0.1)
                    except queue.Empty:
                        continue
                    verifier.feed(frame)
                    rms = float(np.sqrt(np.mean(frame * frame)))
                    voiced = rms > max(MIN_RMS, vad.noise * NOISE_MULT)
                    change = speakers.update(voiced, verifier.is_owner(), time.time())
                    if change:
                        ipc.emit("speaker", who=change, score=round(verifier.score(), 2))
                if stream is not None:
                    close_stream(stream)
                    stream = None
                if ipc.should_exit or os.getppid() == 1:
                    break
                clear_queue()
                vad.reset()
                tracker.reset()
                State.awaiting = False
                pause_handled = False
                stream = open_stream()
                ipc.emit("resumed")
                continue

            try:
                frame = q.get(timeout=0.3)
            except queue.Empty:
                frame = None
            now = time.time()

            if State.awaiting and not vad.active and now > State.await_deadline:
                State.awaiting = False
                ipc.emit("await_timeout")
                continue

            if frame is None:
                continue
            if now < ipc.deaf_until():
                if ipc.mute_keep_phrase and vad.active:
                    vad.skip(frame)   # наш звук посреди фразы: не рвём её
                else:
                    vad.reset()       # не склеиваем фразу через наш собственный сигнал
                continue

            if not gera_wake.frame_is_heard(ipc.listen_mode, ipc.busy, ipc.speaking, State.awaiting):
                # Push-to-talk or «не слушать во время ответа»: микрофон глух.
                if vad.active:
                    vad.reset()
                    tracker.reset()
                if detector is not None:
                    detector.reset()
                continue
            if verifier is not None:
                verifier.feed(frame)
            if detector is not None and detector.feed(frame):
                on_keyword()

            mult = SPEAKING_THRESHOLD_MULT if ipc.speaking else 1.0
            was_active = vad.active
            utt = vad.feed(frame, mult)
            if not was_active and vad.active:
                utterance_id += 1
                tracker.reset()
                if keyword_recent():
                    tracker.wake_sent = True
                utt_owner_best = 0.0
                ipc.emit("utterance_start")
            if vad.active and verifier is not None:
                utt_owner_best = max(utt_owner_best, verifier.score())
            if State.flush:
                # Hold-to-talk released: the phrase is over, send it now.
                State.flush = False
                if vad.active and not pause_handled:
                    pause_handled = True
                    send_paused_command()
            if utt is None:
                if vad.active:
                    drain_partials()
                    process_partial()
                    if vad.trailing_silence() >= COMMAND_PAUSE_SEC:
                        if not pause_handled:
                            pause_handled = True
                            send_paused_command()
                    else:
                        pause_handled = False   # пользователь заговорил снова
                else:
                    pause_handled = False
                if ipc.levels_on or State.awaiting:
                    rms = float(np.sqrt(np.mean(frame * frame)))
                    thr = max(MIN_RMS, vad.noise * NOISE_MULT) * mult
                    if now - last_level_at >= LEVEL_INTERVAL:
                        last_level_at = now
                        ipc.emit("level", rms=round(rms, 5), thr=round(thr, 5), active=vad.active)
                continue
            kind, payload, duration = utt
            if kind == "filtered":
                ipc.emit("filtered", reason=payload)
                print(f"🚫 отсеяно: {payload}", file=sys.stderr, flush=True)
                ipc.emit("utterance_end", dur=round(duration, 3))
                continue
            if whisper_needed():
                handle(payload)
            ipc.emit("utterance_end", dur=round(duration, 3))
    except KeyboardInterrupt:
        print("\n👋 Завершаю.", file=sys.stderr, flush=True)
    except Exception as error:  # noqa: BLE001 — процесс не должен падать молча
        ipc.emit("error", message=f"микрофон: {error}")
        print(f"Ошибка микрофона: {error}", file=sys.stderr, flush=True)
    finally:
        if stream is not None:
            close_stream(stream)
        ipc.emit("bye")


if __name__ == "__main__":
    sys.exit(main() or 0)
