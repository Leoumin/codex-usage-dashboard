#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_APP="${1:-$SCRIPT_DIR/CodexUsageHUD.app}"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/CodexUsageHUD.app"
LABEL="local.codex.usage-hud.follow-codex"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_VALUE="$(id -u)"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "App not found: $SOURCE_APP" >&2
  exit 1
fi

/bin/launchctl bootout "gui/$UID_VALUE" "$PLIST" >/dev/null 2>&1 || true
/usr/bin/pkill -x CodexUsageHUD >/dev/null 2>&1 || true

mkdir -p "$HOME/Library/LaunchAgents" "$INSTALL_DIR"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-hud.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto --norsrc "$SOURCE_APP" "$STAGING_DIR/CodexUsageHUD.app"
/usr/bin/xattr -cr "$STAGING_DIR/CodexUsageHUD.app"
/usr/bin/codesign --verify --deep --strict "$STAGING_DIR/CodexUsageHUD.app"
/bin/rm -rf "$APP_PATH"
/bin/mv "$STAGING_DIR/CodexUsageHUD.app" "$APP_PATH"

/usr/bin/python3 - "$PLIST" "$APP_PATH" <<'PY'
import plistlib
import sys

plist_path, app_path = sys.argv[1], sys.argv[2]
command = (
    f'executable="{app_path}/Contents/MacOS/CodexUsageHUD"; '
    f'session="$(/bin/ps -axo pid=,args= | /usr/bin/awk \'BEGIN {{ needle = "/" "Applications/Codex.app/Contents/MacOS/Codex" }} index($0, needle) {{ print $1; exit }}\')"; '
    f'[[ -n "$session" ]] || session="$(/bin/ps -axo pid=,args= | /usr/bin/awk \'BEGIN {{ needle = "/" "Applications/ChatGPT.app/Contents/MacOS/ChatGPT" }} index($0, needle) {{ print $1; exit }}\')"; '
    f'[[ -n "$session" ]] || session="$(/bin/ps -axo pid=,args= | /usr/bin/awk \'BEGIN {{ needle = "/" "Applications/ChatGPT.app/Contents/Resources/codex" }} index($0, needle) {{ print $1; exit }}\')"; '
    f'if [[ -n "$session" ]]; then "$executable" --refresh-widget; fi'
)
payload = {
    "Label": "local.codex.usage-hud.follow-codex",
    "ProgramArguments": ["/bin/zsh", "-lc", command],
    "RunAtLoad": True,
    "StartInterval": 60,
}
with open(plist_path, "wb") as f:
    plistlib.dump(payload, f)
PY

/bin/launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID_VALUE/$LABEL"

echo "Installed $APP_PATH and $LABEL"
