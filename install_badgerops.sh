#!/usr/bin/env bash
# ============================================================================
# install_badgerops_command.sh - Install/uninstall BadgerOps launchers
#
# Creates symlinks for badgerops, badgerops-cli, badgerops-tui, and badgerops-gui in either
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
TARGETS=(badgerops badgerops-cli badgerops-tui badgerops-gui)
USER_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"
MODE="user"

usage() {
  cat <<EOF
Install BadgerOps commands as normal shell commands.

Usage:
  ./install_badgerops_command.sh [--user|--system]

Options:
  --user    Install symlinks into ${HOME}/.local/bin (default)
  --system  Install symlinks into /usr/local/bin using sudo

After install:
  badgerops system_info
  badgerops list
  badgerops-cli help
  badgerops-tui --help
  badgerops-gui
EOF
}

case "${1:---user}" in
  --user)
    MODE="user"
    ;;
  --system)
    MODE="system"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: ${1}" >&2
    usage >&2
    exit 2
    ;;
esac

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
  badgerops help
  badgerops system_info
  badgerops port_scanner -- --host 127.0.0.1
  badgerops-cli help
  badgerops-tui --help
  badgerops-gui
EOF
