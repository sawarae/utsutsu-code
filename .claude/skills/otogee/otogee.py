#!/usr/bin/env python3
"""Terminal Rhythm Game — otogee.py

A single-lane rhythm game using curses. Notes fall from the top;
press Space when they reach the judge line. Tsukuyomi-chan reacts
via mascot signal files and TTS. Child mascots spawn on combo
milestones and speak encouraging messages before disappearing.

Controls:
  Space  — Hit note
  Q      — Quit early

Requires only Python stdlib (curses, time, json, os, subprocess, threading).
"""

import curses
import json
import os
import platform
import random
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

# ── Constants ────────────────────────────────────────────────

SIGNAL_DIR = os.path.expanduser("~/.claude/utsutsu-code")
SIGNAL_FILE = os.path.join(SIGNAL_DIR, "mascot_speaking")
SPAWN_SIGNAL = os.path.join(SIGNAL_DIR, "spawn_child")
TTS_SCRIPT = os.path.expanduser("~/.claude/hooks/mascot_tts.py")

GAME_DURATION = 30.0  # seconds
FALL_TIME = 2.0  # seconds for a note to fall from top to judge line
TARGET_FPS = 60
FRAME_TIME = 1.0 / TARGET_FPS

# Timing windows (seconds) — generous for terminal input latency
PERFECT_WINDOW = 0.080
GREAT_WINDOW = 0.160
GOOD_WINDOW = 0.250

# Scoring
PERFECT_SCORE = 300
GREAT_SCORE = 200
GOOD_SCORE = 100

# Combo multiplier thresholds
COMBO_2X = 10
COMBO_3X = 20

# Note glyph cycle
NOTE_GLYPHS = ["♪", "♫", "♩", "♬"]

# Judgment display
JUDGE_COLORS = {
    "PERFECT!": 1,  # Yellow
    "GREAT!": 2,    # Green
    "GOOD!": 3,     # Cyan
    "MISS": 4,      # Red
}

COUNTDOWN_DURATION = 3  # seconds

# Combo milestones → child mascot celebrations
COMBO_CELEBRATIONS = [
    (5,  "Joy",     "いいかんじ！"),
    (10, "Singing", "すごーい！"),
    (15, "Joy",     "のりのり！"),
    (20, "Singing", "さいこー！"),
    (25, "Joy",     "かんぺき！"),
    (30, "Singing", "でんせつ！"),
]

# macOS system sounds for hit/miss feedback
_SOUND_DIR = "/System/Library/Sounds"
SOUNDS = {
    "hit": f"{_SOUND_DIR}/Tink.aiff",
    "miss": f"{_SOUND_DIR}/Basso.aiff",
}


# ── Data Classes ─────────────────────────────────────────────

@dataclass
class Note:
    target_time: float  # When note should arrive at judge line
    active: bool = True
    hit: bool = False
    glyph: str = "♪"


@dataclass
class Judgment:
    text: str
    time: float  # When the judgment was made
    score: int = 0


@dataclass
class GameState:
    notes: list = field(default_factory=list)
    score: int = 0
    combo: int = 0
    max_combo: int = 0
    perfect_count: int = 0
    great_count: int = 0
    good_count: int = 0
    miss_count: int = 0
    last_judgment: Judgment = None
    start_time: float = 0.0
    running: bool = True
    quit_early: bool = False
    child_manager: object = None  # Set in game_main


# ── Note Chart Generation ────────────────────────────────────

def generate_chart(duration: float) -> list:
    """Generate a rhythmic note chart with varying patterns."""
    notes = []
    t = 1.0  # Start 1 second in

    random.seed(42)  # Deterministic for reproducibility

    patterns = [
        # (name, intervals in beats at 120 BPM = 0.5s per beat)
        ("quarter", [0.5, 0.5, 0.5, 0.5]),
        ("eighth", [0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25]),
        ("syncopated", [0.75, 0.25, 0.5, 0.5]),
        ("triplet", [0.333, 0.333, 0.334, 0.5, 0.5]),
        ("rest_gap", [0.5, 0.5, 1.0, 0.5, 0.5]),
        ("slow", [1.0, 1.0, 0.5, 0.5]),
        ("burst", [0.2, 0.2, 0.2, 0.2, 0.2, 1.0]),
    ]

    glyph_idx = 0
    while t < duration - 1.0:
        pattern_name, intervals = random.choice(patterns)
        for interval in intervals:
            if t >= duration - 1.0:
                break
            glyph = NOTE_GLYPHS[glyph_idx % len(NOTE_GLYPHS)]
            glyph_idx += 1
            notes.append(Note(target_time=t, glyph=glyph))
            t += interval
        # Small gap between patterns
        t += random.uniform(0.3, 0.8)

    return notes


