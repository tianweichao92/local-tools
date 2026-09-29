#!/bin/bash
# Isolated install/uninstall regression tests. Never loads real launchd.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
install="$here/../../platforms/macos/install.sh"
uninstall="$here/../../platforms/macos/uninstall.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/stubs" "$tmp/home" "$tmp/prefix"
export HOME="$(cd "$tmp/home" && pwd -P)" LOCAL_TOOLS_TEST_PREFIX="$tmp/prefix"
export PATH="$tmp/stubs:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_UNAME=Darwin TEST_CLAUDE_HELP='--remote-control' TEST_LAUNCH_LOG="$tmp/launch.log"
export TEST_AUTH_JSON='{"loggedIn": true}' TEST_OSASCRIPT_LOG="$tmp/osascript.log"
export LOCAL_TOOLS_TEST_OSASCRIPT="$tmp/stubs/osascript"

printf '#!/bin/sh\nprintf "%%s\\n" "$TEST_UNAME"\n' > "$tmp/stubs/uname"
printf '#!/bin/sh\ncase "$1" in -u) echo 501;; -un) echo tester;; esac\n' > "$tmp/stubs/id"
printf '#!/bin/sh\nprintf "NFSHomeDirectory: %%s\\n" "$HOME"\n' > "$tmp/stubs/dscl"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$TEST_LAUNCH_LOG"\ncase "$1" in\n print) case "${TEST_PRINT_STATUS:-loaded}" in missing) echo "Could not find service" >&2; exit 113;; error) echo "permission denied" >&2; exit 5;; esac;;\n bootout) exit "${TEST_BOOTOUT_CODE:-0}";;\nesac\n' > "$tmp/stubs/launchctl"
printf '#!/bin/sh\ncase "$1" in --help) printf "%%s\\n" "$TEST_CLAUDE_HELP";; auth) printf "%%s\\n" "$TEST_AUTH_JSON"; exit "${TEST_AUTH_CODE:-0}";; esac\n' > "$tmp/stubs/claude"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$TEST_OSASCRIPT_LOG"\n' > "$tmp/stubs/osascript"
chmod +x "$tmp/stubs/"*
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_fail() { if "$@" > "$tmp/out" 2>&1; then fail "unexpected success: $*"; fi; }
assert_file() { [ -f "$1" ] || fail "missing $1"; }
assert_absent() { [ ! -e "$1" ] || fail "unexpected $1"; }
launcher="$HOME/.codex/local-tools/claude-remote-control-autostart/start-claude-rc.zsh"
entry="$HOME/.codex/bin/claude-rc-autostart"
plist="$HOME/Library/LaunchAgents/io.github.tianweichao92.local-tools.claude-remote-control.plist"
old_plist="$HOME/Library/LaunchAgents/com.tianweichao.codex.claude-remote-control.plist"

TEST_UNAME=Linux expect_fail bash "$install"
assert_absent "$HOME/.codex"
mkdir -p "$tmp/work space"
bash "$install" --workdir "$tmp/work space" --dry-run > "$tmp/out"
assert_absent "$HOME/.codex"
bash "$install" --workdir "$tmp/work space" --no-start > "$tmp/out"
assert_file "$launcher"; assert_file "$entry"; assert_file "$plist"
TEST_AUTH_CODE=1 zsh "$launcher"
grep -Fq login_required "$HOME/.codex/local-tools/claude-remote-control-autostart/logs/start.log" || fail 'missing login_required log'
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='{"loggedIn": false}' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='{"loggedIn": "true"}' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='{loggedIn:true}' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='{"nested": {"loggedIn": true}}' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='[{"loggedIn": true}]' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='null' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='1' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='prefix {"loggedIn": true}' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='<plist><dict><key>loggedIn</key><true/></dict></plist>' zsh "$launcher"
assert_absent "$tmp/osascript.log"
TEST_AUTH_JSON='not json' zsh "$launcher"
assert_absent "$tmp/osascript.log"
zsh "$launcher"
assert_file "$tmp/osascript.log"
grep -Fq -- '--remote-control' "$tmp/osascript.log" || fail 'remote control command not sent'
zsh -n "$launcher"; zsh -n "$entry"; plutil -lint "$plist" >/dev/null
grep -Fq "$tmp/work space" "$launcher" || fail 'workdir not rendered'
grep -Fq '<key>RunAtLoad</key><true/>' "$plist" || fail 'RunAtLoad missing'
if grep -Fq KeepAlive "$plist"; then fail 'KeepAlive unexpectedly present'; fi
assert_absent "$tmp/launch.log"
bash "$install" --workdir "$tmp/work space" --no-start > "$tmp/out"
TEST_BOOTOUT_CODE=5 expect_fail bash "$install" --no-start
assert_file "$launcher"; assert_file "$plist"
TEST_PRINT_STATUS=missing bash "$install" --no-start > "$tmp/out"
bash "$install" --no-start > "$tmp/out"
grep -Fq "WORKDIR='$HOME'" "$launcher" || fail 'default workdir is not resolved home'
mkdir -p "$tmp/work'quoted"
bash "$install" --workdir "$tmp/work'quoted" --no-start > "$tmp/out"
zsh -n "$launcher"

TEST_CLAUDE_HELP='no remote feature' expect_fail bash "$install" --no-start
expect_fail bash "$install" --workdir "$tmp/missing" --no-start
assert_file "$launcher"
mv "$tmp/stubs/claude" "$tmp/stubs/claude.disabled"
expect_fail bash "$install" --no-start
mv "$tmp/stubs/claude.disabled" "$tmp/stubs/claude"

