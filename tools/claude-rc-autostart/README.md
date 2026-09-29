# Claude Remote Control autostart

Open Terminal.app and start `claude --remote-control` once at macOS graphical login. Closing the session does not restart it. Claude Code must already be installed and support `--remote-control`; this tool never installs Claude or handles its credentials.

| Platform | Status | Implementation |
| --- | --- | --- |
| macOS | Supported | Terminal.app and a per-user LaunchAgent |
| Windows | Not yet supported | None |
| Linux | Not yet supported | None |

Install from `main`:

```sh
curl -fsSL https://raw.githubusercontent.com/tianweichao92/local-tools/main/tools/claude-rc-autostart/platforms/macos/install.sh | bash
```

For a reproducible install after `v0.1.0` is published, replace `main` in the URL with `v0.1.0`. To choose a working directory:

```sh
curl -fsSL https://raw.githubusercontent.com/tianweichao92/local-tools/main/tools/claude-rc-autostart/platforms/macos/install.sh | bash -s -- --workdir "/path/to/workspace"
```

You can also download and inspect the script before running it.

Options: `--dry-run` previews without writing; `--no-start` writes the LaunchAgent file but does not load it in the current session (it loads at the next graphical login); `--force` permits replacement of conflicting same-name regular files; `--help` prints usage. `--force` never authorizes taking over an unknown legacy LaunchAgent or replacing special files.

The installer writes only to the current user's `~/.codex/local-tools/claude-remote-control-autostart/`, `~/.codex/bin/claude-rc-autostart`, and `~/Library/LaunchAgents/io.github.tianweichao92.local-tools.claude-remote-control.plist`. Its logs contain timestamps, startup outcomes, workdir, and error types, but no prompts or session data. If Claude is not logged in, it records `login_required` and does not perform authentication.

To uninstall, run the [uninstall script](platforms/macos/uninstall.sh) with `bash`. It removes only recognized files owned by this tool and never removes Claude sessions or authorization. `--dry-run` previews removal.
