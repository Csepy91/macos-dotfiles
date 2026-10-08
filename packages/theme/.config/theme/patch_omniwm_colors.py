#!/usr/bin/env python3
"""Patch OmniWM settings.toml color tables from palette hex tokens.

Reads hex colors from the environment (BASE, BLUE_BRIGHT, …) and rewrites the
known RGBA tables in ~/.config/omniwm/settings.toml (or path argv[1]).

Alpha values are preserved; only red/green/blue channels are updated.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def hex_to_srgb(hex_color: str) -> tuple[float, float, float]:
    h = hex_color.strip().lstrip("#")
    if len(h) != 6:
        raise ValueError(f"expected #RRGGBB, got {hex_color!r}")
    r = int(h[0:2], 16) / 255.0
    g = int(h[2:4], 16) / 255.0
    b = int(h[4:6], 16) / 255.0
    return r, g, b


def fmt(component: float) -> str:
    # Keep enough precision for OmniWM without noisy trailing zeros.
    return f"{component:.10g}"


def replace_table_rgb(text: str, header: str, rgb: tuple[float, float, float]) -> str:
    """Replace red/green/blue under [header], preserving alpha and key order."""
    r, g, b = rgb
    pattern = re.compile(
        rf"(^\[{re.escape(header)}\]\n)(.*?)(?=^\[|\Z)",
        re.MULTILINE | re.DOTALL,
    )

    def repl(match: re.Match[str]) -> str:
        head, body = match.group(1), match.group(2)
        # Only rewrite known color keys; leave unknown keys alone.
        body = re.sub(r"(?m)^red\s*=\s*.*$", f"red = {fmt(r)}", body)
        body = re.sub(r"(?m)^green\s*=\s*.*$", f"green = {fmt(g)}", body)
        body = re.sub(r"(?m)^blue\s*=\s*.*$", f"blue = {fmt(b)}", body)
        if not re.search(r"(?m)^red\s*=", body):
            # Table missing channels — append a standard block.
            alpha_m = re.search(r"(?m)^alpha\s*=\s*.*$", body)
            block = (
                f"{alpha_m.group(0)}\n" if alpha_m else "alpha = 1.0\n"
            ) + f"blue = {fmt(b)}\ngreen = {fmt(g)}\nred = {fmt(r)}\n"
            if alpha_m:
                body = re.sub(r"(?m)^alpha\s*=\s*.*$", "", body)
                body = re.sub(r"\n{3,}", "\n\n", body).lstrip("\n")
                body = block + body
            else:
                body = block + body
        return head + body

    new_text, n = pattern.subn(repl, text, count=1)
    if n != 1:
        raise RuntimeError(f"section [{header}] not found in OmniWM settings")
    return new_text


def env_hex(name: str) -> str:
    val = os.environ.get(name, "").strip()
    if not val:
        raise RuntimeError(f"missing env {name}")
    return val


def enable_borders_section(text: str) -> str:
    """Force ``[borders].enabled = true`` without touching other tables."""
    pattern = re.compile(
        r"(^\[borders\]\n)(.*?)(?=^\[|\Z)",
        re.MULTILINE | re.DOTALL,
    )

    def repl(match: re.Match[str]) -> str:
        head, body = match.group(1), match.group(2)
        if re.search(r"(?m)^enabled\s*=", body):
            body = re.sub(
                r"(?m)^(enabled\s*=\s*)\S+",
                r"\1true",
                body,
                count=1,
            )
        else:
            body = "enabled = true\n" + body.lstrip("\n")
        return head + body

    new_text, n = pattern.subn(repl, text, count=1)
    if n != 1:
        raise RuntimeError("section [borders] not found in OmniWM settings")
    return new_text


def main() -> int:
    path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path.home() / ".config/omniwm/settings.toml"
    )
    if not path.is_file():
        print(f"theme: skip OmniWM colors — missing {path}", file=sys.stderr)
        return 0

    text = path.read_text(encoding="utf-8")

    # This rice uses OmniWM built-in borders (jankyborders removed).
    # Only touch the [borders] table — never walk into later sections
    # (a cross-section search previously flipped [hiddenBar] enabled).
    text = enable_borders_section(text)

    # Map OmniWM color tables → palette tokens (focus / accent / chrome).
    mapping = {
        "borders.color": env_hex("BLUE_BRIGHT"),
        "workspaceBar.accentColor": env_hex("AMBER"),
        "overview.backdrop": env_hex("BASE"),
        "overview.windowBorders.hovered": env_hex("BLUE_BRIGHT"),
        "overview.windowBorders.normal": env_hex("THEME_BORDER"),
        "overview.windowBorders.selected": env_hex("AMBER"),
    }

    for header, hex_color in mapping.items():
        text = replace_table_rgb(text, header, hex_to_srgb(hex_color))

    path.write_text(text, encoding="utf-8")
    print(f"theme: patched OmniWM colors → {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 — surface cleanly to theme apply
        print(f"theme: OmniWM color patch failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
