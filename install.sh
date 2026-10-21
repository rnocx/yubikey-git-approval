#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.config/git/hooks"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux) if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then PLATFORM=wsl; else PLATFORM=linux; fi ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
  *) fail "Unsupported platform: $(uname -s)" ;;
esac
case "$PLATFORM" in
  wsl) WINHOME="$(wslpath -u "$(cd "$(wslpath -u 'C:\')" && cmd.exe /d /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")" ;;
  *) WINHOME="$HOME" ;;
esac
case "$PLATFORM" in
  macos)
    command -v swiftc >/dev/null || fail 'Swift compiler missing; run xcode-select --install'
    [[ -x /opt/homebrew/opt/openssh/bin/ssh-keygen || -x /usr/local/opt/openssh/bin/ssh-keygen ]] || fail 'Homebrew OpenSSH missing; run brew install openssh'
    HELPER="$HOME/.local/bin/yubikey-touch"
    ;;
  linux)
    command -v ssh-keygen >/dev/null || fail 'OpenSSH missing; install your distribution openssh-client package'
    command -v zenity >/dev/null || command -v kdialog >/dev/null || fail 'Install zenity or kdialog for the GUI prompts'
    HELPER="$HOME/.local/bin/yubikey-touch"
    ;;
  windows|wsl)
    command -v powershell.exe >/dev/null || fail 'powershell.exe not found'
    if [[ "$PLATFORM" == windows ]]; then KEYGEN="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/OpenSSH/ssh-keygen.exe"
    else KEYGEN="$(wslpath -u 'C:\Windows\System32\OpenSSH\ssh-keygen.exe')"; fi
    [[ -x "$KEYGEN" ]] || fail 'Windows OpenSSH Client missing; add it under Settings > System > Optional features'
    HELPER="$WINHOME/.local/bin/yubikey-touch.ps1"
    ;;
esac
[[ -f "$WINHOME/.ssh/yubikey_git" && -f "$WINHOME/.ssh/yubikey_git.pub" ]] || fail "Create your YubiKey SSH identity in $WINHOME/.ssh first (see README)"
[[ -f "$ROOT/pre-push" ]] || fail 'Required project files missing'
CURRENT="$(git config --global --get core.hooksPath || true)"
if [[ -n "$CURRENT" && "$CURRENT" != "$HOOKS" ]]; then
  fail "Existing global core.hooksPath is $CURRENT; integrate manually rather than overwrite"
fi
if [[ -e "$HOOKS/pre-push" ]] && ! cmp -s "$ROOT/pre-push" "$HOOKS/pre-push"; then
  fail "Existing hook found at $HOOKS/pre-push; back up/merge manually (will not overwrite)"
fi
if [[ -e "$HELPER" ]]; then
  fail "Existing helper found at $HELPER; move or remove it explicitly before installing"
fi
mkdir -p "$(dirname "$HELPER")" "$HOOKS"
TMP="$(mktemp "${TMPDIR:-/tmp}/yubikey-touch.XXXXXXXX")"
trap 'rm -f "$TMP"' EXIT
case "$PLATFORM" in
  macos) swiftc -framework AppKit "$ROOT/YubiKeyTouch.swift" -o "$TMP" ;;
  linux) cp "$ROOT/yubikey-touch-linux" "$TMP" ;;
  windows|wsl) cp "$ROOT/YubiKeyTouch.ps1" "$TMP" ;;
esac
chmod 755 "$TMP"
mv -f "$TMP" "$HELPER"
cp "$ROOT/pre-push" "$HOOKS/pre-push"
chmod 700 "$HOOKS/pre-push"
git config --global core.hooksPath "$HOOKS"
printf 'Platform: %s\nInstalled GUI helper: %s\nInstalled Git hook: %s\nGlobal hooks directory: %s\n' "$PLATFORM" "$HELPER" "$HOOKS/pre-push" "$HOOKS"
echo 'Test from a Git repository: printf "" | ~/.config/git/hooks/pre-push origin git@github.com:owner/repo.git'
