#!/usr/bin/env bash
# ============================================================================
# _perlden_env.sh - Project environment bootstrap (root copy)
#
# Sourced by the top-level launcher scripts (perlden, perlden-cli, perlden-tui,
# perlden-gui).  Sets PATH, PERL5LIB, and share-directory variables, and
# provides helper functions for dependency checking.
# ============================================================================
set -euo pipefail

PERLDEN_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PERLDEN_ROOT_DIR
export PERLDEN_SHARE_DIR="${PERLDEN_ROOT_DIR}/share"
export PERLDEN_SCRIPTS_DIR="${PERLDEN_ROOT_DIR}/scripts"

# Preload project paths
export PATH="${PERLDEN_ROOT_DIR}/bin:${PATH}"
if [[ -n "${PERL5LIB:-}" ]]; then
  export PERL5LIB="${PERLDEN_ROOT_DIR}/lib:${PERL5LIB}"
else
  export PERL5LIB="${PERLDEN_ROOT_DIR}/lib"
fi

# Ensure config dir exists
mkdir -p "${HOME}/.config/perlden"

# ── Colour helpers (disable if not a terminal) ──
if [[ -t 2 ]]; then
  _C_RED=$'\033[1;31m'  _C_YEL=$'\033[1;33m'  _C_GRN=$'\033[1;32m'
  _C_CYN=$'\033[1;36m'  _C_DIM=$'\033[0;37m'   _C_RST=$'\033[0m'
else
  _C_RED='' _C_YEL='' _C_GRN='' _C_CYN='' _C_DIM='' _C_RST=''
fi

_bo_info()  { echo "${_C_CYN}[hb]${_C_RST} $*" >&2; }
_bo_ok()    { echo "${_C_GRN}  ✓${_C_RST} $*" >&2; }
_bo_warn()  { echo "${_C_YEL}  ⚠${_C_RST} $*" >&2; }
_bo_fail()  { echo "${_C_RED}  ✗${_C_RST} $*" >&2; }

# ── Basic helpers ──

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    _bo_fail "Missing required command: ${cmd}"
    return 1
  fi
}

check_perl_module() {
  local module="$1"
  perl -I"${PERLDEN_ROOT_DIR}/lib" -M"${module}" -e 1 >/dev/null 2>&1
}

# ── GUI dependency check (Perl modules) ──

check_gui_deps() {
  local missing=()

  for mod in Glib Glib::Object::Introspection Gtk3 Gtk3::SourceView; do
    if ! check_perl_module "$mod"; then
      missing+=("$mod")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    _bo_fail "Missing GUI Perl modules: ${missing[*]}"
    echo "       Install with: cpanm --installdeps \"${PERLDEN_ROOT_DIR}\"" >&2
    return 1
  fi
}

# ── Full pre-flight check for the GUI ──

