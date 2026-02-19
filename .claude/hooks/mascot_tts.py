#!/usr/bin/env python3
"""Generic mascot TTS dispatcher with adapter pattern.

Supports multiple TTS engines via adapters:
  - coeiroink: COEIROINK v2 API (port 50032)
  - voicevox:  VOICEVOX API (port 50021)
  - none:      Signal file only (no audio), for testing

Engine selection priority:
  1. TTS_ENGINE environment variable
  2. hooks/tts_config.toml file
  3. Auto-detect (try coeiroink, then voicevox, then none)

Usage:
  python3 .claude/hooks/mascot_tts.py --emotion KEY "message"
  python3 ~/.claude/hooks/mascot_tts.py --signal-dir DIR --emotion KEY "message"
"""

import json
import logging
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HOOK_TIMEOUT = 0.5  # seconds for availability check
SYNTHESIS_TIMEOUT = 4  # seconds for synthesis
LOG_DIR = os.path.expanduser("~/.claude/logs")
LOG_FILE = os.path.join(LOG_DIR, "mascot_tts.log")

DEFAULT_MESSAGE = "Task completed"
MAX_MESSAGE_LENGTH_JA = 30
MAX_MESSAGE_LENGTH_EN = 200
SIGNAL_DIR = os.path.expanduser("~/.claude/utsutsu-code")
SIGNAL_FILE = os.path.join(SIGNAL_DIR, "mascot_speaking")
MUTE_FILE = os.path.join(SIGNAL_DIR, "tts_muted")
LOCK_FILE = os.path.join(SIGNAL_DIR, "tts.lock")
LOCK_TIMEOUT = 10  # seconds to wait for lock before proceeding anyway

# Default ports
COEIROINK_PORT = 50032
VOICEVOX_PORT = 50021


def setup_logging():
    os.makedirs(LOG_DIR, exist_ok=True)
    logging.basicConfig(
        filename=LOG_FILE,
        level=logging.DEBUG,
        format="%(asctime)s %(levelname)s %(message)s",
    )


def _tcp_check(host, port, timeout=HOOK_TIMEOUT):
    """Fast TCP connect check (avoids DNS overhead of urllib)."""
    import socket
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False


def api_request(base_url, path, data=None, timeout=HOOK_TIMEOUT):
    """Make a request to a TTS API."""
    url = f"{base_url}{path}"
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method="POST" if body else "GET")
    if body:
        req.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(req, timeout=timeout)


