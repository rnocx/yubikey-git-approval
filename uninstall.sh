#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HOME/.config/git/hooks"
TARGET="$HOOKS/pre-push"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) HELPER="$HOME/.local/bin/yubikey-touch.ps1" ;;
  Linux) if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
      HELPER="$(wslpath -u "$(cd "$(wslpath -u 'C:\')" && cmd.exe /d /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")/.local/bin/yubikey-touch.ps1"
    else HELPER="$HOME/.local/bin/yubikey-touch"; fi ;;
  *) HELPER="$HOME/.local/bin/yubikey-touch" ;;
esac
if [[ -e "$TARGET" ]]; then
  if cmp -s "$ROOT/pre-push" "$TARGET"; then rm -- "$TARGET"; echo "Removed $TARGET";
  else echo "Preserved modified hook: $TARGET" >&2; fi
fi
if [[ -e "$HELPER" ]]; then rm -- "$HELPER"; echo "Removed $HELPER"; fi
CURRENT="$(git config --global --get core.hooksPath || true)"
if [[ "$CURRENT" == "$HOOKS" ]]; then
  echo "Global core.hooksPath remains set to $HOOKS (other hooks may use it)."
  echo 'To unset if appropriate: git config --global --unset core.hooksPath'
fi
