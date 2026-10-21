# YubiKey Git Push Approval (macOS)

A macOS Git `pre-push` hook that displays a native Swift/AppKit **Touch your YubiKey** window and requires a valid hardware-backed SSH signature before allowing a push to continue.

Designed for Git pushes initiated from Terminal, VS Code, Claude Code, and Codex **when they use the local Git installation and hooks**.

> [!IMPORTANT]
> This is a local, best-effort approval mechanism, **not a tamper-proof policy**. A process with access to your Git environment can bypass a `pre-push` hook using `git push --no-verify`, change `core.hooksPath`, or push using another Git client or credential. Use protected branches, repository permissions, and server-side policies for enforcement.

## How it works

1. Git invokes the `pre-push` hook with the remote name, URL, and refs being pushed.
2. The hook creates a random challenge containing the repository path, remote details, and ref updates.
3. A Swift/AppKit helper displays a floating window explaining that a YubiKey touch is required.
4. Homebrew OpenSSH signs the challenge using a FIDO2-backed `ed25519-sk` SSH identity.
5. The hook verifies the signature against the expected public key and only then exits successfully.
6. The window closes as the hook exits. SSH may request **another touch** when the actual push authenticates.

The Swift window **does not authorize anything**: cryptographic signature verification in the hook makes the decision. The current UI is informational and has no approval button.

## Requirements

