#!/bin/bash
# install.sh - bootstrap a modular TARPN node.
#
# This is the only script that needs to run to get started. Everything after
# it is done with tarpnctl and systemctl:
#
#   sudo ./install.sh                     core + linbpq + routes + tarpn-mon
#   sudo ./install.sh --modules core      install just the base layout
#   sudo ./install.sh --all               install every available module
#                                         (adds tarpn-chat)
#   sudo ./install.sh --dry-run           show what would happen
#   sudo ./install.sh --uninstall         remove units and /opt/tarpn
#
# It does not reboot, does not run apt, does not download shell scripts at
# runtime, and does not modify any existing TARPN installation. If a legacy
# TARPN install is present it will say so and stop unless --alongside is
# given, because both stacks driving the same radios at once will not work.

set -euo pipefail

TARPN_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TARPN_SELF_DIR

# Run out of the source tree during install; the staged copy takes over after.
. "${TARPN_SELF_DIR}/lib/tarpn-common.sh"

# tarpn-chat is deliberately not in the default set: it takes chat away from
# LinBPQ, and it needs LinBPQ 6.0.25+ for NETROMPORT. Opt in with
# `--all` or `--modules ...,tarpn-chat`.
DEFAULT_MODULES="core linbpq routes tarpn-mon"
SELECTED=""
INSTALL_ALL=false
UNINSTALL=false
PURGE=false
ALONGSIDE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --modules)   SELECTED="$(printf '%s' "$2" | tr ',' ' ')"; shift 2 ;;
        --all)       INSTALL_ALL=true; shift ;;
        --dry-run)   TARPN_DRY_RUN=true; shift ;;
        --uninstall) UNINSTALL=true; shift ;;
        --purge)     UNINSTALL=true; PURGE=true; shift ;;
        --alongside) ALONGSIDE=true; shift ;;
        --prefix)    TARPN_PREFIX="$2"; shift 2 ;;
        --help|-h)   sed -n '2,20p' "$0"; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
done

# Re-derive paths that depend on the prefix, in case --prefix moved it.
TARPN_MODULE_SRC="${TARPN_PREFIX}/modules"

banner() {
    printf '\n%s========================================%s\n' "$_C_BLU" "$_C_OFF"
    printf '%s  TARPN node installer%s\n' "$_C_BLU" "$_C_OFF"
    printf '%s========================================%s\n\n' "$_C_BLU" "$_C_OFF"
}

# ---------------------------------------------------------------------------
# Legacy install detection
# ---------------------------------------------------------------------------
# The whole point of this installer is to not be the legacy one. Running both
# means two things starting linbpq, two things broadcasting TARPNstat, and the
# legacy update.sh overwriting scripts underneath us.