preflight_gui() {
  local errors=0
  _bo_info "Pre-flight check …"

  # 1. Perl
  if command -v perl >/dev/null 2>&1; then
    local pv
    pv="$(perl -e 'print $^V')"
    _bo_ok "perl ${pv}"
  else
    _bo_fail "perl not found"; (( errors++ ))
  fi

  # 2. Display server
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    _bo_fail "No display server (DISPLAY / WAYLAND_DISPLAY not set)"
    (( errors++ ))
  else
    _bo_ok "Display: ${DISPLAY:-}${WAYLAND_DISPLAY:+wayland:$WAYLAND_DISPLAY}"
  fi

  # 3. UTF-8 locale
  if locale 2>/dev/null | grep -qi 'utf-\?8'; then
    _bo_ok "Locale is UTF-8"
  else
    _bo_warn "Locale may not be UTF-8 — Unicode rendering could break"
  fi

  # 4. GTK / GUI Perl modules
  local gui_mods=(Glib Glib::Object::Introspection Gtk3 Gtk3::SourceView)
  local gui_missing=()
  for mod in "${gui_mods[@]}"; do
    if check_perl_module "$mod"; then
      _bo_ok "Perl module: $mod"
    else
      _bo_fail "Perl module: $mod — NOT FOUND"
      gui_missing+=("$mod")
      (( errors++ ))
    fi
  done

  # 5. VTE terminal (optional but important)
  if perl -I"${PERLDEN_ROOT_DIR}/lib" -e '
      use Glib::Object::Introspection;
      Glib::Object::Introspection->setup(
          basename => "Vte", version => "2.91", package => "Vte",
      );' >/dev/null 2>&1; then
    _bo_ok "VTE terminal widget"
  else
    _bo_warn "VTE not available — embedded terminal will use fallback"
  fi

  # 6. Sysadmin Perl modules
  local sa_mods=(Proc::ProcessTable Net::DNS IO::Socket::SSL Text::Diff
                 YAML::XS JSON::MaybeXS File::HomeDir Perl::Tidy Perl::Critic)
  local sa_missing=()
  for mod in "${sa_mods[@]}"; do
    if check_perl_module "$mod"; then
      _bo_ok "Perl module: $mod"
    else
      _bo_warn "Perl module: $mod — not installed (some features unavailable)"
      sa_missing+=("$mod")
    fi
  done

  # 7. Fonts — check for a good sans-serif and emoji coverage
  if command -v fc-match >/dev/null 2>&1; then
    local sans_font emoji_font
    sans_font="$(fc-match 'sans-serif' family 2>/dev/null | head -1)"
    emoji_font="$(fc-match 'emoji' family 2>/dev/null | head -1)"

    if [[ -n "$sans_font" ]]; then
      _bo_ok "Sans-serif font: ${sans_font}"
    else
      _bo_warn "No sans-serif font found — UI text may look broken"
    fi

    # Check specifically for the fonts we use in Pango markup
    for fname in "Adwaita Sans" "DejaVu Sans" "Noto Sans"; do
      if fc-list : family | grep -qi "^${fname}$"; then
        _bo_ok "Font available: ${fname}"
        break  # one good sans is enough
      fi
    done

    if [[ -n "$emoji_font" ]] && echo "$emoji_font" | grep -qi "emoji"; then
      _bo_ok "Emoji font: ${emoji_font}"
    else
      _bo_warn "No emoji font found — install noto-fonts-emoji for best results"
    fi
  else
    _bo_warn "fontconfig (fc-match) not found — cannot verify fonts"
  fi

  # 8. Required system commands
  local req_cmds=(bash hostname uname df ps ip ss ping systemctl journalctl openssl pod2text)
  local cmd_missing=()
  for cmd in "${req_cmds[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _bo_ok "Command: $cmd"
    else
      _bo_warn "Command: $cmd — not found (some scripts may fail)"
      cmd_missing+=("$cmd")
    fi
  done

  # 9. Theme CSS exists
  local theme_dir="${PERLDEN_ROOT_DIR}/share/themes"
  if [[ -f "${theme_dir}/dark.css" && -f "${theme_dir}/light.css" ]]; then
    _bo_ok "Theme CSS files present"
  else
    _bo_fail "Theme CSS missing from ${theme_dir}"
    (( errors++ ))
  fi

  # 10. Share directory structure
  for subdir in icons templates tutorials themes; do
    if [[ -d "${PERLDEN_ROOT_DIR}/share/${subdir}" ]]; then
      _bo_ok "share/${subdir}/ exists"
    else
      _bo_warn "share/${subdir}/ missing"
    fi
  done

  # 11. Font cache freshness (warn if stale)
  if command -v fc-cache >/dev/null 2>&1; then
    local cache_dir="${HOME}/.cache/fontconfig"
    if [[ -d "$cache_dir" ]]; then
      local cache_age
      cache_age=$(find "$cache_dir" -maxdepth 1 -name '*.cache-*' -mtime +30 -print -quit 2>/dev/null || true)
      if [[ -n "$cache_age" ]]; then
        _bo_warn "Font cache is stale (>30 days) — running fc-cache -f"
        fc-cache -f >/dev/null 2>&1 || true
        _bo_ok "Font cache refreshed"
      fi
    fi
  fi

  # Summary
  echo "" >&2
  if (( errors > 0 )); then
    _bo_fail "${errors} critical issue(s) found — the IDE may not start correctly"
    if (( ${#gui_missing[@]} > 0 )); then
      echo "       Install Perl deps: cpanm --installdeps \"${PERLDEN_ROOT_DIR}\"" >&2
    fi
    return 1
  else
    _bo_ok "All checks passed — launching PerlDen IDE"
    echo "" >&2
    return 0
  fi
}
