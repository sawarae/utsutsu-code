---
name: otogee
description: ターミナル音ゲー - つくよみちゃんと一緒にリズムゲーム
user_invocable: true
---

# /otogee - Terminal Rhythm Game

A terminal-based rhythm game powered by curses. Notes fall from the top of the screen; press Space with correct timing to score points. Tsukuyomi-chan reacts to your performance via mascot signals and TTS.

## Usage

```
/otogee          # Start the rhythm game
```

## Controls

| Key | Action |
|-----|--------|
| Space | Hit note |
| Q | Quit early |

## How to Play

1. Notes (♪) fall from the top of the screen toward the judge line
2. Press Space when a note reaches the judge line
3. Timing determines your judgment: PERFECT / GREAT / GOOD / MISS
4. Build combos for score multipliers
5. Game lasts ~30 seconds, then shows your final grade (S/A/B/C/D)

## Steps

1. Run the game in the terminal:

```bash
python3 .claude/skills/otogee/otogee.py
```

2. Wait for the game to finish or the player to quit (Q key)
3. Report the final score and grade to the user

## Mascot Integration

The game automatically:
- Announces game start/end via TTS (if available)
- Writes mascot signal files for real-time expression changes during gameplay
- No manual mascot setup required; works without mascot running too

## Requirements

- Python 3 (stdlib only — uses `curses`, `time`, `json`, `os`, `subprocess`)
- Terminal that supports curses (any standard macOS/Linux terminal)
- Optional: Running mascot app for real-time reactions
- Optional: COEIROINK/VOICEVOX for TTS announcements

## Related Skills

- `/tts` — Manual TTS messages
- `/mascot-run` — Launch mascot app