check_legacy() {
    local found=()
    local u
    for u in tarpn.service home.service tarpn_mon.service statusmonitor.service \
             rx_tarpnstat.service neighbor_port_association.service; do
        if [ -f "/etc/systemd/system/${u}" ]; then found+=("$u"); fi
    done

    [ ${#found[@]} -eq 0 ] && return 0

    log_warn "an existing TARPN installation was detected:"
    for u in "${found[@]}"; do log_dim "$u"; done
    echo
    if [ "$ALONGSIDE" = true ]; then
        log_warn "--alongside given; continuing without touching the legacy stack"
        log_dim "disable it before starting this node:"
        log_dim "  sudo systemctl disable --now ${found[*]}"
        return 0
    fi
    log_err "refusing to install on top of a running legacy TARPN stack"
    echo
    log_dim "Both stacks would drive the same radios and broadcast the same stats."
    log_dim "Either disable the legacy services first:"
    log_dim "  sudo systemctl disable --now ${found[*]}"
    log_dim "or re-run with --alongside to install without starting anything."
    exit 1
}

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------

stage_tree() {
    log_step "Staging ${TARPN_PREFIX}"

    run install -d -m 0755 "$TARPN_PREFIX"

    local d
    for d in lib bin modules docs; do
        [ -d "${TARPN_SELF_DIR}/${d}" ] || continue
        if [ "$TARPN_DRY_RUN" = true ]; then
            log_dim "would copy ${d}/ to ${TARPN_PREFIX}/${d}/"
            continue
        fi
        # Replace the staged copy wholesale so that removed files in a new
        # release do not linger, but never touch /etc or /var here.
        rm -rf "${TARPN_PREFIX:?}/${d}"
        cp -R "${TARPN_SELF_DIR}/${d}" "${TARPN_PREFIX}/${d}"
    done

    if [ "$TARPN_DRY_RUN" != true ]; then
        chmod 0755 "${TARPN_PREFIX}/bin/"* 2>/dev/null || true
        find "${TARPN_PREFIX}/modules" -type d -name bin -exec chmod -R 0755 {} + 2>/dev/null || true
        find "${TARPN_PREFIX}/modules" -type d -name hooks -exec chmod -R 0755 {} + 2>/dev/null || true
    fi

    run ln -sfn "${TARPN_PREFIX}/bin/tarpnctl" "${TARPN_BINDIR}/tarpnctl"
    log_info "tarpnctl available at ${TARPN_BINDIR}/tarpnctl"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    require_root
    log_step "Uninstalling"

    # Load the module library from wherever the tree currently lives.
    if [ -f "${TARPN_PREFIX}/lib/tarpn-modules.sh" ]; then
        . "${TARPN_PREFIX}/lib/tarpn-modules.sh"
    else
        . "${TARPN_SELF_DIR}/lib/tarpn-modules.sh"
    fi

    if unit_is_active tarpn.target; then run systemctl stop tarpn.target; fi
    if unit_is_enabled tarpn.target; then run systemctl disable tarpn.target; fi

    local name
    for name in $(module_list_available); do
        module_is_installed "$name" || continue
        [ "$name" = core ] && continue
        module_remove "$name" || true
    done

    # core last, and by hand, since module_remove refuses to remove it.
    local unit
    for unit in $(module_units core); do
        if unit_is_enabled "$unit"; then run systemctl disable "$unit"; fi
        run rm -f "${TARPN_UNIT_DIR}/${unit}"
    done
    systemd_reload

    run rm -f "${TARPN_BINDIR}/tarpnctl"
    run rm -rf "${TARPN_PREFIX}"

    if [ "$PURGE" = true ]; then
        log_warn "purging configuration and state"
        run rm -rf "$TARPN_ETC" "$TARPN_STATE"
    else
        log_info "kept ${TARPN_ETC} and ${TARPN_STATE}"
        log_dim "use --purge to remove those too"
    fi

    log_info "Uninstalled"
    exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

banner

[ "$UNINSTALL" = true ] && do_uninstall

# A dry run touches nothing, so let anyone preview it.
if [ "$TARPN_DRY_RUN" = true ]; then
    log_warn "dry run - no changes will be made"
    command -v systemctl >/dev/null 2>&1 || log_warn "systemctl not found; unit handling is only simulated"
else
    require_root
    require_systemd
fi

ARCH="$(detect_arch)"
case "$ARCH" in
    unknown:*) die "unsupported architecture: ${ARCH#unknown:}" ;;
esac
log_info "Architecture: ${ARCH}"

check_legacy
stage_tree

# From here on, work against the staged tree so that what runs during install
# is exactly what will run later.
TARPN_MODULE_SRC="${TARPN_PREFIX}/modules"
if [ "$TARPN_DRY_RUN" = true ]; then
    . "${TARPN_SELF_DIR}/lib/tarpn-modules.sh"
    TARPN_MODULE_SRC="${TARPN_SELF_DIR}/modules"
else
    . "${TARPN_PREFIX}/lib/tarpn-modules.sh"
fi

if [ "$INSTALL_ALL" = true ]; then
    SELECTED="$(module_list_available | tr '\n' ' ')"
elif [ -z "$SELECTED" ]; then
    # On a re-run, update whatever is actually installed rather than reverting
    # to the default set. Otherwise a module the operator added later - qtterm,
    # node-commands, tarpn-chat - silently stops being updated by the very
    # command that is supposed to update everything.
    for _m in $(module_list_available); do
        module_is_installed "$_m" && SELECTED="${SELECTED} ${_m}"
    done
    if [ -n "$SELECTED" ]; then
        log_info "Updating the modules already installed"
    else
        SELECTED="$DEFAULT_MODULES"
    fi
fi

log_info "Modules: ${SELECTED}"
echo

# shellcheck disable=SC2086
MODULES="$(resolve_module_list $SELECTED)"

# Install everything selected, then report. A module that cannot install -
# usually because its binary is not published for this architecture yet -
# should not prevent the rest of the node being set up.
INSTALLED=""
FAILED=""
for m in $MODULES; do
    if module_install "$m"; then
        INSTALLED="${INSTALLED} ${m}"
    else
        FAILED="${FAILED} ${m}"
    fi
done

systemd_reload

for m in $INSTALLED; do
    module_enable "$m"
done

# Replacing a binary on disk does not restart whatever is running the old one,
# so without this an update appears to succeed while the node carries on with
# the previous version. Only restarts services that were already up: a fresh
# install starts nothing, and a service the operator deliberately stopped
# stays stopped.
for m in $INSTALLED; do
    for u in $(module_enable_units "$m"); do
        if unit_is_active "$u"; then
            log_dim "restarting ${u}"
            unit_restart_if_active "$u"
        fi
    done
done

# ---------------------------------------------------------------------------

echo
if [ -n "$FAILED" ]; then
    printf '%s========================================%s\n' "$_C_YEL" "$_C_OFF"
    printf '%s  Partly installed%s\n' "$_C_YEL" "$_C_OFF"
    printf '%s========================================%s\n\n' "$_C_YEL" "$_C_OFF"
    log_info "installed:${INSTALLED}"
    log_err  "not installed:${FAILED}"
    echo
    log_dim "The usual cause is that no binary is published for $(detect_arch) yet."
    log_dim "Build them elsewhere and either drop them in bin/ as"
    log_dim "<component>.linux-$(detect_arch) and re-run this script, or point"
    log_dim "<COMPONENT>_SOURCE in ${TARPN_CONF} at a local file and run:"
    log_dim "  sudo tarpnctl update <module>"
    echo
    log_dim "Everything that did install is set up and usable."
    echo
else
    printf '%s========================================%s\n' "$_C_GRN" "$_C_OFF"
    printf '%s  Installed%s\n' "$_C_GRN" "$_C_OFF"
    printf '%s========================================%s\n\n' "$_C_GRN" "$_C_OFF"
fi

if [ "$TARPN_DRY_RUN" = true ]; then
    log_info "dry run - nothing was changed"
    exit 0
fi

cat <<EOF
Next steps:

  1. Configure the node:
       sudo tarpnctl config

     Converting an existing TARPN node instead:
       sudo tarpnctl import-node-ini /home/pi/node.ini

  2. Bring it up:
       sudo tarpnctl start

  3. Check on it:
       tarpnctl status
       tarpnctl logs -f

Modules are independent. To see what is available:
       tarpnctl list
       sudo tarpnctl install <module>
       sudo tarpnctl remove  <module>
EOF

# Non-zero when anything failed, so this is detectable from a script.
[ -z "$FAILED" ] || exit 1
