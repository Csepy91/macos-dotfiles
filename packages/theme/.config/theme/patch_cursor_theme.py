#!/usr/bin/env python3
"""Register the Dotfiles Cursor theme extension and pin workbench.colorTheme.

Writes/updates:
  ~/.cursor/extensions/extensions.json
  ~/Library/Application Support/Cursor/User/settings.json

Does not wipe unrelated user settings — only ensures rice keys exist.
Materializes a stowed settings.json symlink before writing (never dirties packages/).
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

# Must match publisher + name in templates/cursor-theme-package.json
# → canonical id "dotfiles.theme".
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
    """Remove // and /* */ comments and trailing commas outside of strings."""
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
        # Trailing comma before } or ] (JSONC) — only outside strings.
        if ch == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                i += 1
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def load_json(path: Path, default):
    if not path.is_file() and not path.is_symlink():
        return default
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise RuntimeError(f"cannot read {path}: {exc}") from exc
    if not text:
        return default
    cleaned = strip_jsonc(text)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"cannot parse {path}: {exc}") from exc


def materialize_symlink(path: Path) -> None:
    """Replace a stow symlink with a real file so writes do not dirty packages/."""
    if not path.is_symlink():
        return
    try:
        content = path.read_bytes()
    except OSError as exc:
        raise RuntimeError(f"cannot read symlink {path}: {exc}") from exc
    path.unlink()
    path.write_bytes(content)
    print(f"theme: materialized {path} (was stow symlink; settings now theme-owned)")


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    materialize_symlink(path)
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

    # Drop stale ids from earlier mis-named packages (publisher.name drift).
    stale_ids = {EXT_ID, "dotfiles.dotfiles-theme"}
    out = [
        e
        for e in entries
        if not (
            isinstance(e, dict)
            and isinstance(e.get("identifier"), dict)
            and e["identifier"].get("id") in stale_ids
        )
    ]
    out.append(entry)
    write_json(registry, out)
    print(f"theme: registered Cursor extension {EXT_ID} → {ext_dir}")


def ensure_settings(settings_path: Path) -> None:
    # Materialize before load/write so we never mutate a stowed package file.
    if settings_path.is_symlink():
        materialize_symlink(settings_path)

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