- macOS and a local GUI login session (for the popup).
- A YubiKey supporting FIDO2, configured for SSH keys.
- Xcode Command Line Tools (`xcode-select --install`) with Swift compiler.
- [Homebrew](https://brew.sh/) and FIDO2-capable OpenSSH (`brew install openssh`).
- Git and the repository's SSH remote configured for your target (e.g. GitHub or Gitea).
- The two project files: `YubiKeyTouch.swift` (UI) and `pre-push` (hook).

> A `resident` key is **not required**. For touch-only use, generate a non-resident key without `-O resident` or `-O verify-required`. A FIDO2 PIN may still be required by device policy, and may be needed when creating a resident key.

## 1. Generate a dedicated Git SSH key

If you already have `~/.ssh/yubikey_git` and `~/.ssh/yubikey_git.pub`, keep them and skip generation.

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
brew install openssh

"$(brew --prefix openssh)/bin/ssh-keygen" \
  -t ed25519-sk \
  -O application=ssh:git \
  -C "yubikey-git" \
  -f "$HOME/.ssh/yubikey_git"
```

To require the FIDO2 PIN on every push as well as a touch, add `-O verify-required`. See [PIN-protected keys](#pin-protected-keys-verify-required).

Touch the YubiKey when prompted. The local `yubikey_git` file is a **key handle**, not an exportable private key, but must be backed up securely for a non-resident credential. The `.pub` file is the public key. Avoid accidentally overwriting an existing identity.

Register the public key at your hosting provider:

```bash
cat ~/.ssh/yubikey_git.pub
```

- GitHub: **Settings → SSH and GPG keys → New SSH key**.
- Gitea: **User Settings → SSH / GPG Keys** (menu names may vary).

Verify your remote SSH server supports `sk-ssh-ed25519@openssh.com` keys.

## 2. Configure SSH for Git

Example entries in `~/.ssh/config`:

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/yubikey_git
    IdentitiesOnly yes
    IdentityAgent none
    ControlMaster no

Host git.example.com
    HostName git.example.com
    User git
    IdentityFile ~/.ssh/yubikey_git
    IdentitiesOnly yes
    IdentityAgent none
    ControlMaster no
```

Adjust the Gitea host and SSH port to match your environment. If you have generic `Host *` entries, make sure they do not introduce unexpected settings; OpenSSH uses the first obtained value for many options.

Ensure Git invokes Homebrew's SSH implementation:

```bash
git config --global core.sshCommand "$(brew --prefix openssh)/bin/ssh"
```

For a `verify-required` key, route SSH's PIN and touch prompts through the native helper instead, so they also work when the push comes from an editor or agent with no terminal:

```bash
git config --global core.sshCommand \
  "SSH_ASKPASS=$HOME/.local/bin/yubikey-touch SSH_ASKPASS_REQUIRE=force $(brew --prefix openssh)/bin/ssh"
```

Test independently:

```bash
"$(brew --prefix openssh)/bin/ssh" -T git@github.com
"$(brew --prefix openssh)/bin/ssh" -T git@git.example.com
```

The remote may report successful authentication without offering shell access. Do **not** revoke your previous working SSH keys until both services work.

## 3. Build the Swift helper

From the directory containing `YubiKeyTouch.swift`:

```bash
xcode-select --install  # only if command line tools are not installed
mkdir -p "$HOME/.local/bin"
swiftc -framework AppKit YubiKeyTouch.swift \
  -o "$HOME/.local/bin/yubikey-touch"
```

Test the popup manually:

```bash
"$HOME/.local/bin/yubikey-touch" "example-repo" "git@github.com:owner/repo.git"
```

It should show a floating window. Stop the test helper with **Ctrl+C** in the launching terminal. The window is not a touch detector by itself: the hook runs the actual signing command.

Test the PIN dialog (askpass mode, used for `verify-required` keys). It prints what you type to stdout:

```bash
"$HOME/.local/bin/yubikey-touch" "Enter PIN for ED25519-SK key: "
```

The helper is compiled and run locally; an Apple Developer Program subscription is not necessary for this local workflow.

## 4. Install the pre-push hook

First, inspect any hooks already configured:

```bash
git config --show-origin --get core.hooksPath
```

If you already use a hook manager (e.g. Husky, Lefthook, pre-commit) or a global hooks directory, integrate the YubiKey check into that setup rather than silently replacing existing hooks.

For a fresh global setup, copy this repo's `pre-push` file:

```bash
mkdir -p "$HOME/.config/git/hooks"
cp ./pre-push "$HOME/.config/git/hooks/pre-push"
chmod 700 "$HOME/.config/git/hooks/pre-push"
git config --global core.hooksPath "$HOME/.config/git/hooks"
```

The hook expects these default paths:

| Item | Path |
| --- | --- |
| Key handle | `~/.ssh/yubikey_git` |
| Public key | `~/.ssh/yubikey_git.pub` |
| Native helper | `~/.local/bin/yubikey-touch` |
| Hook | `~/.config/git/hooks/pre-push` |

It also resolves `ssh-keygen` from Homebrew. Set `REQUIRE_GUI=true` to fail closed if the helper executable cannot be started; this cannot guarantee macOS actually placed a window on screen.

**Note:** Setting a global `core.hooksPath` changes hooks for other local repositories too. If you only want this repository protected, install the hook into its `.git/hooks/pre-push` instead and do not set the global hook path.

## 5. Test before pushing

### Test FIDO2 signing alone

```bash
KEYGEN="$(brew --prefix openssh)/bin/ssh-keygen"
TMPFILE="$(mktemp)"
printf 'Touch test\n' > "$TMPFILE"
"$KEYGEN" -Y sign -f "$HOME/.ssh/yubikey_git" \
  -n git-push-approval "$TMPFILE"
ls -l "$TMPFILE.sig"
rm -f "$TMPFILE" "$TMPFILE.sig"
```

You should get a YubiKey touch request and a signature file.

### Test the hook without contacting the remote

Run from within a Git repository:

```bash
printf '' | "$HOME/.config/git/hooks/pre-push" \
  origin git@github.com:owner/repo.git
printf 'Exit status: %s\n' "$?"
```

Expect the native popup, a YubiKey touch, successful signature verification, and exit status `0`. A failed signing/verification step should produce a nonzero status.

This synthetic test has an **empty list of refs**: it checks the authentication workflow only, not real Git ref-update behavior.

### Test a real push

```bash
git push origin HEAD
```

The popup should open before Git contacts the remote for the actual push. SSH authentication may require another touch.

## 6. Troubleshooting

**`No FIDO SecurityKeyProvider specified` / `Key enrollment failed: invalid format`**

Check that you are using Homebrew's OpenSSH, not macOS `/usr/bin/ssh-keygen`:

```bash
which ssh-keygen
"$(brew --prefix openssh)/bin/ssh-keygen" -h 2>&1 | head
ssh -V
```

**Window does not appear**

Run the helper manually. Confirm the file is executable (`ls -l ~/.local/bin/yubikey-touch`) and that the caller runs in the active macOS GUI session. Headless, remote, or sandboxed agent processes may not be allowed to display windows. The hook's PID check does not prove a window is visible.

**Window appears but the YubiKey is never requested**

Run the standalone signing test above. The hook makes `ssh-keygen` ask for any PIN through the helper's dialog. If the push's own SSH login hangs or fails with a PIN error from an editor or agent, check that `core.sshCommand` sets `SSH_ASKPASS` and `SSH_ASKPASS_REQUIRE=force` (see step 2).

**Works in Terminal but fails in VS Code, Codex, or Claude Code**

Verify that the application uses local Git, the same hook path, the same key paths, and Homebrew OpenSSH. A container, remote environment or hosted agent does not automatically inherit your Mac's YubiKey or GUI access.

**`Signature verification failed`**

Verify `~/.ssh/yubikey_git.pub` is the public key matching the key handle, and that the signing and verification namespace strings are identical.

**No hook execution**

Check the effective setting inside the repository:

```bash
git config --show-origin --get core.hooksPath
git config --show-origin --get core.sshCommand
```

Local Git configuration can override global settings. Some tools use libgit2, HTTPS APIs, or another path that doesn't execute your Git hook.

## PIN-protected keys (verify-required)

With a key made using `-O verify-required`, each push asks for **2 PINs and 2 touches**: one pair for the hook's approval signature and one for the SSH login to the remote.

- The hook runs `ssh-keygen` with `SSH_ASKPASS` pointing at the helper and `SSH_ASKPASS_REQUIRE=force`. OpenSSH then shows the PIN prompt as a native dialog, even without a terminal. The hook's stdin carries Git's ref list, so it can't be used for the PIN.
- The helper switches to askpass mode when it receives exactly one argument (OpenSSH's prompt). It shows a secure field for PIN, passphrase and password prompts and a plain field for anything else. With `SSH_ASKPASS_PROMPT=confirm` it asks yes or no. With `SSH_ASKPASS_PROMPT=none` it shows the touch panel until `ssh` closes it.
- Cancel, or OK with an empty field, exits non-zero without sending a PIN to the YubiKey, so no retry is used. A wrong PIN does count: the YubiKey blocks after 3 wrong PINs in a row (unplug it to retry) and locks after 8.
- With the `core.sshCommand` from step 2, every Git SSH connection uses these dialogs, including passphrase and host-key questions for other hosts.

## Security model and limitations

- A successful cryptographic signature demonstrates that the configured FIDO2 credential signed this specific challenge. The challenge includes the remote and refs and a random nonce, limiting accidental reuse; it is not a server-verified push approval token.
- A YubiKey touch confirms **presence**, not that you reviewed a diff or approved the exact contents. The UI displays only summary information.
- `git push --no-verify` bypasses `pre-push`; local software with adequate permissions can alter hooks and key selection. This is **not** protection against a malicious coding agent with unrestricted shell access.
- Git over HTTPS or alternative credentials may not require a YubiKey touch for the actual remote authentication, even if the hook itself does.
- Interactive YubiKey SSH authentication may require an additional touch after the hook authorizes the push.
- Protect GitHub/Gitea branches and enforce access controls server-side. Consider signed commits/tags separately if you want verifiable authorship.
- This setup is meant for **interactive desktop Git use**, not unattended CI/CD. Use dedicated restricted automation credentials for CI.

## Files in this repository

```text
.
├── README.md
├── YubiKeyTouch.swift   # Native floating macOS window
└── pre-push             # Git hook: sign and verify challenge
```

The helper, hook, installer, and uninstaller are included in this repository. macOS compilation and interactive YubiKey behavior must be tested on a Mac; they cannot be verified by the Linux-only packaging checks.

## License

An MIT `LICENSE` is included. Adjust the copyright notice and license if needed before publication.

## One-command installation

After generating `~/.ssh/yubikey_git` and installing the prerequisites above, clone this repository and run:

```bash
./install.sh
```

The installer compiles the Swift helper, installs it to `~/.local/bin/yubikey-touch`, copies the hook to `~/.config/git/hooks/pre-push`, and sets the global `core.hooksPath`. It **refuses to replace a different existing pre-push hook or hooks directory**; merge manually if you already use a hook manager. Installing does not add SSH keys to GitHub or Gitea or modify your SSH configuration.

To remove the installed files:

```bash
./uninstall.sh
```

The uninstaller only removes the hook if its contents still match this repository's hook. It intentionally leaves your global `core.hooksPath` unchanged; unset that setting yourself if no other hooks depend on it.

### Optional paths

The hook supports `YUBIKEY_GIT_KEY` and `YUBIKEY_GIT_HELPER` environment overrides. The installer currently requires the default SSH key location. To use a different key or hook manager, manually integrate the script.

### Repository contents

```text
README.md
YubiKeyTouch.swift
pre-push
install.sh
uninstall.sh
LICENSE
```
