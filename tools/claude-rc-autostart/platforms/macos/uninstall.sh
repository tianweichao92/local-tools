#!/bin/bash
# local-tools:claude-rc-autostart uninstaller
set -euo pipefail
LABEL=io.github.tianweichao92.local-tools.claude-remote-control
MARKER=local-tools:claude-rc-autostart
dry_run=0
usage() { printf 'Usage: bash uninstall.sh [--dry-run] [--help]\n'; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
[ "$(uname -s)" = Darwin ] || die 'macOS only; no files were changed.'
uid=$(id -u); [ "$uid" != 0 ] || die 'Run as your normal user, not root.'
username=$(id -un)
user_home=$(dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p' | head -n 1 || true)
if [ -z "$user_home" ] || [ ! -d "$user_home" ]; then user_home=${HOME:-}; fi
[ -n "$user_home" ] && [ -d "$user_home" ] || die 'Cannot resolve current user home directory.'
user_home=$(cd "$user_home" && pwd -P)
tool_dir="$user_home/.codex/local-tools/claude-remote-control-autostart"
launcher="$tool_dir/start-claude-rc.zsh"
entry="$user_home/.codex/bin/claude-rc-autostart"
plist="$user_home/Library/LaunchAgents/$LABEL.plist"
logs_dir="$tool_dir/logs"
guard_directory() {
  [ ! -L "$1" ] || die "Refusing symlinked directory: $1"
  if [ -e "$1" ] && [ ! -d "$1" ]; then die "Refusing non-directory path: $1"; fi
}
for directory in "$user_home/.codex" "$user_home/.codex/local-tools" "$tool_dir" "$logs_dir" \
    "$user_home/.codex/bin" "$user_home/Library" "$user_home/Library/LaunchAgents"; do
  guard_directory "$directory"
done
owned() { [ -f "$1" ] && [ ! -L "$1" ] && grep -Fq "$MARKER" "$1"; }
bootout_if_loaded() {
  local state
  if state=$(launchctl print "gui/$uid/$LABEL" 2>&1); then
    launchctl bootout "gui/$uid" "$plist" || die 'Could not unload LaunchAgent; files were preserved.'
  else
    case "$state" in
      *'Could not find service'*) ;;
      *) die "Could not determine LaunchAgent state; files were preserved: $state" ;;
    esac
  fi
}
for target in "$launcher" "$entry" "$plist"; do
  if [ -e "$target" ] || [ -L "$target" ]; then
    owned "$target" || die "Refusing non-tool file: $target"
  fi
done
if [ -d "$tool_dir" ] && [ ! -d "$logs_dir" ]; then die "Refusing non-directory log path: $logs_dir"; fi
for logfile in "$logs_dir/start.log" "$logs_dir/launchd.out.log" "$logs_dir/launchd.err.log"; do
  if [ -e "$logfile" ] || [ -L "$logfile" ]; then
    [ -f "$logfile" ] && [ ! -L "$logfile" ] || die "Refusing non-regular log: $logfile"
  fi
done
if [ -d "$tool_dir" ]; then
  while IFS= read -r item; do
    case "$item" in
      "$launcher"|"$tool_dir/logs"|"$tool_dir/logs/start.log"|"$tool_dir/logs/launchd.out.log"|"$tool_dir/logs/launchd.err.log") ;;
      *) die "Refusing unexpected tool-directory content: $item" ;;
    esac
  done < <(find "$tool_dir" -mindepth 1 -print)
fi
printf 'Remove recognized tool files: %s, %s, %s\n' "$launcher" "$entry" "$plist"
if [ "$dry_run" -eq 1 ]; then printf 'Dry run: no files or services changed.\n'; exit 0; fi
if [ -f "$plist" ]; then bootout_if_loaded; fi
for target in "$plist" "$entry" "$launcher"; do if [ -f "$target" ]; then rm -f "$target"; fi; done
for target in "$tool_dir/logs/start.log" "$tool_dir/logs/launchd.out.log" "$tool_dir/logs/launchd.err.log"; do
  if [ -f "$target" ] && [ ! -L "$target" ]; then rm -f "$target"; fi
done
if [ -d "$tool_dir/logs" ]; then rmdir "$tool_dir/logs" 2>/dev/null || true; fi
if [ -d "$tool_dir" ]; then rmdir "$tool_dir" 2>/dev/null || true; fi
printf 'Uninstalled tool files; Claude sessions and authorization were untouched.\n'
