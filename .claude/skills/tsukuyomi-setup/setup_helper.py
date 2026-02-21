#!/usr/bin/env python3
"""Helper script for /tsukuyomi-setup skill.

Subcommands:
  check-speakers   - List speakers from COEIROINK v2 / VOICEVOX
  check-release    - Show latest GitHub release info
  download-models  - Download utsutsu2d model files

All HTTP requests use urllib (no curl pipe needed).
"""

import json
import sys
import urllib.request

COEIROINK_URL = "http://localhost:50032"
RELEASE_API = "https://api.github.com/repos/sawarae/utsutsu-code/releases/latest"
MODEL_RELEASE_API = (
    "https://api.github.com/repos/sawarae/utsutsu2d/releases/tags/v0.03"
)


def check_speakers():
    """List speakers from COEIROINK v2 and highlight つくよみちゃん."""
    try:
        with urllib.request.urlopen(
            f"{COEIROINK_URL}/v1/speakers", timeout=5
        ) as resp:
            speakers = json.loads(resp.read())
    except Exception as e:
        print(f"ERROR: Cannot connect to COEIROINK v2 - {e}")
        return 1

    found = False
    for s in speakers:
        name = s.get("speakerName", "")
        if "\u3064\u304f\u3088\u307f" in name:  # つくよみ
            styles = ", ".join(
                f'{st["styleName"]}(id={st["styleId"]})' for st in s["styles"]
            )
            print(f'Found: {name} (uuid={s["speakerUuid"]})')
            print(f"  Styles: {styles}")
            found = True

    if not found:
        print("つくよみちゃん not found. Install voice data in COEIROINK v2.")
        print("Available speakers:")
        for s in speakers:
            print(f'  {s.get("speakerName", "?")}')
        return 1

    return 0


def check_release():
    """Show latest GitHub release with Windows zip download info."""
    try:
        req = urllib.request.Request(RELEASE_API)
        req.add_header("User-Agent", "utsutsu-code-setup")
        with urllib.request.urlopen(req, timeout=10) as resp:
            release = json.loads(resp.read())
    except Exception as e:
        print(f"ERROR: Cannot fetch release info - {e}")
        return 1

    tag = release["tag_name"]
    html_url = release["html_url"]
    print(f"Latest release: {tag}")
    for asset in release.get("assets", []):
        if asset["name"].endswith(".zip"):
            size_mb = asset["size"] // 1024 // 1024
            print(f"  {asset['name']} ({size_mb} MB)")
    print(f"  Page: {html_url}")

    return 0


def download_models(dest="mascot/assets/models/blend_shape"):
    """Download .inp model files from utsutsu2d release."""
    try:
        req = urllib.request.Request(MODEL_RELEASE_API)
        req.add_header("User-Agent", "utsutsu-code-setup")
        with urllib.request.urlopen(req, timeout=10) as resp:
            release = json.loads(resp.read())
    except Exception as e:
        print(f"ERROR: Cannot fetch model release info - {e}")
        return 1

    downloaded = 0
    for asset in release["assets"]:
        url = asset["browser_download_url"]
        name = asset["name"]
        if name.endswith(".inp"):
            print(f"Downloading {name}...")
            urllib.request.urlretrieve(url, f"{dest}/{name}")
            print(f"  Saved to {dest}/{name}")
            downloaded += 1

    if downloaded == 0:
        print("No .inp files found in release")
        return 1

    print(f"Downloaded {downloaded} model(s)")

    # Copy *_mini.inp files to blend_shape_mini/ for child mascots
    import os
    import shutil

    mini_dest = os.path.join(os.path.dirname(dest), "blend_shape_mini")
    os.makedirs(mini_dest, exist_ok=True)
    for f in os.listdir(dest):
        if f.endswith("_mini.inp"):
            shutil.copy2(os.path.join(dest, f), os.path.join(mini_dest, f))
            print(f"  Copied {f} -> {mini_dest}/")
    # Copy emotions.toml for mini model if it exists
    mini_toml = os.path.join(dest.replace("blend_shape", "blend_shape_mini"), "emotions.toml")
    if not os.path.exists(os.path.join(mini_dest, "emotions.toml")):
        src_toml = os.path.join(os.path.dirname(os.path.dirname(dest)),
                                "assets", "models", "blend_shape_mini", "emotions.toml")
        if os.path.exists(src_toml):
            shutil.copy2(src_toml, os.path.join(mini_dest, "emotions.toml"))
            print(f"  Copied emotions.toml -> {mini_dest}/")

    return 0


COMMANDS = {
    "check-speakers": check_speakers,
    "check-release": check_release,
    "download-models": download_models,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(f"Usage: {sys.argv[0]} <{'|'.join(COMMANDS)}>")
        sys.exit(1)
    sys.exit(COMMANDS[sys.argv[1]]())
