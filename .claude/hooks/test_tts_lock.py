#!/usr/bin/env python3
"""Tests for mascot_tts.py concurrent lock mechanism.

Verifies that _TtsLock serializes access across multiple processes,
preventing signal file races and overlapping audio playback.
"""

import json
import multiprocessing
import os
import sys
import tempfile
import time

# Insert hooks dir into path so we can import mascot_tts
sys.path.insert(0, os.path.dirname(__file__))

import mascot_tts


def _run_tts_with_lock(args):
    """Worker function: acquire lock, write marker, sleep, clear."""
    lock_file, signal_file, worker_id, hold_time = args
    # Override globals for test isolation
    mascot_tts.SIGNAL_DIR = os.path.dirname(signal_file)
    mascot_tts.SIGNAL_FILE = signal_file
    mascot_tts.LOCK_FILE = lock_file

    acquired_at = time.monotonic()
    with mascot_tts._TtsLock(timeout=15):
        locked_at = time.monotonic()
        wait_time = locked_at - acquired_at
        # Write our worker ID to the signal file
        mascot_tts.write_signal(f"worker-{worker_id}", "Gentle")
        # Simulate TTS playback duration
        time.sleep(hold_time)
        # Read back to verify no one overwrote us
        content = open(signal_file, encoding="utf-8").read()
        mascot_tts.clear_signal()

    return {
        "worker_id": worker_id,
        "wait_time": round(wait_time, 2),
        "content_intact": f"worker-{worker_id}" in content,
    }


def test_sequential_lock():
    """Multiple processes should acquire the lock sequentially."""
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_file = os.path.join(tmpdir, "tts.lock")
        signal_file = os.path.join(tmpdir, "mascot_speaking")

        num_workers = 4
        hold_time = 0.3  # each worker holds lock for 300ms

        args = [
            (lock_file, signal_file, i, hold_time) for i in range(num_workers)
        ]

        with multiprocessing.Pool(num_workers) as pool:
            results = pool.map(_run_tts_with_lock, args)

        # All workers should have completed
        assert len(results) == num_workers, f"Expected {num_workers} results, got {len(results)}"

        # All workers should have seen their own content (no overwrites)
        for r in results:
            assert r["content_intact"], (
                f"Worker {r['worker_id']} signal was overwritten!"
            )

        # At least some workers should have waited (serialization)
        wait_times = [r["wait_time"] for r in results]
        max_wait = max(wait_times)
        # With 4 workers holding 0.3s each, the last one waits ~0.9s
        assert max_wait > hold_time * 0.5, (
            f"No serialization detected: max wait={max_wait}s, "
            f"expected at least {hold_time * 0.5}s"
        )

        print(f"  Sequential lock: {num_workers} workers, "
              f"waits={wait_times}, all content intact")


def test_lock_timeout():
    """Lock should timeout gracefully and proceed."""
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_file = os.path.join(tmpdir, "tts.lock")
        mascot_tts.SIGNAL_DIR = tmpdir
        mascot_tts.LOCK_FILE = lock_file

        # Hold the lock manually
        import fcntl
        fd = open(lock_file, "w")
        fcntl.flock(fd, fcntl.LOCK_EX)

        # Try to acquire with very short timeout — should not hang
        start = time.monotonic()
        lock = mascot_tts._TtsLock(timeout=1)
        with lock:
            elapsed = time.monotonic() - start
            # Should have waited ~1s then proceeded
            assert elapsed >= 0.8, f"Timeout too fast: {elapsed}s"
            assert elapsed < 3.0, f"Timeout too slow: {elapsed}s"
            assert not lock._locked, "Should not have acquired lock"

        # Release
        fcntl.flock(fd, fcntl.LOCK_UN)
        fd.close()

        print(f"  Lock timeout: elapsed={elapsed:.2f}s, graceful fallback")


def test_lock_cleanup():
    """Lock file descriptor should be properly closed."""
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_file = os.path.join(tmpdir, "tts.lock")
        mascot_tts.SIGNAL_DIR = tmpdir
        mascot_tts.LOCK_FILE = lock_file

        lock = mascot_tts._TtsLock(timeout=5)
        with lock:
            assert lock._fd is not None
            assert lock._locked
        # After context exit, fd should be closed
        assert lock._fd is None
        assert not lock._locked

        print("  Lock cleanup: fd properly closed")


def test_signal_not_clobbered():
    """Rapid concurrent writes should not produce corrupt JSON."""
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_file = os.path.join(tmpdir, "tts.lock")
        signal_file = os.path.join(tmpdir, "mascot_speaking")

        num_workers = 6  # simulate 6 parallel worktrees
        hold_time = 0.1

        args = [
            (lock_file, signal_file, i, hold_time) for i in range(num_workers)
        ]

        with multiprocessing.Pool(num_workers) as pool:
            results = pool.map(_run_tts_with_lock, args)

        # Every single worker should have read back valid content
        for r in results:
            assert r["content_intact"], (
                f"Worker {r['worker_id']} saw corrupted signal file!"
            )

        # Signal file should be cleaned up
        assert not os.path.exists(signal_file), "Signal file not cleaned up"

        print(f"  Signal integrity: {num_workers} concurrent workers, all intact")


if __name__ == "__main__":
    print("Testing TTS lock mechanism...")
    test_sequential_lock()
    test_lock_timeout()
    test_lock_cleanup()
    test_signal_not_clobbered()
    print("\nAll tests passed!")
