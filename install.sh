#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.config/git/hooks"
HELPER="$HOME/.local/bin/yubikey-touch"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'macOS required to build the AppKit helper'
command -v swiftc >/dev/null || fail 'Swift compiler missing; run xcode-select --install'
[[ -x /opt/homebrew/opt/openssh/bin/ssh-keygen || -x /usr/local/opt/openssh/bin/ssh-keygen ]] || fail 'Homebrew OpenSSH missing; run brew install openssh'
[[ -f "$HOME/.ssh/yubikey_git" && -f "$HOME/.ssh/yubikey_git.pub" ]] || fail 'Create your YubiKey SSH identity first (see README)'
[[ -f "$ROOT/YubiKeyTouch.swift" && -f "$ROOT/pre-push" ]] || fail 'Required project files missing'
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
mkdir -p "$HOME/.local/bin" "$HOOKS"
TMP="$(mktemp "${TMPDIR:-/tmp/}yubikey-touch.XXXXXXXX")"
trap 'rm -f "$TMP"' EXIT
swiftc -framework AppKit "$ROOT/YubiKeyTouch.swift" -o "$TMP"
chmod 755 "$TMP"
mv -f "$TMP" "$HELPER"
cp "$ROOT/pre-push" "$HOOKS/pre-push"
chmod 700 "$HOOKS/pre-push"
git config --global core.hooksPath "$HOOKS"
printf 'Installed GUI helper: %s\nInstalled Git hook: %s\nGlobal hooks directory: %s\n' "$HELPER" "$HOOKS/pre-push" "$HOOKS"
echo 'Test from a Git repository: printf "" | ~/.config/git/hooks/pre-push origin git@github.com:owner/repo.git'
