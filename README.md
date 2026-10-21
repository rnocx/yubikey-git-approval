# YubiKey Git Push Approval

A Git `pre-push` hook that displays a **Touch your YubiKey** window and requires a valid hardware-backed SSH signature before allowing a push to continue. It runs on macOS, Linux, Windows (Git for Windows) and WSL.

Designed for Git pushes initiated from a terminal, VS Code, Claude Code, and Codex **when they use the local Git installation and hooks**.

| Platform | Window | Signs with | PIN and touch prompts |
| --- | --- | --- | --- |
| macOS | Native Swift/AppKit helper (`YubiKeyTouch.swift`) | Homebrew OpenSSH | The helper's dialogs, through `SSH_ASKPASS` |
| Linux | `zenity` or `kdialog` (`yubikey-touch-linux`) | The distribution's OpenSSH (8.2 or later) | The helper's dialogs, through `SSH_ASKPASS` |
| Windows (Git Bash) | PowerShell/WinForms (`YubiKeyTouch.ps1`) | Windows' built-in OpenSSH (`C:\Windows\System32\OpenSSH`) | Windows Security (Windows Hello) |
| WSL | Same PowerShell window, on the Windows desktop | Windows' `ssh-keygen.exe`, through WSL interop | Windows Security (Windows Hello) |

