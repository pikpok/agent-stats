#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PRODUCT_NAME="AgentStatsBar"
APP_NAME="Agent Stats.app"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
USER_INSTALL_DIR="$HOME/Applications"
SYSTEM_INSTALL_DIR="/Applications"
INSTALL_APP=false

usage() {
  cat <<'EOF'
Usage: ./scripts/build-app.sh [--install|--reinstall]

Builds the release app bundle into dist/Agent Stats.app.

Options:
  --install, --reinstall   Also install or reinstall the app bundle.
EOF
}

resolve_install_path() {
  local user_path="$USER_INSTALL_DIR/$APP_NAME"
  local system_path="$SYSTEM_INSTALL_DIR/$APP_NAME"

  if [[ -d "$user_path" && -d "$system_path" ]]; then
    echo "Found installed copies in both $user_path and $system_path; remove one or reinstall manually." >&2
    exit 1
  fi

  if [[ -d "$user_path" ]]; then
    printf '%s\n' "$user_path"
    return
  fi

  if [[ -d "$system_path" ]]; then
    printf '%s\n' "$system_path"
    return
  fi

  printf '%s\n' "$user_path"
}

running_install_pids() {
  local install_path="$1"
  local command_path="$install_path/Contents/MacOS/$PRODUCT_NAME"
  local line pid command

  while IFS= read -r line; do
    pid=${line%% *}
    command=${line#* }
    if [[ "$command" == "$command_path" ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -ax -o pid= -o command=)
}

for arg in "$@"; do
  case "$arg" in
    --install|--reinstall)
      INSTALL_APP=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"

echo "Building release binary..."
swift build -c release --product "$PRODUCT_NAME" --package-path "$ROOT_DIR" >/dev/null

BIN_DIR=$(swift build -c release --show-bin-path --package-path "$ROOT_DIR")

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
cp "$ROOT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "Built $APP_DIR"

if [[ "$INSTALL_APP" != true ]]; then
  exit 0
fi

INSTALL_PATH=$(resolve_install_path)
INSTALL_PARENT=$(dirname "$INSTALL_PATH")
mkdir -p "$INSTALL_PARENT"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-stats-install.XXXXXX")
STAGED_APP="$TEMP_DIR/$APP_NAME"
BACKUP_APP="$TEMP_DIR/$APP_NAME.backup"
WAS_RUNNING=false

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

while IFS= read -r pid; do
  if [[ -n "$pid" ]]; then
    WAS_RUNNING=true
    kill "$pid"
  fi
done < <(running_install_pids "$INSTALL_PATH")

if [[ "$WAS_RUNNING" == true ]]; then
  for _ in {1..50}; do
    if [[ -z "$(running_install_pids "$INSTALL_PATH")" ]]; then
      break
    fi
    sleep 0.2
  done

  if [[ -n "$(running_install_pids "$INSTALL_PATH")" ]]; then
    echo "Failed to stop the running installed app at $INSTALL_PATH" >&2
    exit 1
  fi
fi

ditto "$APP_DIR" "$STAGED_APP"

if [[ -d "$INSTALL_PATH" ]]; then
  mv "$INSTALL_PATH" "$BACKUP_APP"
fi

if ! mv "$STAGED_APP" "$INSTALL_PATH"; then
  if [[ -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALL_PATH"
  fi
  echo "Failed to install $APP_NAME to $INSTALL_PATH" >&2
  exit 1
fi

rm -rf "$BACKUP_APP"

if [[ ! -x "$INSTALL_PATH/Contents/MacOS/$PRODUCT_NAME" ]]; then
  echo "Installed app is missing $PRODUCT_NAME at $INSTALL_PATH" >&2
  exit 1
fi

echo "Installed $INSTALL_PATH"

if [[ "$WAS_RUNNING" == true ]]; then
  open -gj "$INSTALL_PATH"
  echo "Relaunched $INSTALL_PATH"
fi
