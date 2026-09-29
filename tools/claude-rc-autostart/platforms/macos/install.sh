#!/bin/bash
# local-tools:claude-rc-autostart
set -euo pipefail

LABEL=io.github.tianweichao92.local-tools.claude-remote-control
OLD_LABEL=com.tianweichao.codex.claude-remote-control
MARKER=local-tools:claude-rc-autostart
dry_run=0 no_start=0 force=0 requested_workdir=
usage() { printf 'Usage: bash install.sh [--workdir PATH] [--dry-run] [--no-start] [--force] [--help]\n'; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
quote_sh() { local s=$1; s=${s//\'/\'\\\'\'}; printf "'%s'" "$s"; }
xml_escape() { local s=$1; s=${s//&/\&amp;}; s=${s//</\&lt;}; s=${s//>/\&gt;}; s=${s//\"/\&quot;}; s=${s//\'/\&apos;}; printf '%s' "$s"; }
owned() { [ -f "$1" ] && grep -Fq "$MARKER" "$1"; }
guard_dir() { [ ! -L "$1" ] || die "Refusing symlinked directory: $1"; }
guard_file() {
  [ ! -L "$1" ] || die "Refusing symlinked file: $1"
  if [ -e "$1" ] && [ ! -f "$1" ]; then die "Refusing non-regular target: $1"; fi
  if [ -e "$1" ] && ! owned "$1" && [ "$force" -ne 1 ]; then die "Conflicting file: $1 (use --force only if you own it)"; fi
}
bootout_if_loaded() {
  local label=$1 target=$2 state
  if state=$(launchctl print "gui/$uid/$label" 2>&1); then
    launchctl bootout "gui/$uid" "$target" || die "Could not unload LaunchAgent $label; files were preserved."
  else
    case "$state" in
      *'Could not find service'*) ;;
      *) die "Could not determine LaunchAgent state for $label; files were preserved: $state" ;;
    esac
  fi
}
resolve_claude() {
  local candidate prefix=${LOCAL_TOOLS_TEST_PREFIX:-}
  candidate=$(command -v claude 2>/dev/null || true)
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  for candidate in "$prefix/opt/homebrew/bin/claude" "$prefix/usr/local/bin/claude" \
      "$user_home/.local/bin/claude" "$user_home/.claude/local/claude" "$user_home/.npm-global/bin/claude"; do
    if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workdir) [ "$#" -ge 2 ] || die '--workdir needs a path'; requested_workdir=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-start) no_start=1; shift ;;
    --force) force=1; shift ;;
    --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ "$(uname -s)" = Darwin ] || die 'macOS only; no files were changed.'
