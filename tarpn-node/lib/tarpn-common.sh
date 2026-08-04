#!/bin/bash
# tarpn-common.sh - shared functions for the tarpn-node installer and tarpnctl.
#
# Sourced, never executed. Everything here is intentionally dependency-free:
# bash, coreutils and systemctl only. No python, no jq, no network at runtime.

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
# These may be overridden by the environment (mostly for testing against a
# staging root) but default to the standard FHS-ish layout described in
# docs/DESIGN.md.

TARPN_PREFIX="${TARPN_PREFIX:-/opt/tarpn}"        # installed program tree
TARPN_ETC="${TARPN_ETC:-/etc/tarpn}"              # operator-owned config
TARPN_STATE="${TARPN_STATE:-/var/lib/tarpn}"      # runtime state, bpq workdir
TARPN_UNIT_DIR="${TARPN_UNIT_DIR:-/etc/systemd/system}"
TARPN_BINDIR="${TARPN_BINDIR:-/usr/local/bin}"
TARPN_DESKTOP_DIR="${TARPN_DESKTOP_DIR:-/usr/share/applications}"

TARPN_MODULE_SRC="${TARPN_MODULE_SRC:-${TARPN_PREFIX}/modules}"
TARPN_MODULE_STATE="${TARPN_STATE}/modules"

TARPN_CONF="${TARPN_CONF:-${TARPN_ETC}/tarpn.conf}"
TARPN_NODE_CONF="${TARPN_NODE_CONF:-${TARPN_ETC}/node.conf}"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _C_RED=$'\033[0;31m'; _C_GRN=$'\033[0;32m'; _C_YEL=$'\033[1;33m'
    _C_BLU=$'\033[0;34m'; _C_DIM=$'\033[2m';    _C_OFF=$'\033[0m'
else
    _C_RED=""; _C_GRN=""; _C_YEL=""; _C_BLU=""; _C_DIM=""; _C_OFF=""
fi

log_info() { printf '%s[ok]%s %s\n'   "$_C_GRN" "$_C_OFF" "$*"; }
log_step() { printf '%s[==]%s %s\n'   "$_C_BLU" "$_C_OFF" "$*"; }
log_warn() { printf '%s[!!]%s %s\n'   "$_C_YEL" "$_C_OFF" "$*" >&2; }
log_err()  { printf '%s[XX]%s %s\n'   "$_C_RED" "$_C_OFF" "$*" >&2; }
log_dim()  { printf '%s     %s%s\n'   "$_C_DIM" "$*" "$_C_OFF"; }

die() { log_err "$*"; exit 1; }

# Honour --dry-run globally. Any command that mutates the system should be
# wrapped in `run` so that --dry-run is genuinely safe rather than
# best-effort.
TARPN_DRY_RUN="${TARPN_DRY_RUN:-false}"

run() {
    if [ "$TARPN_DRY_RUN" = true ]; then
        printf '%s     would run:%s %s\n' "$_C_DIM" "$_C_OFF" "$*"
        return 0
    fi
    "$@"
}

# Write a heredoc/stdin to a file, honouring dry-run.
run_write() {
    local dest="$1"
    if [ "$TARPN_DRY_RUN" = true ]; then
        printf '%s     would write:%s %s\n' "$_C_DIM" "$_C_OFF" "$dest"
        cat >/dev/null
        return 0
    fi
    cat > "$dest"
}

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------

require_root() {
    [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"
}

require_systemd() {
    command -v systemctl >/dev/null 2>&1 || die "systemctl not found; this installer requires systemd"
    [ -d /run/systemd/system ] || log_warn "systemd does not appear to be the running init; unit changes will not take effect until reboot"
}

# Userland architecture, not kernel. A Pi can run a 64-bit kernel with a
# 32-bit userland, and the binary we need is chosen by the userland.
detect_arch() {
    local machine bits
    machine="$(uname -m)"
    bits="$(getconf LONG_BIT 2>/dev/null || echo unknown)"
    case "$machine" in
        armv6l|armv7l)          echo arm32 ;;
        aarch64|arm64)          [ "$bits" = 32 ] && echo arm32 || echo arm64 ;;
        x86_64|amd64)           echo amd64 ;;
        *)                      echo "unknown:$machine" ;;
    esac
}