def load_config():
    """Load TTS config from hooks/tts_config.toml if it exists."""
    config_path = os.path.join(os.path.dirname(__file__), "tts_config.toml")
    if not os.path.exists(config_path):
        return {}
    config = {}
    with open(config_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip('"')
                config[key] = val
    return config


def write_signal(text, emotion=None):
    """Write the mascot speaking signal file (envelope format v1)."""
    os.makedirs(SIGNAL_DIR, exist_ok=True)
    payload = {"message": text}
    if emotion:
        payload["emotion"] = emotion
    signal = json.dumps({
        "version": "1",
        "type": "mascot.speech",
        "payload": payload,
    })
    Path(SIGNAL_FILE).write_text(signal, encoding="utf-8")


def is_muted():
    """Check if TTS audio is muted."""
    return os.path.exists(MUTE_FILE)


def clear_signal():
    """Remove the mascot speaking signal file."""
    try:
        os.unlink(SIGNAL_FILE)
    except OSError:
        pass


class _TtsLock:
    """Cross-process file lock for serializing TTS playback.

    Prevents concurrent mascot_tts.py processes (e.g. from parallel
    subagents in /develop worktrees) from stomping on each other's
    signal files and overlapping audio playback.

    Uses fcntl.flock on Unix, msvcrt.locking on Windows.
    Falls back gracefully (proceeds without lock) on timeout.
    """

    def __init__(self, timeout=LOCK_TIMEOUT):
        self.timeout = timeout
        self._fd = None
        self._locked = False

    def __enter__(self):
        try:
            os.makedirs(SIGNAL_DIR, exist_ok=True)
        except OSError:
            pass
        try:
            self._fd = open(LOCK_FILE, "w")
            # msvcrt.locking needs at least 1 byte to lock
            if sys.platform == "win32":
                self._fd.write(" ")
                self._fd.flush()
                self._fd.seek(0)
        except OSError as e:
            logging.warning("Cannot open lock file: %s", e)
            return self

        deadline = time.monotonic() + self.timeout
        while True:
            try:
                if sys.platform == "win32":
                    import msvcrt
                    msvcrt.locking(self._fd.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self._locked = True
                return self
            except (OSError, IOError):
                if time.monotonic() >= deadline:
                    logging.warning("TTS lock timeout after %ds, proceeding", self.timeout)
                    return self
                time.sleep(0.2)

    def __exit__(self, *args):
        if self._fd:
            if self._locked:
                try:
                    if sys.platform == "win32":
                        import msvcrt
                        msvcrt.locking(self._fd.fileno(), msvcrt.LK_UNLCK, 1)
                    else:
                        import fcntl
                        fcntl.flock(self._fd, fcntl.LOCK_UN)
                except (OSError, IOError):
                    pass
            self._fd.close()
            self._fd = None
            self._locked = False


def notify_fallback(message):
    """Fallback: show platform-native notification."""
    if sys.platform == "darwin":
        # Escape backslashes and double quotes for osascript
        safe = message.replace("\\", "\\\\").replace('"', '\\"')
        subprocess.run(
            [
                "osascript",
                "-e",
                f'display notification "{safe}" with title "Mascot TTS"',
            ],
            check=False,
            timeout=3,
        )
    elif sys.platform == "win32":
        # Use -EncodedCommand to avoid all quoting/escaping issues
        # Run in background (Popen) to avoid blocking
        script = (
            "Add-Type -AssemblyName System.Windows.Forms; "
            "$n = New-Object System.Windows.Forms.NotifyIcon; "
            "$n.Icon = [System.Drawing.SystemIcons]::Information; "
            "$n.Visible = $true; "
            "$n.ShowBalloonTip(3000, 'Mascot TTS', "
            f"$env:MASCOT_MSG, "
            "[System.Windows.Forms.ToolTipIcon]::Info); "
            "Start-Sleep -Milliseconds 3000; "
            "$n.Dispose()"
        )
        import base64
        encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
        env = {**os.environ, "MASCOT_MSG": message}
        subprocess.Popen(
            ["powershell", "-EncodedCommand", encoded],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        # Linux: notify-send
        subprocess.run(
            ["notify-send", "Mascot TTS", message],
            check=False,
            timeout=3,
        )


def _play_wav(wav_path):
    """Play a WAV file using the platform's native player."""
    if sys.platform == "darwin":
        subprocess.run(["afplay", wav_path], timeout=5, check=False)
    elif sys.platform == "win32":
        # Use -EncodedCommand + env var to avoid path injection
        import base64
        script = (
            "(New-Object System.Media.SoundPlayer($env:MASCOT_WAV))"
            ".PlaySync()"
        )
        encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
        env = {**os.environ, "MASCOT_WAV": wav_path}
        subprocess.run(
            ["powershell", "-EncodedCommand", encoded],
            check=False,
            timeout=5,
            env=env,
        )
    else:
        # Linux
        subprocess.run(["aplay", wav_path], timeout=5, check=False)


# ── Adapters ──────────────────────────────────────────────────


class CoeiroinkAdapter:
    """COEIROINK v2 API adapter."""

    def __init__(self, port=COEIROINK_PORT, speaker_name=None):
        self.port = port
        self.base_url = f"http://127.0.0.1:{port}"
        self.speaker_name = speaker_name

    def is_available(self):
        return _tcp_check("127.0.0.1", self.port)

    def find_speaker(self):
        """Find speaker by name. Returns (speakerUuid, styleId)."""
        with api_request(self.base_url, "/v1/speakers") as resp:
            speakers = json.loads(resp.read())

        for speaker in speakers:
            name = speaker.get("speakerName", "")
            if self.speaker_name and self.speaker_name in name:
                styles = speaker.get("styles", [])
                if styles:
                    return speaker["speakerUuid"], styles[0]["styleId"]
            elif not self.speaker_name:
                # Use first speaker if no name specified
                styles = speaker.get("styles", [])
                if styles:
                    return speaker["speakerUuid"], styles[0]["styleId"]
        return None, None

    def synthesize_and_play(self, text, emotion=None):
        speaker_uuid, style_id = self.find_speaker()
        if speaker_uuid is None:
            return False

        # Step 1: Estimate prosody
        with api_request(
            self.base_url, "/v1/estimate_prosody", {"text": text}, SYNTHESIS_TIMEOUT
        ) as resp:
            prosody = json.loads(resp.read())

        # Step 2: Predict (generate WAV)
        predict_body = {
            "speakerUuid": speaker_uuid,
            "styleId": style_id,
            "text": text,
            "prosodyDetail": prosody["detail"],
            "speedScale": 1.0,
        }
        with api_request(
            self.base_url, "/v1/predict", predict_body, SYNTHESIS_TIMEOUT
        ) as resp:
            wav_data = resp.read()

        # Step 3: Play audio
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(wav_data)
            wav_path = f.name

        try:
            write_signal(text, emotion)
            _play_wav(wav_path)
        finally:
            clear_signal()
            os.unlink(wav_path)

        return True


class VoicevoxAdapter:
    """VOICEVOX API adapter."""

    # Emotion → VOICEVOX style name mapping (common patterns)
    EMOTION_STYLES = {
        "Gentle": "ノーマル",
        "Joy": "うれしい",
        "Blush": "照れ",
        "Trouble": "困り",
        "Singing": "ノーマル",
    }

    def __init__(self, port=VOICEVOX_PORT, speaker_name=None):
        self.port = port
        self.base_url = f"http://127.0.0.1:{port}"
        self.speaker_name = speaker_name

    def is_available(self):
        return _tcp_check("127.0.0.1", self.port)

    def find_speaker_id(self, emotion=None):
        """Find speaker ID, optionally matching emotion to style."""
        with api_request(self.base_url, "/speakers") as resp:
            speakers = json.loads(resp.read())

        target_style = self.EMOTION_STYLES.get(emotion, "ノーマル") if emotion else None

        for speaker in speakers:
            name = speaker.get("name", "")
            if self.speaker_name and self.speaker_name not in name:
                continue

            styles = speaker.get("styles", [])
            # Try to match emotion style
            if target_style:
                for style in styles:
                    if target_style in style.get("name", ""):
                        return style["id"]
            # Fallback to first style
            if styles:
                return styles[0]["id"]

            if not self.speaker_name:
                break

        return None

    def synthesize_and_play(self, text, emotion=None):
        speaker_id = self.find_speaker_id(emotion)
        if speaker_id is None:
            return False

        # Step 1: Audio query
        query_url = (
            f"/audio_query?text={urllib.request.quote(text)}&speaker={speaker_id}"
        )
        with api_request(self.base_url, query_url, timeout=SYNTHESIS_TIMEOUT) as resp:
            query = json.loads(resp.read())

        # Step 2: Synthesis
        synth_url = f"/synthesis?speaker={speaker_id}"
        with api_request(
            self.base_url, synth_url, query, SYNTHESIS_TIMEOUT
        ) as resp:
            wav_data = resp.read()

        # Step 3: Play audio
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(wav_data)
            wav_path = f.name

        try:
            write_signal(text, emotion)
            _play_wav(wav_path)
        finally:
            clear_signal()
            os.unlink(wav_path)

        return True


class GenieTtsAdapter:
    """Genie-TTS adapter for English Tsukuyomi voice (Rust binary)."""

    def __init__(self, genie_root=None):
        self.genie_root = Path(genie_root) if genie_root else None

    def _binary(self):
        return self.genie_root / "genie-tts-rs" / "target" / "release" / "genie-tts-en"

    def _data_dir(self):
        return self.genie_root / "genie-tts-rs" / "data"

    def is_available(self):
        if not self.genie_root:
            return False
        return self._binary().exists() and self._data_dir().exists()

    def synthesize_and_play(self, text, emotion=None):
        binary = self._binary()
        data_dir = self._data_dir()

        if not binary.exists():
            logging.error("genie-tts-en binary not found at %s", binary)
            return False

        wav_path = None
        try:
            write_signal(text, emotion)
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                wav_path = tmp.name

            result = subprocess.run(
                [str(binary), "--text", text, "--output", wav_path, "--data-dir", str(data_dir)],
                timeout=30,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                logging.error("Genie-TTS failed: %s", result.stderr)
                return False

            _play_wav(wav_path)
            return True
        except subprocess.TimeoutExpired:
            logging.error("Genie-TTS timed out")
            return False
        finally:
            clear_signal()
            if wav_path:
                try:
                    os.unlink(wav_path)
                except Exception:
                    pass


class NoneAdapter:
    """No-audio adapter. Only writes signal file for mascot animation."""

    def is_available(self):
        return True

    def synthesize_and_play(self, text, emotion=None):
        import time

        write_signal(text, emotion)
        # Keep signal file for a brief moment so mascot can animate
        time.sleep(5.0)
        clear_signal()
        return True


# ── Engine Resolution ─────────────────────────────────────────


def resolve_adapter(config, lang=None):
    """Resolve TTS adapter from env, config, or auto-detect."""
    # English: use Genie-TTS if available
    if lang == "en":
        genie_root = config.get("genie_tts_root")
        if genie_root:
            adapter = GenieTtsAdapter(genie_root=genie_root)
            if adapter.is_available():
                logging.info("Using Genie-TTS for English")
                return adapter
            logging.warning("Genie-TTS not available, falling back")

    engine = os.environ.get("TTS_ENGINE") or config.get("engine")
    speaker_name = os.environ.get("TTS_SPEAKER") or config.get("speaker_name")

    if engine == "coeiroink":
        port = int(config.get("coeiroink_port", COEIROINK_PORT))
        adapter = CoeiroinkAdapter(port=port, speaker_name=speaker_name)
        if adapter.is_available():
            return adapter
        logging.warning("COEIROINK not available, falling back to signal-only")
        return NoneAdapter()
    elif engine == "voicevox":
        port = int(config.get("voicevox_port", VOICEVOX_PORT))
        adapter = VoicevoxAdapter(port=port, speaker_name=speaker_name)
        if adapter.is_available():
            return adapter
        logging.warning("VOICEVOX not available, falling back to signal-only")
        return NoneAdapter()
    elif engine == "none":
        return NoneAdapter()

    # Auto-detect
    coeiroink = CoeiroinkAdapter(speaker_name=speaker_name)
    if coeiroink.is_available():
        logging.info("Auto-detected COEIROINK")
        return coeiroink

    voicevox = VoicevoxAdapter(speaker_name=speaker_name)
    if voicevox.is_available():
        logging.info("Auto-detected VOICEVOX")
        return voicevox

    logging.info("No TTS engine available, using signal-only mode")
    return NoneAdapter()


# ── Main ──────────────────────────────────────────────────────


def main():
    setup_logging()

    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        hook_input = {}

    # Parse named flags from argv
    emotion = None
    signal_dir = None
    dismiss = False
    spawn = False
    spawn_model = None
    quiet = False
    lang = None
    argv = sys.argv[1:]
    filtered = []
    i = 0
    while i < len(argv):
        if argv[i] == "--emotion" and i + 1 < len(argv):
            emotion = argv[i + 1]
            i += 2
        elif argv[i] == "--signal-dir" and i + 1 < len(argv):
            signal_dir = os.path.expanduser(argv[i + 1])
            i += 2
        elif argv[i] == "--dismiss":
            dismiss = True
            i += 1
        elif argv[i] == "--spawn":
            spawn = True
            i += 1
        elif argv[i] == "--spawn-model" and i + 1 < len(argv):
            spawn_model = argv[i + 1]
            i += 2
        elif argv[i] == "--lang" and i + 1 < len(argv):
            lang = argv[i + 1]
            i += 2
        elif argv[i] == "--quiet":
            quiet = True
            i += 1
        else:
            filtered.append(argv[i])
            i += 1
    argv = filtered

    # Override global signal paths if --signal-dir specified.
    # LOCK_FILE is intentionally NOT overridden: all processes share a
    # single audio output device, so TTS playback must serialize globally
    # regardless of which signal directory each child uses.
    if signal_dir:
        global SIGNAL_DIR, SIGNAL_FILE, MUTE_FILE
        SIGNAL_DIR = signal_dir
        SIGNAL_FILE = os.path.join(signal_dir, "mascot_speaking")
        MUTE_FILE = os.path.join(signal_dir, "tts_muted")

    # Dismiss: write dismiss signal and exit
    if dismiss:
        dismiss_path = os.path.join(SIGNAL_DIR, "mascot_dismiss")
        os.makedirs(SIGNAL_DIR, exist_ok=True)
        Path(dismiss_path).write_text("dismiss", encoding="utf-8")
        print(json.dumps({"status": "dismissed", "signal_dir": SIGNAL_DIR}))
        return

    # Spawn: write spawn_child signal to PARENT mascot's signal dir
    if spawn:
        if not signal_dir:
            print(json.dumps({"status": "error", "error": "--signal-dir required with --spawn"}))
            return
        # Always write to the default (parent) signal dir, not the overridden one
        parent_dir = os.path.expanduser("~/.claude/utsutsu-code")
        spawn_signal = os.path.join(parent_dir, "spawn_child")
        os.makedirs(parent_dir, exist_ok=True)
        # Dart expects {"task_id": "xxx"} and constructs signal dir as task-{id}
        basename = os.path.basename(signal_dir)
        task_id = basename[5:] if basename.startswith("task-") else basename
        payload = {"task_id": task_id}
        if spawn_model:
            payload["model"] = spawn_model
        Path(spawn_signal).write_text(json.dumps(payload), encoding="utf-8")
        # Ensure the child signal dir exists
        os.makedirs(signal_dir, exist_ok=True)
        print(json.dumps({"status": "spawned", "signal_dir": signal_dir}))
        return

    # Custom message from argv, stdin JSON, or default
    if argv:
        message = " ".join(argv)
    else:
        message = hook_input.get("message", DEFAULT_MESSAGE)
    max_len = MAX_MESSAGE_LENGTH_EN if lang == "en" else MAX_MESSAGE_LENGTH_JA
    message = message[:max_len]
    logging.info("TTS fired: message=%s emotion=%s", message, emotion)

    config = load_config()
    if quiet:
        config.setdefault("engine", "coeiroink")  # skip auto-detect
    result = {"status": "unknown"}
    muted = is_muted()

    # Serialize TTS across concurrent processes (parallel subagents)
    with _TtsLock():
        try:
            if muted:
                logging.info("TTS muted, signal-only")
                adapter = NoneAdapter()
            else:
                adapter = resolve_adapter(config, lang=lang)
            engine_name = type(adapter).__name__.replace("Adapter", "").lower()

            if isinstance(adapter, NoneAdapter):
                adapter.synthesize_and_play(message, emotion)
                if not muted:
                    notify_fallback(message)
                result = {
                    "status": "muted" if muted else "fallback",
                    "engine": "none",
                    "message": message,
                }
            else:
                success = adapter.synthesize_and_play(message, emotion)
                if success:
                    result = {
                        "status": "tts",
                        "engine": engine_name,
                        "message": message,
                    }
                    if emotion:
                        result["emotion"] = emotion
                    logging.info("TTS playback complete via %s", engine_name)
                else:
                    notify_fallback(message)
                    result = {
                        "status": "fallback",
                        "reason": "speaker_not_found",
                        "engine": engine_name,
                        "message": message,
                    }
                    logging.warning("Speaker not found in %s", engine_name)
        except Exception as e:
            logging.error("TTS failed: %s", e)
            # Write signal so mascot still shows bubble + lip-sync
            try:
                write_signal(message, emotion)
                time.sleep(1.0)
            finally:
                clear_signal()
            if not muted:
                try:
                    notify_fallback(message)
                except Exception:
                    pass
            result = {"status": "error", "error": str(e), "message": message}

    print(json.dumps(result))


if __name__ == "__main__":
    main()
