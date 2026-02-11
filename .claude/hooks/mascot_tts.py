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
  python3 ~/.claude/hooks/mascot_tts.py --emotion KEY "message"
"""

import json
import logging
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

HOOK_TIMEOUT = 1  # seconds for availability check
SYNTHESIS_TIMEOUT = 4  # seconds for synthesis
LOG_DIR = os.path.expanduser("~/.claude/logs")
LOG_FILE = os.path.join(LOG_DIR, "mascot_tts.log")

DEFAULT_MESSAGE = "Task completed"
MAX_MESSAGE_LENGTH = 30
SIGNAL_DIR = os.path.expanduser("~/.claude/utsutsu-code")
SIGNAL_FILE = os.path.join(SIGNAL_DIR, "mascot_speaking")
MUTE_FILE = os.path.join(SIGNAL_DIR, "tts_muted")

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
    """Write the mascot speaking signal file."""
    os.makedirs(SIGNAL_DIR, exist_ok=True)
    if emotion:
        signal = json.dumps({"message": text, "emotion": emotion})
    else:
        signal = text
    Path(SIGNAL_FILE).write_text(signal)


def is_muted():
    """Check if TTS audio is muted."""
    return os.path.exists(MUTE_FILE)


def clear_signal():
    """Remove the mascot speaking signal file."""
    try:
        os.unlink(SIGNAL_FILE)
    except OSError:
        pass


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
        # Escape single quotes for PowerShell string interpolation
        safe = message.replace("'", "''")
        # Non-blocking balloon tip notification
        subprocess.run(
            [
                "powershell",
                "-c",
                (
                    "Add-Type -AssemblyName System.Windows.Forms; "
                    "$n = New-Object System.Windows.Forms.NotifyIcon; "
                    "$n.Icon = [System.Drawing.SystemIcons]::Information; "
                    "$n.Visible = $true; "
                    f"$n.ShowBalloonTip(3000, 'Mascot TTS', '{safe}', "
                    "[System.Windows.Forms.ToolTipIcon]::Info); "
                    "Start-Sleep -Milliseconds 3000; "
                    "$n.Dispose()"
                ),
            ],
            check=False,
            timeout=5,
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
        safe_path = wav_path.replace("'", "''")
        subprocess.run(
            [
                "powershell",
                "-c",
                (
                    f"(New-Object System.Media.SoundPlayer('{safe_path}'))"
                    ".PlaySync()"
                ),
            ],
            timeout=5,
            check=False,
        )
    else:
        # Linux
        subprocess.run(["aplay", wav_path], timeout=5, check=False)


# ── Adapters ──────────────────────────────────────────────────


class CoeiroinkAdapter:
    """COEIROINK v2 API adapter."""

    def __init__(self, port=COEIROINK_PORT, speaker_name=None):
        self.base_url = f"http://localhost:{port}"
        self.speaker_name = speaker_name

    def is_available(self):
        try:
            api_request(self.base_url, "/v1/speakers")
            return True
        except Exception:
            return False

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
        self.base_url = f"http://localhost:{port}"
        self.speaker_name = speaker_name

    def is_available(self):
        try:
            api_request(self.base_url, "/speakers")
            return True
        except Exception:
            return False

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


class NoneAdapter:
    """No-audio adapter. Only writes signal file for mascot animation."""

    def is_available(self):
        return True

    def synthesize_and_play(self, text, emotion=None):
        import time

        write_signal(text, emotion)
        # Keep signal file for a brief moment so mascot can animate
        time.sleep(1.0)
        clear_signal()
        return True


# ── Engine Resolution ─────────────────────────────────────────


def resolve_adapter(config):
    """Resolve TTS adapter from env, config, or auto-detect."""
    engine = os.environ.get("TTS_ENGINE") or config.get("engine")
    speaker_name = os.environ.get("TTS_SPEAKER") or config.get("speaker_name")

    if engine == "coeiroink":
        port = int(config.get("coeiroink_port", COEIROINK_PORT))
        return CoeiroinkAdapter(port=port, speaker_name=speaker_name)
    elif engine == "voicevox":
        port = int(config.get("voicevox_port", VOICEVOX_PORT))
        return VoicevoxAdapter(port=port, speaker_name=speaker_name)
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

    # Parse --emotion KEY from argv
    emotion = None
    argv = sys.argv[1:]
    if len(argv) >= 2 and argv[0] == "--emotion":
        emotion = argv[1]
        argv = argv[2:]

    # Custom message from argv, stdin JSON, or default
    if argv:
        message = " ".join(argv)
    else:
        message = hook_input.get("message", DEFAULT_MESSAGE)
    message = message[:MAX_MESSAGE_LENGTH]
    logging.info("TTS fired: message=%s emotion=%s", message, emotion)

    config = load_config()
    result = {"status": "unknown"}
    muted = is_muted()

    try:
        if muted:
            logging.info("TTS muted, signal-only")
            adapter = NoneAdapter()
        else:
            adapter = resolve_adapter(config)
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
        if not muted:
            try:
                notify_fallback(message)
            except Exception:
                pass
        result = {"status": "error", "error": str(e), "message": message}

    print(json.dumps(result))


if __name__ == "__main__":
    main()
