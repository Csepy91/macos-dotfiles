#!/usr/bin/env zsh
# Default handlers: text/code → Sublime Text, media → IINA.
# Uses Swift Launch Services (reliable on modern macOS); duti UTI file is kept as documentation.
set -euo pipefail

info() { print -r -- "==> $*"; }
ok() { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }

info "Setting default handlers via Launch Services…"

/usr/bin/swift -e '
import CoreServices
import Foundation
import UniformTypeIdentifiers

let sublime = "com.sublimetext.4"
let iina = "com.colliderli.iina"

@discardableResult
func setUTI(_ uti: String, _ bundle: String) -> Bool {
  let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundle as CFString)
  if status != noErr {
    fputs("! UTI \(uti) → \(bundle) failed (\(status))\n", stderr)
    return false
  }
  return true
}

func setExt(_ ext: String, _ bundle: String) {
  if let type = UTType(filenameExtension: ext) {
    _ = setUTI(type.identifier, bundle)
  } else {
    // Fall back to duti for dynamic types when available.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/duti")
    if !FileManager.default.isExecutableFile(atPath: task.executableURL!.path) {
      task.executableURL = URL(fileURLWithPath: "/usr/local/bin/duti")
    }
    guard FileManager.default.isExecutableFile(atPath: task.executableURL!.path) else { return }
    task.arguments = ["-s", bundle, ".\(ext)", "all"]
    try? task.run()
    task.waitUntilExit()
  }
}

// Explicit UTIs (stable across macOS versions)
let textUTIs = [
  "public.plain-text", "public.text", "public.source-code", "public.script",
  "public.shell-script", "public.python-script", "public.ruby-script",
  "public.perl-script", "public.php-script", "public.swift-source",
  "public.c-source", "public.c-header", "public.c-plus-plus-source",
  "public.c-plus-plus-header", "public.objective-c-source",
  "public.objective-c-plus-plus-source", "com.netscape.javascript-source",
  "public.css", "public.html", "public.xml", "public.json", "public.yaml",
  "net.daringfireball.markdown", "com.apple.property-list",
  "com.apple.xml-property-list", "com.sun.java-source",
]
let mediaUTIs = [
  "public.movie", "public.video", "public.audio", "public.mpeg", "public.mpeg-4",
  "public.mpeg-4-audio", "public.avi", "public.mp3", "public.aiff-audio",
  "com.apple.quicktime-movie", "com.microsoft.waveform-audio",
]

for u in textUTIs { _ = setUTI(u, sublime) }
for u in mediaUTIs { _ = setUTI(u, iina) }

// Extensions (covers toml/yml/mkv/etc. via UTType resolution)
let textExts = [
  "txt", "text", "md", "markdown", "mdown", "rst", "log", "csv", "tsv",
  "py", "pyi", "pyw",
  "js", "jsx", "mjs", "cjs", "ts", "tsx",
  "json", "jsonc", "json5",
  "yaml", "yml", "toml",
  "ini", "cfg", "conf", "config", "env",
  "xml", "html", "htm", "xhtml", "css", "scss", "sass", "less",
  "sh", "bash", "zsh", "fish",
  "rs", "go", "c", "h", "cpp", "hpp", "cc", "cxx", "m", "mm", "swift",
  "rb", "pl", "php", "lua", "vim", "sql",
  "nix", "tf", "hcl",
  "gitignore", "editorconfig", "gitattributes", "lock",
]
let mediaExts = [
  "mp4", "m4v", "mkv", "avi", "mov", "webm", "wmv", "flv", "mpg", "mpeg",
  "m2ts", "ts", "vob",
  "mp3", "flac", "aac", "m4a", "wav", "ogg", "opus", "wma", "aiff", "aif",
]

for e in textExts { setExt(e, sublime) }
for e in mediaExts { setExt(e, iina) }

print("✓ Launch Services handlers set (Sublime Text + IINA)")
'

ok "default apps applied"
