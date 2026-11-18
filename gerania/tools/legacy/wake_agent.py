#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GERANIA v3.1 — голосовой фронтенд для Hermes Agent (macOS, Apple Silicon).

Что делает:
  • слушает микрофон постоянно (и пока агент работает, и пока говорит);
  • "Гера, <команда>" одной фразой ИЛИ "Гера" -> пауза -> "<команда>";
  • новое "Гера" во время работы/озвучки — barge-in: задача и озвучка прерываются;
  • стоп-слова ("хватит", "стоп", "отмена"...) отменяют ввод, пока Гера слушает,
    и останавливают работу/озвучку, пока Гера занята;
  • защита от ложных срабатываний (стук, хлопок, падение предметов):
      1) VAD с порогом выше шума комнаты,
      2) спектральный фильтр "это похоже на голос?",
      3) отсев по уверенности Whisper (no_speech_prob / avg_logprob),
      4) wake word только в начале фразы, без initial_prompt (он заставлял
         Whisper "выдумывать" Геру из шума);
  • звуки: проснулась / отправила / ответ / ошибка; озвучка через `say`;
  • хук для плашки: overlay(kind, text) (+ опциональный HTTP-адрес).

Запуск:     python wake_agent.py
Тест mic:   python wake_agent.py --levels
Отладка:    GERA_DEBUG=1 python wake_agent.py
"""
import json
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.request
from collections import deque
from pathlib import Path

import numpy as np
import sounddevice as sd
import mlx_whisper

# ============================== НАСТРОЙКИ ==============================

# --- распознавание речи ---
MODEL_NAME = "mlx-community/whisper-large-v3-turbo"
LANGUAGE = "ru"
# ВАЖНО: подсказка вроде "Гера." заставляла Whisper "слышать" Геру в шуме.
# Оставьте None; включайте только если Геру стали часто не узнавать.
WAKE_PROMPT = None

# --- Hermes ---
HERMES_BIN = shutil.which("hermes") or str(Path.home() / ".local" / "bin" / "hermes")
HERMES_PROVIDER = "gemini"
HERMES_MODEL = "gemini-2.5-flash-lite"   # точное имя смотрите в `hermes model`
CONTINUE_LAST_SESSION = True
AGENT_TIMEOUT_SEC = 600
WORKDIR = Path.home() / "AgentWork"
PROMPT_PREFIX = (
    "[Голосовой режим] Отвечай по-русски, коротко (1–3 предложения), без markdown и "
    "списков: ответ будет озвучен. Ничего не удаляй и не перезаписывай; новые файлы "
    f"и папки создавай только в {WORKDIR}. Запрос: "
)

# --- wake word ---
# Только звательная форма/имя. "гер", "геры", "германия", "герой" НЕ срабатывают.
WAKE_FORMS = ["гера", "гэра", "гира"]
WAKE_RE = re.compile(
    r"(?<!\w)(?:эй[,\s]+)?(?:" + "|".join(WAKE_FORMS) + r")(?!\w)", re.IGNORECASE
)
WAKE_MAX_PREFIX_WORDS = 2      # перед "Гера" допускается не больше 2 слов ("ну", "слушай")
AWAIT_COMMAND_SEC = 8.0
MIN_COMMAND_CHARS = 3

# --- стоп-слова ---
# Работают: (а) пока Гера ждёт команду — отменяют ввод; (б) пока агент работает или
# говорит — останавливают его; (в) всегда, если сказать "Гера, стоп".
# Фраза считается стоп-командой, только если она ЦЕЛИКОМ состоит из стоп-слов
# (с необязательными "ну/так/уже/пожалуйста/Гера"), чтобы "отмена будильника"
# не принималась за стоп.
STOP_WORDS = ["хватит", "стоп", "стой", "отмена", "отбой", "отставить",
              "ничего", "нет", "забудь", "stop"]
STOP_PHRASES = ["не надо", "не нужно", "не слушай", "все хватит", "ладно хватит"]
STOP_FILLERS = {"эй", "ну", "так", "уже", "все", "ладно", "пожалуйста", "да",
                "гера", "гэра", "гира"}
STOP_WHEN_BUSY = True          # реагировать на стоп-слово без "Гера", пока агент работает/говорит

# --- фильтры ложных срабатываний ---
NO_SPEECH_MAX = 0.5            # выше — Whisper считает, что речи нет
LOGPROB_MIN = -1.2             # ниже — Whisper сам не уверен в тексте
USE_SPECTRAL_GATE = True
BAND_RATIO_MIN = 0.1          # доля энергии в голосовой полосе 300–3400 Гц
FLATNESS_MAX = 0.35            # у голоса спектр "гребенчатый", у шума/хлопка — плоский
MIN_TONAL_FRAMES = 4           # минимум "голосовых" кадров в фразе (~0.15 с)
MIN_TONAL_FRAC = 0.30

# --- звуки (/System/Library/Sounds) ---
SOUNDS = {
    "wake": "Funk",
    "sent": "Tink",
    "answer": "Glass",
    "error": "Basso",
    "cancel": "Pop",
}

# --- озвучка ---
SPEAK_ANSWER = True
SAY_VOICE = "Milena"
SAY_RATE = 190
MAX_SPOKEN_CHARS = 500
SPEAKING_THRESHOLD_MULT = 3.0

# --- оверлей / уведомления ---
USE_NOTIFICATIONS = True
OVERLAY_URL = None             # например "http://127.0.0.1:8765/event"

# --- аудио / VAD ---
SAMPLE_RATE = 16000
FRAME = 480                              # 30 мс
FRAME_SEC = FRAME / SAMPLE_RATE
PRE_ROLL_FRAMES = int(0.4 / FRAME_SEC)
START_FRAMES = 3                      # было 3: меньше реакций на щелчки
END_SILENCE_FRAMES = int(0.8 / FRAME_SEC)
MAX_UTT_FRAMES = int(15.0 / FRAME_SEC)
MIN_VOICED_FRAMES = 3
NOISE_MULT = 4.0                         # было 3.0
MIN_RMS = 0.005                          # было 0.006; подберите через --levels
DEBUG = os.environ.get("GERA_DEBUG") == "1"

HALLUCINATIONS = (
    "субтитры", "dimatorzok", "продолжение следует", "спасибо за просмотр",
    "подписывайтесь", "редактор субтитров", "корректор",
)

ENV = os.environ.copy()
ENV["PATH"] = os.pathsep.join(
    ["/opt/homebrew/bin", "/usr/local/bin", str(Path.home() / ".local" / "bin"), ENV.get("PATH", "")]
)


# ============================== СОСТОЯНИЕ / ЗВУКИ ==============================
class State:
    awaiting = False
    await_deadline = 0.0
    deaf_until = 0.0


def mute(sec: float) -> None:
    State.deaf_until = max(State.deaf_until, time.time() + sec)


def play(name: str) -> None:
    path = f"/System/Library/Sounds/{SOUNDS[name]}.aiff"
    if os.path.exists(path):
        subprocess.Popen(["afplay", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        mute(0.45)


# ============================ ПЛАШКА / ХУК ============================
def _post_overlay(payload: dict) -> None:
    try:
        req = urllib.request.Request(
            OVERLAY_URL,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=0.5).close()
    except Exception:
        pass


def _notify(title: str, text: str) -> None:
    script = "on run argv\ndisplay notification (item 1 of argv) with title (item 2 of argv)\nend run"
    subprocess.run(["osascript", "-e", script, text[:220], title],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


ICONS = {"wake": "🔔", "heard": "🎯", "answer": "🤖", "error": "⚠️", "cancel": "⛔", "idle": "💤"}


def overlay(kind: str, text: str = "") -> None:
    """kind: wake | heard | answer | error | cancel | idle"""
    print(f"{ICONS.get(kind, '•')} [{kind}] {text}")
    if OVERLAY_URL:
        threading.Thread(target=_post_overlay,
                         args=({"kind": kind, "text": text, "ts": time.time()},),
                         daemon=True).start()
    if USE_NOTIFICATIONS and kind in ("answer", "error"):
        threading.Thread(target=_notify, args=("Гера", text), daemon=True).start()


# ============================== ОЗВУЧКА ==============================
def _pick_voice():
    try:
        out = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
        return SAY_VOICE if SAY_VOICE and SAY_VOICE.lower() in out.lower() else None
    except Exception:
        return None


def clean_for_speech(text: str) -> str:
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"[*#_>|~]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > MAX_SPOKEN_CHARS:
        cut = text[:MAX_SPOKEN_CHARS]
        end = max(cut.rfind(". "), cut.rfind("! "), cut.rfind("? "))
        text = cut[: end + 1] if end > 80 else cut
    return text


class Speaker:
    def __init__(self):
        self.voice = _pick_voice()
        self._p = None

    def speak(self, text: str) -> None:
        self.stop()
        t = clean_for_speech(text)
        if not (SPEAK_ANSWER and t):
            return
        cmd = ["say", "-r", str(SAY_RATE), "-f", "-"]
        if self.voice:
            cmd[1:1] = ["-v", self.voice]
        self._p = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self._p.stdin.write(t.encode("utf-8"))
            self._p.stdin.close()
        except Exception:
            pass

    def is_speaking(self) -> bool:
        return self._p is not None and self._p.poll() is None

    def stop(self) -> bool:
        was = self.is_speaking()
        if was:
            self._p.terminate()
        self._p = None
        return was


# ============================== АГЕНТ ==============================
def build_cmd(prompt: str, use_continue: bool) -> list:
    cmd = [HERMES_BIN, "-z", PROMPT_PREFIX + prompt]
    if HERMES_PROVIDER:
        cmd += ["--provider", HERMES_PROVIDER]
    if HERMES_MODEL:
        cmd += ["-m", HERMES_MODEL]
    if use_continue:
        cmd += ["--continue"]
    return cmd


class Agent:
    """Запускает `hermes -z` в отдельном процессе; умеет отменять на лету."""

    def __init__(self, on_done):
        self._lock = threading.Lock()
        self._gen = 0
        self._proc = None
        self._active = False
        self._on_done = on_done

    @property
    def busy(self) -> bool:
        with self._lock:
            return self._active

    def start(self, prompt: str) -> None:
        with self._lock:
            self._kill_locked()
            self._gen += 1
            gen = self._gen
            self._active = True
        threading.Thread(target=self._run, args=(prompt, gen), daemon=True).start()

    def cancel(self) -> bool:
        with self._lock:
            was = self._active
            self._gen += 1
            self._active = False
            self._kill_locked()
        return was

    def _kill_locked(self) -> None:
        proc, self._proc = self._proc, None
        if proc and proc.poll() is None:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except Exception:
                pass

            def _force():
                if proc.poll() is None:
                    try:
                        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    except Exception:
                        pass
            threading.Timer(3.0, _force).start()

    def _spawn(self, prompt: str, use_continue: bool, gen: int):
        with self._lock:
            if gen != self._gen:
                return None
            proc = subprocess.Popen(
                build_cmd(prompt, use_continue),
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, cwd=str(WORKDIR), env=ENV,
                start_new_session=True,
            )
            self._proc = proc
        return proc

    def _run(self, prompt: str, gen: int) -> None:
        attempts = (True, False) if CONTINUE_LAST_SESSION else (False,)
        out = err = ""
        proc = None
        for use_continue in attempts:
            proc = self._spawn(prompt, use_continue, gen)
            if proc is None:
                return
            try:
                out, err = proc.communicate(timeout=AGENT_TIMEOUT_SEC)
            except subprocess.TimeoutExpired:
                proc.kill()
                out, err = proc.communicate()
                err = (err or "") + "\nтаймаут"
            with self._lock:
                if gen != self._gen:
                    return
            if proc.returncode == 2 and use_continue:
                continue
            break
        with self._lock:
            if gen != self._gen:
                return
            self._active = False
            self._proc = None
        self._on_done((out or "").strip(), (err or "").strip(), proc.returncode)


# ====================== "ЭТО ПОХОЖЕ НА ГОЛОС?" (спектр) ======================
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

    def feed(self, frame: np.ndarray, mult: float = 1.0):
        rms = float(np.sqrt(np.mean(frame * frame)))
        thr = max(MIN_RMS, self.noise * NOISE_MULT) * mult
        loud = rms > thr
        if DEBUG and int(time.time() * 4) % 4 == 0:
            print(f"\rrms={rms:.4f} thr={thr:.4f} active={self.active}   ", end="")

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
            self.reset()
            if voiced < MIN_VOICED_FRAMES:
                print(f"🚫 отсеяно: короткий звук ({voiced} кадров)")
                return None
            if USE_SPECTRAL_GATE:
                ok, info = speech_check(audio)
                if not ok:
                    print(f"🚫 отсеяно: не похоже на речь ({info})")
                    return None
            return audio
        return None


# ============================ РАСПОЗНАВАНИЕ ============================
def transcribe(audio: np.ndarray, prompt=None):
    """Возвращает (текст, no_speech_prob, avg_logprob)."""
    kw = dict(
        path_or_hf_repo=MODEL_NAME,
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
    """Wake word должно стоять в начале фразы (до 2 слов перед ним)."""
    m = WAKE_RE.search(text)
    if not m:
        return None
    if len(norm(text[: m.start()]).split()) > WAKE_MAX_PREFIX_WORDS:
        return None
    return m


_STOP_SINGLE = {w for w in STOP_WORDS if " " not in w}
_STOP_ALL = set(STOP_WORDS) | set(STOP_PHRASES)


def is_stop(text: str) -> bool:
    words = [w for w in norm(text).split() if w not in STOP_FILLERS]
    if not words:
        return False
    if " ".join(words) in _STOP_ALL:
        return True
    return all(w in _STOP_SINGLE for w in words)


# ================================ MAIN ================================
def levels_mode():
    print("Говорите, потом стучите по столу/хлопайте. Ctrl+C — выход.")
    print("MIN_RMS должен быть выше шума комнаты и стука, но ниже вашей речи.")

    def cb(indata, frames, t, status):
        rms = float(np.sqrt(np.mean(indata ** 2)))
        print(f"\rRMS {rms:.4f} " + "█" * min(60, int(rms * 600)) + " " * 20, end="")

    with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, blocksize=FRAME, callback=cb):
        while True:
            time.sleep(1)


def main():
    if "--levels" in sys.argv:
        return levels_mode()

    WORKDIR.mkdir(parents=True, exist_ok=True)
    speaker = Speaker()

    def on_done(out: str, err: str, rc: int):
        if rc == 0 and out:
            overlay("answer", out)
            play("answer")
            mute(0.6)
            speaker.speak(out)
        elif rc == 0:
            overlay("error", "Hermes вернул пустой ответ")
            play("error")
        else:
            tail = (err or out or "неизвестная ошибка")[-300:]
            overlay("error", f"Hermes завершился с кодом {rc}: {tail}")
            play("error")

    agent = Agent(on_done)

    print("=== GERANIA v3.1 ===")
    print(f"🎙️  Загрузка {MODEL_NAME} ...")
    transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32))
    print(f"✅ Готово. Hermes: {HERMES_BIN} (provider={HERMES_PROVIDER or 'из конфига'}, "
          f"model={HERMES_MODEL or 'из конфига'})")
    print("🗣️  «Гера, <команда>». Новое «Гера» прерывает задачу. Стоп-слова: "
          + ", ".join(STOP_WORDS))

    def dispatch(cmd: str):
        cmd = clean_command(cmd)
        if not is_real_command(cmd):
            overlay("error", "Не расслышала команду")
            play("error")
            return
        overlay("heard", cmd)
        play("sent")
        agent.start(cmd)

    def cancel_input():
        State.awaiting = False
        play("cancel")
        overlay("idle", "Ввод отменён")

    def handle(utt: np.ndarray):
        waiting = State.awaiting
        text, nsp, lp = transcribe(utt, None if waiting else WAKE_PROMPT)
        if not text:
            return
        if nsp > NO_SPEECH_MAX or lp < LOGPROB_MIN:
            print(f"🚫 отсеяно: Whisper не уверен (no_speech={nsp:.2f}, logprob={lp:.2f}): {text!r}")
            return
        print(f"👂 {text}" + (f"   [no_speech={nsp:.2f}, logprob={lp:.2f}]" if DEBUG else ""))

        m = find_wake(text)
        stop = is_stop(text)

        # --- Гера слушает команду ---
        if waiting:
            State.awaiting = False
            if stop:
                cancel_input()
                return
            cmd = clean_command(text[m.end():] if m else text)
            if m and not is_real_command(cmd):       # просто повторили "Гера" — ждём дальше
                State.awaiting = True
                State.await_deadline = time.time() + AWAIT_COMMAND_SEC
                return
            dispatch(cmd)
            return

        # --- стоп-слова вне режима ввода ---
        if stop and (m or (STOP_WHEN_BUSY and (agent.busy or speaker.is_speaking()))):
            was = agent.cancel()
            was = speaker.stop() or was
            play("cancel")
            overlay("cancel", "Остановлено" if was else "Отбой")
            return

        if not m:
            return

        # --- wake word: barge-in ---
        interrupted = agent.cancel()
        interrupted = speaker.stop() or interrupted
        if interrupted:
            overlay("cancel", "Прервано новым запросом")
        play("wake")

        cmd = clean_command(text[m.end():])
        if is_real_command(cmd):
            dispatch(cmd)
        else:
            State.awaiting = True
            State.await_deadline = time.time() + AWAIT_COMMAND_SEC
            overlay("wake", "Слушаю…")

    q: "queue.Queue[np.ndarray]" = queue.Queue()

    def callback(indata, frames, t, status):
        if status:
            print(status, file=sys.stderr)
        q.put(indata[:, 0].copy())

    vad = VAD()
    try:
        with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                            blocksize=FRAME, callback=callback):
            while True:
                try:
                    frame = q.get(timeout=0.3)
                except queue.Empty:
                    frame = None
                now = time.time()

                if State.awaiting and not vad.active and now > State.await_deadline:
                    State.awaiting = False
                    overlay("idle", "Команда не прозвучала")
                    play("cancel")

                if frame is None:
                    continue
                if now < State.deaf_until:
                    vad.reset()        # не склеиваем фразу через наш собственный сигнал
                    continue

                mult = SPEAKING_THRESHOLD_MULT if speaker.is_speaking() else 1.0
                utt = vad.feed(frame, mult)
                if utt is not None:
                    handle(utt)
    except KeyboardInterrupt:
        print("\n👋 Завершаю.")
    finally:
        agent.cancel()
        speaker.stop()


if __name__ == "__main__":
    main()
