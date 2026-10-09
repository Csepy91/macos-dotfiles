#!/usr/bin/env python3
"""Register the Dotfiles Cursor theme extension and pin workbench.colorTheme.

Writes/updates:
  ~/.cursor/extensions/extensions.json
  ~/Library/Application Support/Cursor/User/settings.json

Does not wipe unrelated user settings — only ensures rice keys exist.
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

EXT_ID = "dotfiles.theme"
EXT_DIR_NAME = "dotfiles.theme-0.0.1"
THEME_LABEL = "Dotfiles"

# Keys theme apply owns; other settings are left alone.
OWNED_SETTINGS = {
    "workbench.colorTheme": THEME_LABEL,
    "window.autoDetectColorScheme": False,
    "editor.fontFamily": "JetBrainsMono Nerd Font, JetBrains Mono, Menlo, monospace",
    "editor.fontLigatures": True,
}


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments outside of strings (VS Code / Cursor JSONC)."""
    out: list[str] = []
    i = 0
    n = len(text)
    in_string = False
    escape = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and i + 1 < n:
            nxt = text[i + 1]
            if nxt == "/":
                i += 2
                while i < n and text[i] not in "\r\n":
                    i += 1
                continue
            if nxt == "*":
                i += 2
                while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                    i += 1
                i = min(i + 2, n)
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def load_json(path: Path, default):
    if not path.is_file():
        return default
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        return default
    # Cursor/VS Code settings.json is often JSONC (comments / trailing commas).
    cleaned = strip_jsonc(text)
    # Trailing commas before } or ]
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"cannot parse {path}: {exc}") from exc


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def register_extension(ext_root: Path) -> None:
    ext_dir = ext_root / EXT_DIR_NAME
    if not (ext_dir / "package.json").is_file():
        raise SystemExit(f"missing extension at {ext_dir}")

    registry = ext_root / "extensions.json"
    entries = load_json(registry, [])
    if not isinstance(entries, list):
        entries = []

    fs_path = str(ext_dir)
    location = {
        "$mid": 1,
        "fsPath": fs_path,
        "external": f"file://{fs_path}",
        "path": fs_path,
        "scheme": "file",
    }
    entry = {
        "identifier": {"id": EXT_ID},
        "version": "0.0.1",
        "location": location,
        "relativeLocation": EXT_DIR_NAME,
        "metadata": {
            "installedTimestamp": int(time.time() * 1000),
            "pinned": True,
            "source": "vsix",
        },
    }

    out = [e for e in entries if not (
        isinstance(e, dict)
        and isinstance(e.get("identifier"), dict)
        and e["identifier"].get("id") == EXT_ID
    )]
    out.append(entry)
    write_json(registry, out)
    print(f"theme: registered Cursor extension {EXT_ID} → {ext_dir}")


def ensure_settings(settings_path: Path) -> None:
    data = load_json(settings_path, {})
    if not isinstance(data, dict):
        data = {}

    changed = False
    for key, value in OWNED_SETTINGS.items():
        if data.get(key) != value:
            data[key] = value
            changed = True

    if changed or not settings_path.is_file():
        write_json(settings_path, data)
        print(f"theme: ensured Cursor settings → {settings_path}")
    else:
        print(f"theme: Cursor settings already pinned to {THEME_LABEL}")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: patch_cursor_theme.py <extensions-dir> <settings.json>",
            file=sys.stderr,
        )
        return 2
    ext_root = Path(sys.argv[1]).expanduser()
    settings = Path(sys.argv[2]).expanduser()
    register_extension(ext_root)
    ensure_settings(settings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