# ── Sound Effects ────────────────────────────────────────────

def play_sound(name: str):
    """Play a short system sound (non-blocking, macOS only)."""
    if platform.system() != "Darwin":
        return
    path = SOUNDS.get(name)
    if not path or not os.path.exists(path):
        return
    try:
        subprocess.Popen(
            ["afplay", path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


# ── Mascot Bridge ────────────────────────────────────────────

def write_signal(message: str, emotion: str):
    """Write mascot signal file to parent mascot (non-blocking file I/O)."""
    try:
        os.makedirs(SIGNAL_DIR, exist_ok=True)
        payload = {"message": message, "emotion": emotion}
        signal = json.dumps({
            "version": "1",
            "type": "mascot.speech",
            "payload": payload,
        })
        Path(SIGNAL_FILE).write_text(signal, encoding="utf-8")
    except OSError:
        pass


def clear_signal():
    """Remove mascot signal file."""
    try:
        os.unlink(SIGNAL_FILE)
    except OSError:
        pass


def speak_async(emotion: str, message: str):
    """Fire-and-forget TTS via subprocess. Must be called OUTSIDE curses."""
    if not os.path.exists(TTS_SCRIPT):
        return
    try:
        subprocess.Popen(
            ["python3", TTS_SCRIPT, "--emotion", emotion, message],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


# ── Child Mascot Manager ────────────────────────────────────

class ChildMascotManager:
    """Manages child mascots that spawn on combo milestones.

    Each child mascot lifecycle:
      1. Write spawn_child signal → Flutter app creates child window
      2. Wait for child to initialize
      3. Call TTS on child's signal-dir → child speaks with lip-sync
      4. After TTS completes, dismiss → child disappears with pop animation
    """

    def __init__(self):
        self._active_ids = []
        self._threads = []
        self._lock = threading.Lock()

    def spawn_combo_child(self, combo: int, emotion: str, message: str):
        """Spawn a child mascot in a background thread."""
        task_id = f"otogee-{combo}"
        with self._lock:
            self._active_ids.append(task_id)
        t = threading.Thread(
            target=self._lifecycle,
            args=(task_id, emotion, message),
            daemon=True,
        )
        t.start()
        self._threads.append(t)

    def _lifecycle(self, task_id: str, emotion: str, message: str):
        """Background thread: spawn → speak → dismiss."""
        child_dir = os.path.join(SIGNAL_DIR, f"task-{task_id}")

        try:
            # 1. Write spawn signal for parent mascot
            self._write_spawn(task_id)

            # 2. Wait for child to initialize (Flutter needs time to create window)
            time.sleep(2.0)

            # 3. Make child speak via TTS (blocking in this thread)
            self._speak_child(child_dir, emotion, message)

            # 4. Brief pause after speaking
            time.sleep(1.5)

            # 5. Dismiss child (pop animation + close)
            self._dismiss(child_dir)
        except Exception:
            pass
        finally:
            with self._lock:
                if task_id in self._active_ids:
                    self._active_ids.remove(task_id)

    def _write_spawn(self, task_id: str):
        """Write spawn_child signal file for the parent mascot."""
        try:
            os.makedirs(SIGNAL_DIR, exist_ok=True)
            payload = {"task_id": task_id}
            Path(SPAWN_SIGNAL).write_text(json.dumps(payload), encoding="utf-8")
        except OSError:
            pass

    def _speak_child(self, child_dir: str, emotion: str, message: str):
        """Call TTS on child mascot's signal-dir (blocking)."""
        if not os.path.exists(TTS_SCRIPT):
            # Fallback: just write signal file
            self._write_child_signal(child_dir, message, emotion)
            return
        try:
            subprocess.run(
                ["python3", TTS_SCRIPT, "--signal-dir", child_dir,
                 "--emotion", emotion, message],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=8,
            )
        except (OSError, subprocess.TimeoutExpired):
            # Fallback: write signal file directly
            self._write_child_signal(child_dir, message, emotion)

    def _write_child_signal(self, child_dir: str, message: str, emotion: str):
        """Write mascot_speaking signal directly to child's dir."""
        try:
            os.makedirs(child_dir, exist_ok=True)
            speaking_path = os.path.join(child_dir, "mascot_speaking")
            payload = {"message": message, "emotion": emotion}
            signal = json.dumps({
                "version": "1",
                "type": "mascot.speech",
                "payload": payload,
            })
            Path(speaking_path).write_text(signal, encoding="utf-8")
        except OSError:
            pass

    def _dismiss(self, child_dir: str):
        """Write mascot_dismiss signal to child's dir."""
        try:
            dismiss_path = os.path.join(child_dir, "mascot_dismiss")
            Path(dismiss_path).write_text("dismiss", encoding="utf-8")
        except OSError:
            pass

    def cleanup(self):
        """Dismiss all active children and remove signal dirs."""
        with self._lock:
            ids = list(self._active_ids)
        for task_id in ids:
            child_dir = os.path.join(SIGNAL_DIR, f"task-{task_id}")
            self._dismiss(child_dir)
        # Wait briefly for animations
        time.sleep(0.5)
        # Clean up dirs
        for task_id in ids:
            child_dir = os.path.join(SIGNAL_DIR, f"task-{task_id}")
            shutil.rmtree(child_dir, ignore_errors=True)
        with self._lock:
            self._active_ids.clear()


# ── Timing Judge ─────────────────────────────────────────────

def judge_hit(state: GameState, hit_time: float) -> Judgment:
    """Find the closest active note and judge timing."""
    best_note = None
    best_diff = float("inf")

    for note in state.notes:
        if not note.active:
            continue
        diff = abs(hit_time - note.target_time)
        if diff < best_diff and diff <= GOOD_WINDOW:
            best_diff = diff
            best_note = note

    if best_note is None:
        # Pressed Space but no note nearby — play miss sound
        play_sound("miss")
        return None

    best_note.active = False
    best_note.hit = True

    if best_diff <= PERFECT_WINDOW:
        text, score = "PERFECT!", PERFECT_SCORE
        state.perfect_count += 1
    elif best_diff <= GREAT_WINDOW:
        text, score = "GREAT!", GREAT_SCORE
        state.great_count += 1
    else:
        text, score = "GOOD!", GOOD_SCORE
        state.good_count += 1

    # Play hit sound
    play_sound("hit")

    # Apply combo multiplier
    state.combo += 1
    if state.combo > state.max_combo:
        state.max_combo = state.combo

    multiplier = 1
    if state.combo >= COMBO_3X:
        multiplier = 3
    elif state.combo >= COMBO_2X:
        multiplier = 2

    final_score = score * multiplier
    state.score += final_score

    judgment = Judgment(text=text, time=hit_time, score=final_score)
    state.last_judgment = judgment

    # Parent mascot expression (signal file only — instant)
    if text == "PERFECT!":
        write_signal("パーフェクト！", "Joy")

    # Check combo milestones → spawn child mascot
    if state.child_manager:
        for threshold, emotion, msg in COMBO_CELEBRATIONS:
            if state.combo == threshold:
                state.child_manager.spawn_combo_child(threshold, emotion, msg)
                break

    return judgment


def check_misses(state: GameState, current_time: float):
    """Mark notes that passed the judge line without being hit."""
    any_miss = False
    for note in state.notes:
        if not note.active:
            continue
        if current_time - note.target_time > GOOD_WINDOW:
            note.active = False
            state.miss_count += 1
            any_miss = True
            if state.combo >= 5:
                write_signal("あっ", "Trouble")
            state.combo = 0
            state.last_judgment = Judgment(text="MISS", time=current_time)

    if any_miss:
        play_sound("miss")


# ── Grade Calculation ────────────────────────────────────────

def calculate_grade(state: GameState) -> str:
    total = state.perfect_count + state.great_count + state.good_count + state.miss_count
    if total == 0:
        return "D"
    ratio = (state.perfect_count * 3 + state.great_count * 2 + state.good_count) / (total * 3)
    if ratio >= 0.95:
        return "S"
    elif ratio >= 0.85:
        return "A"
    elif ratio >= 0.70:
        return "B"
    elif ratio >= 0.50:
        return "C"
    else:
        return "D"


# ── Rendering ────────────────────────────────────────────────

def init_colors():
    """Initialize curses color pairs."""
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_YELLOW, -1)   # PERFECT
    curses.init_pair(2, curses.COLOR_GREEN, -1)     # GREAT
    curses.init_pair(3, curses.COLOR_CYAN, -1)      # GOOD
    curses.init_pair(4, curses.COLOR_RED, -1)       # MISS
    curses.init_pair(5, curses.COLOR_MAGENTA, -1)   # Notes
    curses.init_pair(6, curses.COLOR_WHITE, -1)     # Judge line


def render_frame(stdscr, state: GameState, current_time: float):
    """Render one frame of the game."""
    stdscr.erase()
    max_y, max_x = stdscr.getmaxyx()

    if max_y < 10 or max_x < 30:
        stdscr.addstr(0, 0, "Terminal too small!")
        stdscr.refresh()
        return

    # Layout
    judge_row = max_y - 4
    note_col = max_x // 2
    hud_row = max_y - 2

    # Draw judge line
    line_str = "═" * min(max_x - 2, 40)
    line_start = max(0, note_col - len(line_str) // 2)
    try:
        stdscr.addstr(judge_row, line_start, line_str, curses.color_pair(6) | curses.A_BOLD)
    except curses.error:
        pass

    # Draw falling notes
    for note in state.notes:
        if not note.active:
            continue
        time_until = note.target_time - current_time
        if time_until > FALL_TIME or time_until < -0.5:
            continue

        # Map time to row: note reaches judge_row exactly at target_time
        progress = 1.0 - (time_until / FALL_TIME)
        row = int(progress * judge_row)

        if 1 <= row <= judge_row:
            try:
                stdscr.addstr(row, note_col, note.glyph, curses.color_pair(5) | curses.A_BOLD)
            except curses.error:
                pass

    # Draw judgment text
    if state.last_judgment:
        elapsed = current_time - state.last_judgment.time
        if elapsed < 0.5:
            text = state.last_judgment.text
            color = JUDGE_COLORS.get(text, 6)
            attr = curses.color_pair(color) | curses.A_BOLD
            jx = max(0, note_col - len(text) // 2)
            try:
                stdscr.addstr(judge_row + 1, jx, text, attr)
            except curses.error:
                pass

    # HUD: Score and Combo
    combo_str = f"Combo: {state.combo}" if state.combo > 0 else ""
    multiplier = ""
    if state.combo >= COMBO_3X:
        multiplier = " x3"
    elif state.combo >= COMBO_2X:
        multiplier = " x2"

    score_str = f"Score: {state.score}"
    time_left = max(0, GAME_DURATION - (current_time - state.start_time))
    time_str = f"Time: {time_left:.0f}s"

    try:
        stdscr.addstr(hud_row, 1, score_str, curses.A_BOLD)
        if combo_str:
            stdscr.addstr(hud_row, len(score_str) + 3, combo_str + multiplier,
                          curses.color_pair(1) | curses.A_BOLD)
        stdscr.addstr(hud_row, max_x - len(time_str) - 2, time_str)
    except curses.error:
        pass

    # Title
    title = "♪ おとげー ♪"
    try:
        stdscr.addstr(0, max(0, max_x // 2 - len(title) // 2), title,
                      curses.color_pair(5) | curses.A_BOLD)
    except curses.error:
        pass

    # Controls hint
    hint = "[Space] Hit  [Q] Quit"
    try:
        stdscr.addstr(max_y - 1, max(0, max_x // 2 - len(hint) // 2), hint, curses.A_DIM)
    except curses.error:
        pass

    stdscr.refresh()


def render_countdown(stdscr, seconds: int):
    """Show countdown before game starts."""
    max_y, max_x = stdscr.getmaxyx()
    center_y = max_y // 2
    center_x = max_x // 2

    for i in range(seconds, 0, -1):
        stdscr.erase()
        text = str(i)
        try:
            stdscr.addstr(center_y, center_x - len(text) // 2, text,
                          curses.color_pair(1) | curses.A_BOLD)
            hint = "Get ready..."
            stdscr.addstr(center_y + 2, center_x - len(hint) // 2, hint, curses.A_DIM)
        except curses.error:
            pass
        stdscr.refresh()
        time.sleep(1.0)

    # "GO!"
    stdscr.erase()
    go_text = "GO!"
    try:
        stdscr.addstr(center_y, center_x - len(go_text) // 2, go_text,
                      curses.color_pair(2) | curses.A_BOLD)
    except curses.error:
        pass
    stdscr.refresh()
    time.sleep(0.5)


def render_results(stdscr, state: GameState, grade: str):
    """Show final results screen."""
    max_y, max_x = stdscr.getmaxyx()
    center_x = max_x // 2

    stdscr.erase()
    row = max(1, max_y // 2 - 7)

    lines = [
        ("━━━ RESULTS ━━━", curses.color_pair(1) | curses.A_BOLD),
        ("", 0),
        (f"Grade: {grade}", curses.color_pair(1) | curses.A_BOLD),
        (f"Score: {state.score}", curses.A_BOLD),
        (f"Max Combo: {state.max_combo}", curses.A_BOLD),
        ("", 0),
        (f"PERFECT: {state.perfect_count}", curses.color_pair(1)),
        (f"GREAT:   {state.great_count}", curses.color_pair(2)),
        (f"GOOD:    {state.good_count}", curses.color_pair(3)),
        (f"MISS:    {state.miss_count}", curses.color_pair(4)),
        ("", 0),
        ("Press any key to exit...", curses.A_DIM),
    ]

    for text, attr in lines:
        if row >= max_y - 1:
            break
        x = max(0, center_x - len(text) // 2)
        try:
            stdscr.addstr(row, x, text, attr)
        except curses.error:
            pass
        row += 1

    stdscr.refresh()

    # Wait for keypress (blocking)
    stdscr.nodelay(False)
    stdscr.getch()


# ── Main Game Loop ───────────────────────────────────────────

def game_main(stdscr):
    """Main game entry point (called by curses.wrapper)."""
    # Setup curses
    curses.curs_set(0)  # Hide cursor
    stdscr.nodelay(True)
    stdscr.timeout(int(FRAME_TIME * 1000))
    init_colors()

    # Generate chart and init state
    state = GameState()
    state.notes = generate_chart(GAME_DURATION)
    state.child_manager = ChildMascotManager()

    # Countdown
    stdscr.nodelay(False)
    render_countdown(stdscr, COUNTDOWN_DURATION)
    stdscr.nodelay(True)
    stdscr.timeout(int(FRAME_TIME * 1000))

    # Record start time (after countdown)
    state.start_time = time.monotonic()

    # Adjust note target times to absolute time
    for note in state.notes:
        note.target_time += state.start_time

    # Game loop
    while state.running:
        now = time.monotonic()
        elapsed = now - state.start_time

        # Check game end
        if elapsed >= GAME_DURATION:
            state.running = False
            break

        # Process input — capture time at key detection for accurate judging
        try:
            key = stdscr.getch()
        except curses.error:
            key = -1

        if key == ord("q") or key == ord("Q"):
            state.quit_early = True
            state.running = False
            break
        elif key == ord(" "):
            hit_time = time.monotonic()
            judge_hit(state, hit_time)

        # Check for missed notes (use fresh timestamp)
        check_misses(state, time.monotonic())

        # Render
        render_frame(stdscr, state, time.monotonic())

    # Calculate grade
    grade = calculate_grade(state)

    # Show results
    render_results(stdscr, state, grade)

    # Clean up signal file
    clear_signal()

    return state, grade


def main():
    """Entry point. TTS calls happen outside curses for reliable audio."""
    child_manager = None

    # Game start TTS (outside curses — reliable)
    speak_async("Gentle", "おとげーすたーと")

    try:
        state, grade = curses.wrapper(game_main)
        child_manager = state.child_manager
    except KeyboardInterrupt:
        clear_signal()
        print("\nGame interrupted.")
        return

    # Cleanup child mascots
    if child_manager:
        child_manager.cleanup()

    # Game end TTS (outside curses — reliable)
    if grade == "S":
        speak_async("Singing", "エスランクおめでとう")
    elif grade in ("A", "B"):
        speak_async("Joy", "おつかれさまでした")
    else:
        speak_async("Blush", "つぎはがんばろう")

    # Print summary to stdout (for Claude to read)
    total = state.perfect_count + state.great_count + state.good_count + state.miss_count
    print(f"\n{'━' * 30}")
    print(f"  Grade: {grade}  |  Score: {state.score}")
    print(f"  Max Combo: {state.max_combo}")
    print(f"  PERFECT: {state.perfect_count}  GREAT: {state.great_count}  "
          f"GOOD: {state.good_count}  MISS: {state.miss_count}")
    print(f"  Total Notes: {total}")
    print(f"{'━' * 30}")


if __name__ == "__main__":
    main()
