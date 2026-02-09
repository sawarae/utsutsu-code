# utsutsu-code

A desktop mascot with lip-sync animation for AI coding assistants. Runs as a transparent, always-on-top macOS window with click-through on transparent areas and native dragging.

## Features

- **kokoro2d rendering**: Loads `.inp` puppet models with blend shape or parts-based animation
- **Lip-sync**: Mouth animation driven by a signal file (`~/.claude/mascot_speaking`)
- **Emotion system**: 5 emotions (Gentle, Joy, Blush, Trouble, Singing) with per-model parameter mappings
- **Generic TTS**: Pluggable TTS dispatcher supporting COEIROINK, VOICEVOX, or signal-only mode
- **Transparent window**: Click-through on transparent pixels, native window dragging
- **Config-driven**: All model parameters externalized to TOML files

## Quick Start

### Prerequisites

- Flutter SDK (3.10+)
- macOS

### Setup

```bash
# Install dependencies
flutter pub get

# Set up model directories and example configs
make setup-models

# Download fallback PNG images from release
make setup-fallback

# Place your model.inp files
# assets/models/blend_shape/model.inp
# assets/models/parts/model.inp

# Run
flutter run -d macos
```

### Without a model file

The app will launch with fallback PNG images (if downloaded via `make setup-fallback`) or a grey placeholder icon. Full puppet animation requires a `.inp` model file.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MASCOT_MODEL` | `blend_shape` | Model directory name under `assets/models/` |
| `MASCOT_MODELS_DIR` | `assets/models` | Base directory for model directories |
| `TTS_ENGINE` | (auto-detect) | TTS engine: `coeiroink`, `voicevox`, or `none` |
| `TTS_SPEAKER` | (first available) | Speaker name substring filter |

## Emotion System

Emotions are defined in `emotions.toml` and per-model `emotions.toml` configs:

| Key | Description | Usage |
|-----|-------------|-------|
| `Gentle` | Calm, gentle | Greetings, explanations, normal reports |
| `Joy` | Happy, joyful | Test passed, build succeeded, task completed |
| `Blush` | Shy, bashful | Being praised, reporting minor mistakes |
| `Trouble` | Troubled, worried | Error occurred, test failed, warning |
| `Singing` | Fun, excited | Celebration, jokes, completion fanfare |

### Signal Protocol

The TTS hook writes `~/.claude/mascot_speaking` with JSON:

```json
{"message": "text", "emotion": "Joy"}
```

The mascot controller polls this file every 100ms and applies emotion parameters + mouth animation.

## TTS Setup

```bash
# Auto-detect (tries COEIROINK → VOICEVOX → signal-only)
python3 hooks/mascot_tts.py --emotion Joy "Test message"

# Or configure explicitly
cp hooks/tts_config.example.toml hooks/tts_config.toml
# Edit tts_config.toml with your engine and speaker preferences
```

## Adding a Custom Character

1. Create a directory under `assets/models/your_character/`
2. Copy an example config: `cp config/examples/blend_shape.toml assets/models/your_character/emotions.toml`
3. Edit `emotions.toml` with your model's parameter names and values
4. Place your `model.inp` file in the directory
5. Run with `MASCOT_MODEL=your_character flutter run -d macos`

## Project Structure

```
lib/
  main.dart              # App entry point, window setup
  mascot_widget.dart     # Mascot rendering (kokoro2d + fallback)
  mascot_controller.dart # Signal file polling, emotion state, mouth animation
  model_config.dart      # TOML-based model configuration
  toml_parser.dart       # Minimal TOML parser
hooks/
  mascot_tts.py          # Generic TTS dispatcher
  tts_config.example.toml
config/examples/         # Example emotion configs for different model types
emotions.toml            # Canonical emotion key definitions
macos/Runner/
  MainFlutterWindow.swift  # Transparency, click-through, native dragging
```

## Testing

```bash
flutter test
```