# ---------------------------------------------------------------------------
# Config files
# ---------------------------------------------------------------------------
# tarpn.conf and node.conf are plain KEY=value files. They are read with a
# parser rather than `source`d, so a stray backtick in a CTEXT string cannot
# execute anything.

# conf_get <file> <key> [default]
conf_get() {
    local file="$1" key="$2" default="${3-}" line value
    [ -f "$file" ] || { printf '%s' "$default"; return 0; }
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | tail -n1)"
    if [ -z "$line" ]; then
        printf '%s' "$default"
        return 0
    fi
    value="${line#*=}"
    # trim surrounding whitespace
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    # strip one layer of matching quotes
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf '%s' "$value"
}

# conf_set <file> <key> <value>  - idempotent in-place upsert
conf_set() {
    local file="$1" key="$2" value="$3"
    if [ "$TARPN_DRY_RUN" = true ]; then
        log_dim "would set ${key}=${value} in ${file}"
        return 0
    fi
    touch "$file"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        # Use a bash replacement rather than sed so that values containing
        # slashes, ampersands etc. survive untouched.
        local tmp; tmp="$(mktemp)"
        local replaced=false line
        while IFS= read -r line || [ -n "$line" ]; do
            if [ "$replaced" = false ] && [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
                printf '%s=%s\n' "$key" "$value" >> "$tmp"
                replaced=true
            else
                printf '%s\n' "$line" >> "$tmp"
            fi
        done < "$file"
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# The account that owns node data and runs the services. Defaults to `pi` when
# it exists (matching stock TARPN), otherwise the invoking sudo user, otherwise
# root. Stored in tarpn.conf once decided so it never silently changes.
resolve_tarpn_user() {
    local u
    u="$(conf_get "$TARPN_CONF" TARPN_USER "")"
    if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
    if id pi >/dev/null 2>&1; then printf 'pi'; return 0; fi
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then printf '%s' "$SUDO_USER"; return 0; fi
    printf 'root'
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------
# A module is a directory containing module.conf plus optional units/, bin/,
# config/, templates/ and hooks/. See docs/DESIGN.md for the contract.

module_dir()  { printf '%s/%s' "$TARPN_MODULE_SRC" "$1"; }
module_conf() { printf '%s/%s/module.conf' "$TARPN_MODULE_SRC" "$1"; }

module_exists() { [ -f "$(module_conf "$1")" ]; }

# module_meta <module> <KEY> [default]
module_meta() { conf_get "$(module_conf "$1")" "$2" "${3-}"; }

# All modules present in the source tree, in dependency-friendly order
# (core first, then alphabetical).
module_list_available() {
    local d name
    [ -d "$TARPN_MODULE_SRC" ] || return 0
    [ -f "$TARPN_MODULE_SRC/core/module.conf" ] && echo core
    for d in "$TARPN_MODULE_SRC"/*/; do
        [ -f "${d}module.conf" ] || continue
        name="$(basename "$d")"
        [ "$name" = core ] && continue
        echo "$name"
    done
}

module_state_file() { printf '%s/%s' "$TARPN_MODULE_STATE" "$1"; }

module_is_installed() { [ -f "$(module_state_file "$1")" ]; }

module_installed_version() {
    local f; f="$(module_state_file "$1")"
    [ -f "$f" ] && conf_get "$f" VERSION "unknown" || printf 'none'
}

module_units() { module_meta "$1" UNITS ""; }

# Units that should be enabled at boot (a subset of UNITS; a .service pulled
# in by a .timer or .path should not itself be enabled).
module_enable_units() {
    local e; e="$(module_meta "$1" ENABLE "")"
    [ -n "$e" ] && printf '%s' "$e" || module_units "$1"
}

# ---------------------------------------------------------------------------
# systemd helpers
# ---------------------------------------------------------------------------

systemd_reload() { run systemctl daemon-reload; }

unit_exists() { [ -f "${TARPN_UNIT_DIR}/$1" ]; }

unit_is_active()  { systemctl is-active  --quiet "$1" 2>/dev/null; }
unit_is_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

# Restart only if the unit is currently running; otherwise leave it alone.
# Used on update so we never start something the operator deliberately stopped.
unit_restart_if_active() {
    if unit_is_active "$1"; then
        run systemctl restart "$1"
    fi
}

# ---------------------------------------------------------------------------
# LinBPQ upstream builds
# ---------------------------------------------------------------------------
# G8BPQ publishes a build per architecture. Verified against the actual files:
#
#   pilinbpq     ELF 32-bit ARM EABI5 (armhf)
#   pilinbpq64   ELF 64-bit ARM aarch64
#   linbpq64     ELF 64-bit x86-64
#   linbpq       ELF 32-bit Intel 80386
#
# so there is nothing to build from source for 64-bit; the right binary just
# has to be picked for the userland. install_linbpq verifies the ELF class of
# whatever it fetches, so a wrong entry here fails loudly rather than leaving
# an unrunnable binary in place.

LINBPQ_UPSTREAM_BASE="${LINBPQ_UPSTREAM_BASE:-https://www.cantab.net/users/john.wiseman/Downloads/Beta}"

# elf_arch_of <file> -> arm32 | arm64 | amd64 | x86 | unknown
#
# Uses file(1) when present and falls back to reading the ELF header, since
# file is not installed on a minimal image. Byte 4 is the class (1=32, 2=64)
# and byte 18 the machine (0x28 ARM, 0xB7 aarch64, 0x3E x86-64, 0x03 i386).
elf_arch_of() {
    local f="$1" desc klass machine
    if command -v file >/dev/null 2>&1; then
        desc="$(file -b "$f" 2>/dev/null || true)"
        case "$desc" in
            *"ARM aarch64"*) printf 'arm64'; return 0 ;;
            *32-bit*ARM*)    printf 'arm32'; return 0 ;;
            *x86-64*)        printf 'amd64'; return 0 ;;
            *80386*)         printf 'x86';   return 0 ;;
        esac
    fi
    klass="$(od -An -tu1 -j4  -N1 "$f" 2>/dev/null | tr -d ' ')"
    machine="$(od -An -tu1 -j18 -N1 "$f" 2>/dev/null | tr -d ' ')"
    case "${klass}:${machine}" in
        1:40)  printf 'arm32' ;;
        2:183) printf 'arm64' ;;
        2:62)  printf 'amd64' ;;
        1:3)   printf 'x86'   ;;
        *)     printf 'unknown' ;;
    esac
}

# QtTermTCP, G8BPQ's terminal program. Same download area as LinBPQ, and the
# build names follow the same pattern. Verified against the published files:
#   piQtTermTCP    ELF 32-bit ARM      piQtTermTCP64  ELF 64-bit ARM aarch64
#   QtTermTCP      ELF 32-bit i386     QtTermTCP64    ELF 64-bit x86-64
qtterm_upstream_name() {
    case "$1" in
        arm32) printf 'piQtTermTCP'   ;;
        arm64) printf 'piQtTermTCP64' ;;
        amd64) printf 'QtTermTCP64'   ;;
        *)     return 1 ;;
    esac
}

qtterm_upstream_url() {
    local name
    name="$(qtterm_upstream_name "$1")" || return 1
    printf '%s/%s' "$LINBPQ_UPSTREAM_BASE" "$name"
}

linbpq_upstream_name() {
    case "$1" in
        arm32) printf 'pilinbpq'   ;;
        arm64) printf 'pilinbpq64' ;;
        amd64) printf 'linbpq64'   ;;
        *)     return 1 ;;
    esac
}

linbpq_upstream_url() {
    local name
    name="$(linbpq_upstream_name "$1")" || return 1
    printf '%s/%s' "$LINBPQ_UPSTREAM_BASE" "$name"
}

# check_linbpq_arch <binary> <host-arch>
#
# Returns non-zero, with an explanation, when the binary cannot run on this
# userland. Uses file(1) when available and falls back to reading the ELF
# header directly, since file is not installed on a minimal image.
check_linbpq_arch() {
    local binary="$1" host="$2" desc="" klass machine

    if command -v file >/dev/null 2>&1; then
        desc="$(file -b "$binary" 2>/dev/null || true)"
    fi

    if [ -z "$desc" ]; then
        # ELF header: byte 4 is the class (1=32-bit, 2=64-bit), bytes 18-19
        # are the machine type (0x28 = ARM, 0xB7 = aarch64, 0x3E = x86-64).
        klass="$(od -An -tu1 -j4 -N1 "$binary" 2>/dev/null | tr -d ' ')"
        machine="$(od -An -tu1 -j18 -N1 "$binary" 2>/dev/null | tr -d ' ')"
        case "${klass}:${machine}" in
            1:40)  desc="ELF 32-bit ARM" ;;
            2:183) desc="ELF 64-bit ARM aarch64" ;;
            2:62)  desc="ELF 64-bit x86-64" ;;
            1:3)   desc="ELF 32-bit Intel 80386" ;;
            *)     return 0 ;;   # unrecognised: do not guess
        esac
    fi

    case "${desc}:${host}" in
        *aarch64*:arm32)
            log_err "linbpq is a 64-bit ARM binary but this userland is 32-bit"
            log_dim "use the ${LINBPQ_UPSTREAM_BASE}/$(linbpq_upstream_name arm32) build"
            return 1 ;;
        *32-bit*ARM*:arm64)
            log_err "linbpq is a 32-bit ARM binary but this userland is 64-bit"
            log_dim "use the ${LINBPQ_UPSTREAM_BASE}/$(linbpq_upstream_name arm64) build"
            return 1 ;;
        *ARM*:amd64|*x86-64*:arm32|*x86-64*:arm64|*Intel*:arm32|*Intel*:arm64)
            log_err "linbpq (${desc}) does not match this ${host} userland"
            return 1 ;;
    esac
    return 0
}

# install_linbpq <staged> <dest> <arch> <user> <group>
#
# Moves a freshly fetched binary into place, but only once it is confirmed to
# be an executable of the right architecture. A truncated download or an HTML
# error page must never replace a working node engine.
install_linbpq() {
    local staged="$1" dest="$2" arch="$3" user="$4" group="$5"

    [ "$TARPN_DRY_RUN" = true ] && return 0

    if ! head -c4 "$staged" | grep -q $'\x7fELF'; then
        rm -f "$staged"
        log_err "downloaded linbpq is not an ELF binary"
        return 1
    fi
    if ! check_linbpq_arch "$staged" "$arch"; then
        rm -f "$staged"
        log_err "refusing to install a linbpq that cannot run on this system"
        return 1
    fi

    chmod 0755 "$staged"
    chown "$user:$group" "$staged" 2>/dev/null || true
    mv "$staged" "$dest"
    log_info "Installed ${dest}"
}

# ---------------------------------------------------------------------------
# Binary distribution
# ---------------------------------------------------------------------------

# install_release_binary <name> <dest>
#
# Resolve a binary for this host, in priority order:
#   1. <name>_SOURCE in tarpn.conf  - a local path or URL (operator override)
#   2. bin/<name>.linux-<arch> next to the running installer, i.e. dropped
#      into a checkout before running install.sh
#   3. the same path in the staged tree, so a binary provided that way is
#      still there for `tarpnctl update` later
#   4. the configured release channel
#
# 2 and 3 are what make a fully offline install possible: build on a
# workstation, copy the checkout with binaries in bin/, and never touch the
# network. That matters for a network whose whole premise is not having one.
#
# Downloads to a temp file and only moves it into place on success, so a
# failed or truncated download never replaces a working binary.
install_release_binary() {
    local name="$1" dest="$2"
    local arch override src tmp fallback_url=""

    arch="$(detect_arch)"
    case "$arch" in
        unknown:*) die "unsupported architecture: ${arch#unknown:}" ;;
    esac

    # 1. explicit override, e.g. SEND_ROUTES_VIA_CQ_SOURCE=/home/pi/build/foo
    local key
    key="$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')_SOURCE"
    override="$(conf_get "$TARPN_CONF" "$key" "")"

    if [ -n "$override" ]; then
        src="$override"
    elif [ -f "${TARPN_SELF_DIR:-}/bin/${name}.linux-${arch}" ]; then
        src="${TARPN_SELF_DIR}/bin/${name}.linux-${arch}"
    elif [ -f "${TARPN_PREFIX}/bin/${name}.linux-${arch}" ]; then
        src="${TARPN_PREFIX}/bin/${name}.linux-${arch}"
    else
        local base version
        # The environment wins over tarpn.conf so a first-time install can be
        # pointed at a specific release. tarpn.conf does not exist until the
        # core module has run, by which time later modules would already be
        # fetching from whatever the shipped default says.
        base="${TARPN_RELEASE_BASE_URL:-$(conf_get "$TARPN_CONF" RELEASE_BASE_URL "https://tarpn-terminal.s3.us-east-1.amazonaws.com")}"
        version="${TARPN_RELEASE_VERSION:-$(conf_get "$TARPN_CONF" RELEASE_VERSION latest)}"
        src="${base}/${version}/${name}.linux-${arch}"

        # tarpn-chat was published as "tarpn-chat-<arch>" before the naming
        # was made consistent. Releases now carry both, but a bucket that has
        # not been rebuilt since only has the old name.
        fallback_url="${base}/${version}/${name}-${arch}"
    fi

    if [ "$TARPN_DRY_RUN" = true ]; then
        log_dim "would install ${name} (${arch}) from ${src} to ${dest}"
        return 0
    fi

    log_step "Installing ${name} (${arch})"
    tmp="$(mktemp "${dest}.XXXXXX")"

    case "$src" in
        http://*|https://*)
            # curl's own diagnostics are suppressed: a 404 on the first
            # attempt is expected when falling back, and our messages below
            # say more than "error 22" does.
            if ! curl -fsL "$src" -o "$tmp" 2>/dev/null; then
                if [ -n "${fallback_url:-}" ] && curl -fsL "$fallback_url" -o "$tmp" 2>/dev/null; then
                    log_dim "using the legacy release name $(basename "$fallback_url")"
                else
                    rm -f "$tmp"
                    log_err "could not download ${name} for ${arch}"
                    log_dim "tried ${src}"
                    [ -n "${fallback_url:-}" ] && log_dim "and  ${fallback_url}"
                    log_dim "if this architecture has not been published yet, build it and set"
                    log_dim "${key} in ${TARPN_CONF} to the local path"
                    return 1
                fi
            fi
            ;;
        *)
            if [ ! -f "$src" ]; then
                rm -f "$tmp"
                log_err "${key} points at a file that does not exist: ${src}"
                return 1
            fi
            cp "$src" "$tmp"
            ;;
    esac

    # A 404 page saved to disk is still a successful curl to an S3 bucket that
    # returns HTML. Reject anything that is not an executable image.
    if ! head -c4 "$tmp" | grep -q $'\x7fELF'; then
        rm -f "$tmp"
        log_err "${name} downloaded from ${src} is not an ELF binary"
        log_dim "the release may not exist for ${arch}"
        return 1
    fi

    chmod 0755 "$tmp"
    mv "$tmp" "$dest"
    log_info "Installed ${dest}"
}

# ---------------------------------------------------------------------------
# Callsign helpers
# ---------------------------------------------------------------------------

# Amateur callsign with optional SSID, e.g. N0CALL-2. Deliberately permissive
# about prefix shape but strict about overall structure: a prefix, a digit,
# then a suffix of up to four letters. Four is needed for the conventional
# N0CALL placeholder as well as for the longer suffixes some prefixes issue.
# SSID is 0-15, as AX.25 allows.
is_valid_call() {
    printf '%s' "$1" | grep -qiE '^[A-Z0-9]{1,3}[0-9][A-Z]{1,4}(-([0-9]|1[0-5]))?$'
}

call_base() { printf '%s' "${1%%-*}"; }

call_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
call_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Chat node alias, derived the way the legacy scripts did it: 'z' plus the
# last three characters of the base call plus the zero-padded SSID, so
# N0CALL-9 becomes zall09. Other nodes on the network expect this shape, so
# both the bpq32.cfg generator and the tarpn-chat module use this one
# implementation rather than each inventing their own.
chat_alias() {
    local call="$1" base ssid
    base="$(call_lower "$(call_base "$call")")"
    ssid="${call##*-}"
    [ "$ssid" = "$call" ] && ssid=0
    printf 'z%s%02d' "${base: -3}" "$((10#${ssid:-0}))"
}