uid=$(id -u)
[ "$uid" != 0 ] || die 'Run as your normal user, not root.'
username=$(id -un)
user_home=$(dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p' | head -n 1 || true)
if [ -z "$user_home" ] || [ ! -d "$user_home" ]; then user_home=${HOME:-}; fi
[ -n "$user_home" ] && [ -d "$user_home" ] || die 'Cannot resolve current user home directory.'
user_home=$(cd "$user_home" && pwd -P)
workdir=${requested_workdir:-$user_home}
[ -d "$workdir" ] || die "Working directory does not exist: $workdir"
workdir=$(cd "$workdir" && pwd -P)
claude_bin=$(resolve_claude) || die 'Claude executable not found; install Claude Code first.'
help_text=$("$claude_bin" --help 2>/dev/null) || die 'Claude --help failed; check the installation.'
printf '%s\n' "$help_text" | grep -Fq -- '--remote-control' || die 'Claude lacks --remote-control; upgrade Claude Code.'

tool_dir="$user_home/.codex/local-tools/claude-remote-control-autostart"
bin_dir="$user_home/.codex/bin"
agent_dir="$user_home/Library/LaunchAgents"
launcher="$tool_dir/start-claude-rc.zsh"
entry="$bin_dir/claude-rc-autostart"
plist="$agent_dir/$LABEL.plist"
old_plist="$agent_dir/$OLD_LABEL.plist"
old_readme="$tool_dir/README.md"
for directory in "$user_home/.codex" "$user_home/.codex/local-tools" "$tool_dir" "$tool_dir/logs" "$bin_dir" "$user_home/Library" "$agent_dir"; do guard_dir "$directory"; done
for logfile in "$tool_dir/logs/start.log" "$tool_dir/logs/launchd.out.log" "$tool_dir/logs/launchd.err.log"; do
  [ ! -L "$logfile" ] || die "Refusing symlinked log: $logfile"
done
guard_file "$plist"

old_migration=0
old_readme_removal=0
if [ -e "$old_plist" ] || [ -L "$old_plist" ]; then
  [ ! -L "$old_plist" ] || die "Unknown legacy LaunchAgent: $old_plist"
  old_program=$(plutil -extract ProgramArguments.0 raw -o - "$old_plist" 2>/dev/null || true)
  old_argument=$(plutil -extract ProgramArguments.1 raw -o - "$old_plist" 2>/dev/null || true)
  if [ "$old_program" != "$launcher" ] || [ "$old_argument" != run ] || [ ! -f "$launcher" ] || \
     ! grep -Fq "LAUNCH_LABEL=\"$OLD_LABEL\"" "$launcher" || \
     ! grep -Fq CLAUDE_RC_STARTED "$launcher" || ! grep -Fq 'claude rc' "$launcher"; then
    die "Unknown legacy LaunchAgent; refusing migration: $old_plist"
  fi
  old_migration=1
fi
if [ "$old_migration" -eq 1 ] && [ -L "$entry" ]; then
  [ "$(readlink "$entry")" = "$launcher" ] || die "Unknown legacy command symlink: $entry"
else
  guard_file "$entry"
fi
if [ "$old_migration" -eq 0 ]; then guard_file "$launcher"; fi
if [ -e "$old_readme" ] || [ -L "$old_readme" ]; then
  if [ "$old_migration" -ne 1 ] || [ -L "$old_readme" ] || [ ! -f "$old_readme" ] || \
     ! grep -Fxq '# Claude Remote Control 开机启动' "$old_readme" || \
     ! grep -Fq 'CLAUDE_RC_LOGIN_REQUIRED' "$old_readme" || \
     ! grep -Fq "$OLD_LABEL" "$old_readme"; then
    die "Unknown tool README; refusing replacement: $old_readme"
  fi
  old_readme_removal=1
fi

printf 'Claude: %s\nWorking directory: %s\nLauncher: %s\nCommand: %s\nLaunchAgent: %s\n' "$claude_bin" "$workdir" "$launcher" "$entry" "$plist"
[ "$old_migration" -eq 0 ] || printf 'Recognized legacy LaunchAgent: %s\n' "$old_plist"
if [ "$dry_run" -eq 1 ]; then printf 'Dry run: no files or services changed.\n'; exit 0; fi

umask 077
mkdir -p "$tool_dir/logs" "$bin_dir" "$agent_dir"
temp_launcher=$(mktemp "$tool_dir/.start.XXXXXX")
temp_entry=$(mktemp "$bin_dir/.claude-rc-autostart.XXXXXX")
temp_plist=$(mktemp "$agent_dir/.claude-rc-autostart.XXXXXX")
cleanup() { rm -f "$temp_launcher" "$temp_entry" "$temp_plist"; }
trap cleanup EXIT
{
  printf '#!/bin/zsh\n# %s\n' "$MARKER"
  printf 'WORKDIR=%s\nLOGDIR=%s\nFALLBACK_CLAUDE=%s\nTEST_PREFIX=%s\nOSASCRIPT_BIN=%s\n' \
    "$(quote_sh "$workdir")" "$(quote_sh "$tool_dir/logs")" "$(quote_sh "$claude_bin")" \
    "$(quote_sh "${LOCAL_TOOLS_TEST_PREFIX:-}")" "$(quote_sh "${LOCAL_TOOLS_TEST_OSASCRIPT:-/usr/bin/osascript}")"
  cat <<'ZSH'
umask 077
mkdir -p -- "$LOGDIR"
log() { print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $1 workdir=$WORKDIR" >> "$LOGDIR/start.log" }
claude_bin=$(command -v claude 2>/dev/null)
if [[ -z $claude_bin || ! -x $claude_bin ]]; then
  for candidate in "$TEST_PREFIX/opt/homebrew/bin/claude" "$TEST_PREFIX/usr/local/bin/claude" \
    "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" "$HOME/.npm-global/bin/claude" "$FALLBACK_CLAUDE"; do
    if [[ -x $candidate ]]; then claude_bin=$candidate; break; fi
  done
fi
if [[ -z $claude_bin || ! -x $claude_bin ]]; then log claude_missing; exit 1; fi
auth_output=$("$claude_bin" auth status 2>/dev/null) || { log login_required; exit 0; }
auth_state=$(/usr/bin/osascript -l JavaScript -e 'function run(argv) {
  var value = JSON.parse(argv[0]);
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype && value.loggedIn === true ? "true" : "false";
}' "$auth_output" 2>/dev/null) || {
  log login_required
  exit 0
}
if [[ $auth_state != true ]]; then
  log login_required
  exit 0
fi
command="cd ${(q)WORKDIR} && ${(q)claude_bin} --remote-control"
if "$OSASCRIPT_BIN" -e 'on run argv' -e 'tell application "Terminal" to do script (item 1 of argv)' -e 'end run' "$command" >/dev/null 2>&1; then
  log started
else
  log terminal_error
  exit 1
fi
ZSH
} > "$temp_launcher"
{
  printf '#!/bin/zsh\n# %s\n' "$MARKER"
  printf 'exec %s "$@"\n' "$(quote_sh "$launcher")"
} > "$temp_entry"
{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '<!-- %s -->\n' "$MARKER"
  printf '%s\n' '<plist version="1.0"><dict>'
  printf '<key>Label</key><string>%s</string>\n' "$LABEL"
  printf '<key>ProgramArguments</key><array><string>%s</string></array>\n' "$(xml_escape "$launcher")"
  printf '<key>WorkingDirectory</key><string>%s</string>\n' "$(xml_escape "$workdir")"
  printf '%s\n' '<key>LimitLoadToSessionType</key><string>Aqua</string>' '<key>RunAtLoad</key><true/>'
  printf '<key>StandardOutPath</key><string>%s</string>\n' "$(xml_escape "$tool_dir/logs/launchd.out.log")"
  printf '<key>StandardErrorPath</key><string>%s</string>\n' "$(xml_escape "$tool_dir/logs/launchd.err.log")"
  printf '%s\n' '</dict></plist>'
} > "$temp_plist"
zsh -n "$temp_launcher" || die 'Generated launcher failed zsh syntax validation.'
zsh -n "$temp_entry" || die 'Generated command failed zsh syntax validation.'
plutil -lint "$temp_plist" >/dev/null || die 'Generated LaunchAgent failed plist validation.'
chmod 700 "$temp_launcher" "$temp_entry"; chmod 600 "$temp_plist"
if [ "$old_migration" -eq 1 ]; then bootout_if_loaded "$OLD_LABEL" "$old_plist"; fi
if [ -f "$plist" ]; then bootout_if_loaded "$LABEL" "$plist"; fi
if [ "$old_migration" -eq 1 ]; then
  rm -f "$old_plist"
  if [ "$old_readme_removal" -eq 1 ]; then rm -f "$old_readme"; fi
fi
mv -f "$temp_launcher" "$launcher"; mv -f "$temp_entry" "$entry"; mv -f "$temp_plist" "$plist"
if [ "$no_start" -eq 0 ]; then
  launchctl bootstrap "gui/$uid" "$plist" || die 'Files installed, but LaunchAgent could not be loaded.'
  printf 'Installed and loaded. Terminal opens only if Claude is logged in.\n'
else
  printf 'Installed for next graphical login; no session started now.\n'
fi