# Candidate path probing: Apple Silicon, Intel, and user-level installations.
for path in "$tmp/prefix/opt/homebrew/bin/claude" "$tmp/prefix/usr/local/bin/claude" "$HOME/.local/bin/claude"; do
  mkdir -p "$(dirname "$path")"
  cp "$tmp/stubs/claude" "$path"
  mv "$tmp/stubs/claude" "$tmp/stubs/claude.disabled"
  bash "$install" --no-start > "$tmp/out"
  grep -Fq "Claude: $path" "$tmp/out" || { sed -n '1,8p' "$tmp/out" >&2; fail "candidate not selected: $path"; }
  mv "$tmp/stubs/claude.disabled" "$tmp/stubs/claude"
  rm -f "$path"
done

# Unknown replacement is rejected; --force is opt-in.
printf 'foreign\n' > "$entry"
expect_fail bash "$install" --no-start
bash "$install" --force --no-start > "$tmp/out"

# Exact known legacy signature migrates; an unknown legacy plist does not.
printf '#!/bin/zsh\nLAUNCH_LABEL="com.tianweichao.codex.claude-remote-control"\n# CLAUDE_RC_STARTED\n# claude rc\n' > "$launcher"
rm -f "$entry"
ln -s "$launcher" "$entry"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>ProgramArguments</key><array>' \
  "<string>$launcher</string><string>run</string>" '</array></dict></plist>' > "$old_plist"
printf 'foreign\n' > "$HOME/.codex/local-tools/claude-remote-control-autostart/README.md"
expect_fail bash "$install" --no-start
printf '# Claude Remote Control 开机启动\nCLAUDE_RC_LOGIN_REQUIRED\n%s\n' \
  'com.tianweichao.codex.claude-remote-control' > "$HOME/.codex/local-tools/claude-remote-control-autostart/README.md"
rm -f "$entry"
ln -s "$tmp/foreign" "$entry"
expect_fail bash "$install" --force --no-start
rm -f "$entry"
ln -s "$launcher" "$entry"
TEST_BOOTOUT_CODE=5 expect_fail bash "$install" --no-start
assert_file "$old_plist"
assert_file "$HOME/.codex/local-tools/claude-remote-control-autostart/README.md"
[ -L "$entry" ] || fail 'legacy symlink lost after failed bootout'
bash "$install" --no-start > "$tmp/out"
assert_absent "$old_plist"
assert_absent "$HOME/.codex/local-tools/claude-remote-control-autostart/README.md"
assert_file "$entry"
[ ! -L "$entry" ] || fail 'legacy symlink was not replaced'
printf 'foreign\n' > "$old_plist"
expect_fail bash "$install" --force --no-start
assert_file "$old_plist"
rm -f "$old_plist"

# Uninstall preserves unrelated files and refuses unexpected tool-directory content.
TEST_BOOTOUT_CODE=5 expect_fail bash "$uninstall"
assert_file "$launcher"; assert_file "$entry"; assert_file "$plist"
TEST_PRINT_STATUS=missing bash "$uninstall" --dry-run > "$tmp/out"
logs_dir="$HOME/.codex/local-tools/claude-remote-control-autostart/logs"
mv "$HOME/.codex/local-tools" "$tmp/external_local_tools"
ln -s "$tmp/external_local_tools" "$HOME/.codex/local-tools"
expect_fail bash "$uninstall"
assert_file "$tmp/external_local_tools/claude-remote-control-autostart/logs/start.log"
assert_file "$tmp/external_local_tools/claude-remote-control-autostart/start-claude-rc.zsh"
rm -f "$HOME/.codex/local-tools"
mv "$tmp/external_local_tools" "$HOME/.codex/local-tools"
mv "$HOME/.codex/bin" "$tmp/external_bin"
ln -s "$tmp/external_bin" "$HOME/.codex/bin"
expect_fail bash "$uninstall"
assert_file "$tmp/external_bin/claude-rc-autostart"
rm -f "$HOME/.codex/bin"
mv "$tmp/external_bin" "$HOME/.codex/bin"
mv "$HOME/Library/LaunchAgents" "$tmp/external_launch_agents"
ln -s "$tmp/external_launch_agents" "$HOME/Library/LaunchAgents"
expect_fail bash "$uninstall"
assert_file "$tmp/external_launch_agents/io.github.tianweichao92.local-tools.claude-remote-control.plist"
rm -f "$HOME/Library/LaunchAgents"
mv "$tmp/external_launch_agents" "$HOME/Library/LaunchAgents"
mv "$logs_dir" "$tmp/external_logs"
ln -s "$tmp/external_logs" "$logs_dir"
expect_fail bash "$uninstall"
assert_file "$tmp/external_logs/start.log"
rm -f "$logs_dir"
mv "$tmp/external_logs" "$logs_dir"
mv "$logs_dir" "$tmp/external_logs"
expect_fail bash "$uninstall"
mv "$tmp/external_logs" "$logs_dir"
printf 'keep\n' > "$HOME/.codex/bin/unrelated"
printf 'keep\n' > "$HOME/.codex/local-tools/claude-remote-control-autostart/foreign"
expect_fail bash "$uninstall"
rm -f "$HOME/.codex/local-tools/claude-remote-control-autostart/foreign"
bash "$uninstall" --dry-run > "$tmp/out"
assert_file "$launcher"
bash "$uninstall" > "$tmp/out"
assert_absent "$launcher"; assert_absent "$entry"; assert_absent "$plist"
assert_file "$HOME/.codex/bin/unrelated"
mkdir "$entry"
expect_fail bash "$install" --force --no-start
assert_absent "$launcher"; assert_absent "$plist"
rmdir "$entry"
mv "$tmp/stubs/claude" "$tmp/stubs/claude.disabled"
expect_fail bash "$install" --no-start
assert_absent "$launcher"; assert_absent "$plist"
printf 'PASS: isolated macOS install/uninstall cases\n'
