#!/usr/bin/env bash
# ============================================================================
# install_perlden_command.sh - Install/uninstall PerlDen launchers
#
# Creates symlinks for perlden, perlden-cli, perlden-tui, and perlden-gui in either
# ~/.local/bin (user mode, default) or /usr/local/bin (system mode).
# Pass --uninstall to remove them.
# ============================================================================
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
TARGETS=(perlden perlden-cli perlden-tui perlden-gui)
GUI_TARGETS=(perlden-gui)
USER_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"
MODE="user"
NO_GUI=0
UNINSTALL=0

usage() {
  cat <<EOF
Install PerlDen commands as normal shell commands.

Usage:
  ./install_perlden_command.sh [--user|--system] [--no-gui] [--uninstall]

Options:
  --user       Install symlinks into ${HOME}/.local/bin (default)
  --system     Install symlinks into /usr/local/bin using sudo
  --no-gui     Skip GTK/GUI launcher (perlden-gui) and system GUI dependencies
  --uninstall  Remove installed symlinks (will prompt before removing config)

After install:
  perlden system_info
  perlden list
  perlden-cli help
  perlden-tui --help
  perlden-gui
EOF
}

# Parse all arguments
for arg in "$@"; do
  case "$arg" in
    --user)      MODE="user"    ;;
    --system)    MODE="system"  ;;
    --no-gui)    NO_GUI=1       ;;
    --uninstall) UNINSTALL=1   ;;
    -h|--help)   usage; exit 0  ;;
    *)
      echo "Unknown option: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Remove GUI targets when --no-gui is set
if [[ "$NO_GUI" == 1 ]]; then
  TARGETS=($(printf '%s\n' "${TARGETS[@]}" | grep -v 'gui'))
fi

# ---- Uninstall path -------------------------------------------------------
if [[ "$UNINSTALL" == 1 ]]; then
  INSTALL_DIR="$([[ $MODE == system ]] && echo "$SYSTEM_BIN" || echo "$USER_BIN")"
  echo "Removing symlinks from ${INSTALL_DIR}..."
  for target in perlden perlden-cli perlden-tui perlden-gui; do
    link="${INSTALL_DIR}/${target}"
    if [[ -L "$link" ]]; then
      rm -f "$link"
      echo "  Removed: $link"
    fi
  done

  CONFIG_DIR="${HOME}/.config/perlden"
  if [[ -d "$CONFIG_DIR" ]]; then
    read -r -p "Remove config directory ${CONFIG_DIR}? [y/N] " answer
    if [[ "${answer,,}" == y ]]; then
      rm -rf "$CONFIG_DIR"
      echo "  Removed: $CONFIG_DIR"
    else
      echo "  Kept: $CONFIG_DIR"
    fi
  fi
  echo "Uninstall complete."
  exit 0
fi

# ---- Install path ---------------------------------------------------------
for target in "${TARGETS[@]}"; do
  src="${ROOT_DIR}/${target}"
  if [[ ! -f "$src" ]]; then
    echo "Missing launcher: $src" >&2
    exit 1
  fi
  if [[ ! -x "$src" ]]; then
    chmod +x "$src"
  fi
done

if [[ "$MODE" == "user" ]]; then
  mkdir -p "$USER_BIN"
  for target in "${TARGETS[@]}"; do
    src="${ROOT_DIR}/${target}"
    ln -snf "$src" "$USER_BIN/$target"
    echo "Installed: $USER_BIN/$target -> $src"
  done

  case ":${PATH}:" in
    *":${USER_BIN}:"*)
      echo "${USER_BIN} is already on PATH."
      ;;
    *)
      shell_name="$(basename "${SHELL:-bash}")"
      rc_file="${HOME}/.bashrc"
      [[ "$shell_name" == "zsh" ]] && rc_file="${HOME}/.zshrc"
      echo
      echo "Add this line to ${rc_file}:"
      echo "  export PATH=\"${USER_BIN}:\$PATH\""
      echo
      echo "Then run:"
      echo "  source ${rc_file}"
      ;;
  esac
else
  for target in "${TARGETS[@]}"; do
    src="${ROOT_DIR}/${target}"
    sudo ln -snf "$src" "$SYSTEM_BIN/$target"
    echo "Installed: $SYSTEM_BIN/$target -> $src"
  done
fi

cat <<EOF

Commands ready:
  perlden help
  perlden system_info
  perlden port_scanner -- --host 127.0.0.1
  perlden-cli help
  perlden-tui --help
  perlden-gui
EOF