The steps below are written for macOS. See [Linux](#linux), [Windows](#windows-git-for-windows) and [WSL](#wsl) for what differs.

> [!IMPORTANT]
> This is a local, best-effort approval mechanism, **not a tamper-proof policy**. A process with access to your Git environment can bypass a `pre-push` hook using `git push --no-verify`, change `core.hooksPath`, or push using another Git client or credential. Use protected branches, repository permissions, and server-side policies for enforcement.

## Why a YubiKey instead of 1Password or the Secure Enclave?

The goal is to approve every push in person, including pushes started by an editor or a coding agent. Three common ways to hold an SSH key on a Mac compare like this:

- **1Password's SSH agent** uses a software key. It is stored encrypted in your vault and synced, and 1Password signs with it in memory. Touch ID unlocks 1Password and approves the request, but the key itself is not kept in the Secure Enclave.
- **A Secure Enclave key** (for example with [Secretive](https://github.com/maxgoedjen/secretive), or native support in recent macOS versions) is created inside the Mac's security chip and can never be exported.
- **A YubiKey `ed25519-sk` key** (this project) is created inside the YubiKey and can never be exported.

| | 1Password SSH agent | macOS Secure Enclave key | YubiKey `ed25519-sk` (this project) |
| --- | --- | --- | --- |
| Where the private key lives | In the vault: encrypted, synced and exportable, and held in memory while signing | Inside this Mac's Secure Enclave, never exportable | Inside the YubiKey, never exportable; `~/.ssh/yubikey_git` is only a key handle |
| Key type | ed25519 or RSA | ECDSA P-256 only (supported by GitHub and Gitea) | ed25519-sk or ecdsa-sk |
| Approval for each signature | Approvals can be remembered per app or terminal session until 1Password locks, so later signatures can go through silently | Touch ID on every use if the key is created to require it; otherwise it signs silently | A physical touch on every signature, and a PIN with `verify-required`; nothing is cached |
| Second factor | Touch ID or the 1Password password | Touch ID, often with the Mac login password as fallback | Having the YubiKey and knowing its PIN |
| A coding agent pushing again | After one approval, more pushes in the same session may not prompt | Each push needs Touch ID, if required per use | Each push needs a new touch |
| Remote key theft | Possible through malware on an unlocked Mac, or a compromised 1Password account and its secret key | Not possible; the key can't be copied | Not possible; an attacker needs the YubiKey itself (and its PIN) |
| Stolen laptop | Exposed if the attacker can unlock 1Password | The key goes with the Mac; with password fallback, the login password is enough to sign | The key stays with you, unless the YubiKey travels with the laptop |
| Separation from the computer | The prompt is drawn by software on the same machine | Part of the Mac, but the chip enforces Touch ID even if macOS is compromised | A separate device decides, and software can't fake a touch |
| Use on several Macs | Yes, synced | No; each Mac has its own key | Yes, plug it in anywhere |
| Backup | Automatic | None; enroll each Mac separately | A second YubiKey |
| Proof the key is hardware-backed | None | Not available for SSH in practice | Optional FIDO attestation (`ssh-keygen -O write-attestation=<file>`) |
| Convenience | Synced, nothing to plug in, nothing to lose | Built in, nothing to carry, Touch ID is fast | Must be plugged in; PIN and touch for each signature |
| Works with this hook | No | Not yet: the key is reached through an agent, while the hook signs with a key handle file | Yes |

In short: against remote attackers, Secure Enclave and YubiKey keys are close, and both are far stronger than 1Password, because neither key can be copied and both can require a person for every signature. The YubiKey adds independence from the Mac: a stolen laptop doesn't carry the key, one key works on several machines, and a second YubiKey gives you a backup. The Secure Enclave is more convenient for a single Mac. If you use one, create the key to require biometrics only, without password fallback.

Two caveats:

- A touch proves **presence**, not intent. The YubiKey has no screen, so you can't see what it signs. Software running as you could show a convincing panel while it requests a signature for something else.
- A Touch ID prompt is drawn by macOS, but its text comes from the app asking for the signature, so it can mislead in the same way.

The hook checks a signature from whichever key it is configured with. The hardware key is what turns "the hook ran" into "a person touched a device". The 1Password approval options differ between versions; check **Settings → Developer** in your installation.

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

## Linux

Most distributions build OpenSSH 8.2 or later with FIDO2 support, so no extra OpenSSH is needed. Differences from the macOS steps:

- Install the packages: `sudo apt install openssh-client libfido2-1 zenity` (Debian/Ubuntu) or `sudo dnf install openssh-clients libfido2 zenity` (Fedora). On KDE, `kdialog` works instead of `zenity`.
- Your user needs access to the YubiKey's HID device. The `libfido2` or `libu2f-udev` packages ship udev rules for this; if `ssh-keygen` reports `device not found`, install them and re-plug the key.
- Use `ssh-keygen` and `ssh` from your `PATH` wherever the macOS steps say `$(brew --prefix openssh)/bin/...`.
- The helper is a shell script, not compiled: `./install.sh` copies `yubikey-touch-linux` to `~/.local/bin/yubikey-touch`.
- For a `verify-required` key, route SSH's prompts through the helper:

  ```bash
  git config --global core.sshCommand \
    "SSH_ASKPASS=$HOME/.local/bin/yubikey-touch SSH_ASKPASS_REQUIRE=force ssh"
  ```

The helper needs a graphical session (X11 or Wayland). Over plain SSH to a Linux machine there is no window, and the YubiKey would have to be attached to that machine anyway.

## Windows (Git for Windows)

Windows only lets administrators talk to a FIDO2 key directly, so OpenSSH builds that use `libfido2` (such as the one bundled with Git for Windows) can't sign as a normal user. Windows' built-in OpenSSH instead goes through Windows Hello, which shows its own **Windows Security** dialog for the PIN and touch. The hook therefore uses `C:\Windows\System32\OpenSSH\ssh-keygen.exe`, and the PowerShell window only shows which push is waiting.

1. Install [Git for Windows](https://gitforwindows.org/) and make sure the **OpenSSH Client** optional feature is installed (Windows 10 1809 or later; FIDO2 keys need its OpenSSH 8.9 or later, included in current Windows 11).
2. In PowerShell, generate the key with Windows' OpenSSH:

   ```powershell
   ssh-keygen -t ed25519-sk -O application=ssh:git -C yubikey-git -f $HOME\.ssh\yubikey_git
   ```

   Add `-O verify-required` to require the PIN on every push. Windows Security asks for the PIN and touch.
3. Use the same `~/.ssh/config` entries as in step 2 (in `%USERPROFILE%\.ssh\config`), and point Git at Windows' `ssh.exe` so the push itself also goes through Windows Hello:

   ```bash
   git config --global core.sshCommand C:/Windows/System32/OpenSSH/ssh.exe
   ```

   No `SSH_ASKPASS` setting is needed.
4. From Git Bash, run `./install.sh`. It copies `YubiKeyTouch.ps1` to `~/.local/bin/yubikey-touch.ps1` and installs the hook. Git for Windows runs the hook with its bundled Bash, including pushes from VS Code and other tools that use Git for Windows.

The window appears near the top of the screen, so it doesn't cover the Windows Security dialog. It closes itself when the hook finishes, or after 5 minutes.

## WSL

WSL has no direct access to USB devices, so the hook calls Windows' `ssh-keygen.exe` through WSL interop and the YubiKey prompts appear on the Windows desktop. Git still runs inside WSL.

1. Set up the key on the Windows side as in [Windows](#windows-git-for-windows) steps 1–2. The hook looks for `%USERPROFILE%\.ssh\yubikey_git` (for example `/mnt/c/Users/you/.ssh/yubikey_git`), not `~/.ssh` inside WSL.
2. In WSL, make Git push through Windows' `ssh.exe`, which reads the Windows `~/.ssh/config` and key:

   ```bash
   git config --global core.sshCommand ssh.exe
   ```

3. In WSL, run `./install.sh`. It installs the hook in WSL's `~/.config/git/hooks` and the PowerShell window to `%USERPROFILE%\.local\bin\yubikey-touch.ps1`.

The challenge files are kept in the Windows temp folder, so `ssh-keygen.exe` never reads files through `\\wsl$` paths.

If you would rather attach the YubiKey to WSL itself with [usbipd-win](https://github.com/dorssel/usbipd-win), follow the [Linux](#linux) instructions instead and set `YUBIKEY_GIT_SSH_KEYGEN=/usr/bin/ssh-keygen`, `YUBIKEY_GIT_KEY=$HOME/.ssh/yubikey_git` and `YUBIKEY_GIT_HELPER=$HOME/.local/bin/yubikey-touch` (with `zenity` running through WSLg). The installer doesn't set up this variant.

## Files in this repository

```text
.
├── README.md
├── YubiKeyTouch.swift    # macOS: native floating window and askpass dialogs
├── yubikey-touch-linux   # Linux: zenity/kdialog window and askpass dialogs
├── YubiKeyTouch.ps1      # Windows and WSL: WinForms window (Windows Hello asks for PIN and touch)
├── pre-push              # Git hook: sign and verify challenge
├── install.sh            # Installs the hook and the helper for the current platform
└── uninstall.sh
```

The macOS path has been tested on a Mac. The Linux, Windows and WSL paths follow the same design but need testing with a real YubiKey on each platform.

## License

An MIT `LICENSE` is included. Adjust the copyright notice and license if needed before publication.

## One-command installation

After generating `~/.ssh/yubikey_git` and installing the prerequisites above, clone this repository and run:

```bash
./install.sh
```

On macOS the installer compiles the Swift helper and installs it to `~/.local/bin/yubikey-touch` (Linux and Windows: see their sections above). It copies the hook to `~/.config/git/hooks/pre-push`, and sets the global `core.hooksPath`. It **refuses to replace a different existing pre-push hook or hooks directory**; merge manually if you already use a hook manager. Installing does not add SSH keys to GitHub or Gitea or modify your SSH configuration.

To remove the installed files:

```bash
./uninstall.sh
```

The uninstaller only removes the hook if its contents still match this repository's hook. It intentionally leaves your global `core.hooksPath` unchanged; unset that setting yourself if no other hooks depend on it.

### Optional paths

The hook supports `YUBIKEY_GIT_KEY`, `YUBIKEY_GIT_HELPER` and `YUBIKEY_GIT_SSH_KEYGEN` environment overrides. The installer currently requires the default SSH key location. To use a different key or hook manager, manually integrate the script.
