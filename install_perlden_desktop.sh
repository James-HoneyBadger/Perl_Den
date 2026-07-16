#!/usr/bin/env bash
# ======================================================================
# install_perlden_desktop.sh - Install/uninstall PerlDen desktop menu entry
#
# Creates a desktop launcher in the freedesktop application menu and
# installs a matching icon into the user's local icon theme.  The launcher
# points at the repo's perlden-gui wrapper, so it works from a source checkout.
# ======================================================================
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

APP_ID="perlden"
DESKTOP_FILE="${APP_ID}.desktop"
ICON_NAME="${APP_ID}"

USER_APP_DIR="${HOME}/.local/share/applications"
SYSTEM_APP_DIR="/usr/local/share/applications"
USER_ICON_DIR="${HOME}/.local/share/icons/hicolor"
SYSTEM_ICON_DIR="/usr/local/share/icons/hicolor"

MODE="user"
UNINSTALL=0

usage() {
  cat <<EOF
Install PerlDen as a desktop application entry in the DE menu.

Usage:
  ./install_perlden_desktop.sh [--user|--system] [--uninstall]

Options:
  --user       Install into ${HOME}/.local/share (default)
  --system     Install into /usr/local/share using sudo
  --uninstall  Remove the desktop entry and installed icon assets

After install:
  Open your desktop environment menu and search for "Perl Den"
EOF
}

for arg in "$@"; do
  case "$arg" in
    --user)      MODE="user"    ;;
    --system)    MODE="system"  ;;
    --uninstall) UNINSTALL=1      ;;
    -h|--help)   usage; exit 0   ;;
    *)
      echo "Unknown option: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

DESKTOP_SOURCE="${ROOT_DIR}/share/applications/${DESKTOP_FILE}"
ICON_SOURCE_PNG="${ROOT_DIR}/share/icons/hb_perl_256.png"
ICON_SOURCE_SVG="${ROOT_DIR}/share/icons/hb_perl.svg"

if [[ ! -f "$DESKTOP_SOURCE" ]]; then
  echo "Missing desktop template: $DESKTOP_SOURCE" >&2
  exit 1
fi
if [[ ! -f "$ICON_SOURCE_PNG" || ! -f "$ICON_SOURCE_SVG" ]]; then
  echo "Missing icon asset(s) under share/icons/" >&2
  exit 1
fi
if [[ ! -x "${ROOT_DIR}/perlden-gui" ]]; then
  chmod +x "${ROOT_DIR}/perlden-gui"
fi

if [[ "$MODE" == "user" ]]; then
  APP_DIR="$USER_APP_DIR"
  ICON_DIR="$USER_ICON_DIR"
else
  APP_DIR="$SYSTEM_APP_DIR"
  ICON_DIR="$SYSTEM_ICON_DIR"
fi

install_file() {
  local src="$1"
  local dst="$2"
  if [[ "$MODE" == "user" ]]; then
    install -Dm644 "$src" "$dst"
  else
    sudo install -Dm644 "$src" "$dst"
  fi
}

remove_file() {
  local dst="$1"
  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ "$MODE" == "user" ]]; then
      rm -f "$dst"
    else
      sudo rm -f "$dst"
    fi
  fi
}

refresh_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -q "$ICON_DIR" >/dev/null 2>&1 || true
  fi
}

if [[ "$UNINSTALL" == 1 ]]; then
  echo "Removing desktop menu entry and icons..."
  remove_file "$APP_DIR/$DESKTOP_FILE"
  remove_file "$ICON_DIR/256x256/apps/${ICON_NAME}.png"
  remove_file "$ICON_DIR/scalable/apps/${ICON_NAME}.svg"
  refresh_caches
  echo "Uninstall complete."
  exit 0
fi

mkdir -p "$APP_DIR" "$ICON_DIR/256x256/apps" "$ICON_DIR/scalable/apps"

tmp_desktop="$(mktemp)"
trap 'rm -f "$tmp_desktop"' EXIT

sed "s|@ROOT_DIR@|${ROOT_DIR}|g" "$DESKTOP_SOURCE" >"$tmp_desktop"

install_file "$tmp_desktop" "$APP_DIR/$DESKTOP_FILE"
install_file "$ICON_SOURCE_PNG" "$ICON_DIR/256x256/apps/${ICON_NAME}.png"
install_file "$ICON_SOURCE_SVG" "$ICON_DIR/scalable/apps/${ICON_NAME}.svg"
refresh_caches

cat <<EOF
Installed desktop entry:
  $APP_DIR/$DESKTOP_FILE

Installed icons:
  $ICON_DIR/256x256/apps/${ICON_NAME}.png
  $ICON_DIR/scalable/apps/${ICON_NAME}.svg

Search your desktop menu for: Perl Den
EOF