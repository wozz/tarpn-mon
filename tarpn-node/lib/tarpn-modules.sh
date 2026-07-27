#!/bin/bash
# tarpn-modules.sh - install/remove/enable logic shared by install.sh and
# tarpnctl. Sourced after tarpn-common.sh.
#
# A module is a directory under /opt/tarpn/modules containing:
#
#   module.conf      required. NAME, SUMMARY, VERSION, REQUIRES, UNITS,
#                    ENABLE, REQUIRED, BINARY, PROVIDES
#   units/           systemd units, copied to /etc/systemd/system with
#                    @PLACEHOLDER@ substitution
#   bin/             executables, left in place and referenced by the units
#   config/          example/default config, seeded but never overwritten
#   templates/       data files used at runtime
#   hooks/postinstall, hooks/preremove
#                    optional bash scripts, sourced with the library loaded
#
# The whole modules/ tree is staged on disk regardless of what is activated,
# so enabling a module later needs neither the network nor the source tree.

# ---------------------------------------------------------------------------
# Unit files
# ---------------------------------------------------------------------------

# Units are templated so that TARPN_USER and BPQ_HOME stay configurable
# without asking the operator to hand-edit unit files (which would then be
# clobbered on update, or need a drop-in to survive).
unit_substitute() {
    local src="$1" dest="$2" user group bpq_home
    user="$(resolve_tarpn_user)"
    group="$(id -gn "$user" 2>/dev/null || echo "$user")"
    bpq_home="$(conf_get "$TARPN_CONF" BPQ_HOME /var/lib/tarpn/bpq)"

    if [ "$TARPN_DRY_RUN" = true ]; then
        log_dim "would install unit $(basename "$dest")"
        return 0
    fi

    sed -e "s|@TARPN_USER@|${user}|g" \
        -e "s|@TARPN_GROUP@|${group}|g" \
        -e "s|@TARPN_PREFIX@|${TARPN_PREFIX}|g" \
        -e "s|@TARPN_ETC@|${TARPN_ETC}|g" \
        -e "s|@TARPN_STATE@|${TARPN_STATE}|g" \
        -e "s|@BPQ_HOME@|${bpq_home}|g" \
        "$src" > "$dest"
    chmod 0644 "$dest"
}

module_install_units() {
    local name="$1" dir unit
    dir="$(module_dir "$name")"
    [ -d "${dir}/units" ] || return 0

    for unit in $(module_units "$name"); do
        [ -f "${dir}/units/${unit}" ] || die "module ${name} declares unit ${unit} but ${dir}/units/${unit} does not exist"
        unit_substitute "${dir}/units/${unit}" "${TARPN_UNIT_DIR}/${unit}"
    done
}

module_remove_units() {
    local name="$1" unit
    for unit in $(module_units "$name"); do
        run rm -f "${TARPN_UNIT_DIR}/${unit}"
    done
}

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------

module_run_hook() {
    local name="$1" hook="$2" path rc=0
    path="$(module_dir "$name")/hooks/${hook}"
    [ -f "$path" ] || return 0

    # Sourced, so hooks inherit the library, the resolved layout and
    # TARPN_DRY_RUN without re-deriving any of it - but sourced inside a
    # subshell.
    #
    # Without the subshell, a hook's own `set -e` applies to the installer's
    # shell, so one failing command inside a hook terminates the whole install
    # silently, halfway through, with no error and no indication of which
    # module stopped it. The subshell contains both the shell options and the
    # exit, leaving a status we can report.
    # shellcheck source=/dev/null
    ( . "$path" ) || rc=$?

    if [ "$rc" -ne 0 ]; then
        log_err "module ${name}: ${hook} hook failed (exit ${rc})"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

# Emit <name> preceded by anything it requires, depth first. Cycles are
# broken by _dep_seen so a bad manifest cannot hang the installer.
_dep_seen=""
module_with_deps() {
    local name="$1" dep
    case " $_dep_seen " in *" $name "*) return 0 ;; esac
    _dep_seen="$_dep_seen $name"

    module_exists "$name" || die "no such module: ${name}"
    for dep in $(module_meta "$name" REQUIRES ""); do
        module_with_deps "$dep"
    done
    echo "$name"
}

resolve_module_list() {
    _dep_seen=""
    local n
    for n in "$@"; do module_with_deps "$n"; done
}

# ---------------------------------------------------------------------------
# Install / remove
# ---------------------------------------------------------------------------

module_install() {
    local name="$1" version
    module_exists "$name" || die "no such module: ${name}"
    version="$(module_meta "$name" VERSION 1)"

    log_step "Installing module: ${name} ($(module_meta "$name" SUMMARY ""))"

    module_install_units "$name"

    # A module whose postinstall failed is not installed. Recording it as
    # such would let a later `tarpnctl update` skip straight past the
    # problem, and would let other modules detect it as present.
    if ! module_run_hook "$name" postinstall; then
        module_remove_units "$name"
        die "module ${name} failed to install"
    fi

    if [ "$TARPN_DRY_RUN" != true ]; then
        install -d -m 0755 "$TARPN_MODULE_STATE"
        {
            printf 'NAME=%s\n' "$name"
            printf 'VERSION=%s\n' "$version"
            printf 'INSTALLED=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$(module_state_file "$name")"
    fi
}

module_remove() {
    local name="$1" unit
    module_is_installed "$name" || { log_warn "module ${name} is not installed"; return 0; }

    if [ "$(module_meta "$name" REQUIRED false)" = true ]; then
        die "module ${name} is required and cannot be removed"
    fi

    log_step "Removing module: ${name}"

    for unit in $(module_units "$name"); do
        if unit_is_active "$unit";  then run systemctl stop "$unit"; fi
        if unit_is_enabled "$unit"; then run systemctl disable "$unit"; fi
    done

    module_run_hook "$name" preremove
    module_remove_units "$name"
    systemd_reload

    run rm -f "$(module_state_file "$name")"

    # Config under /etc/tarpn is deliberately left behind: removing a module
    # should never destroy the operator's node configuration.
    log_info "Removed ${name}; configuration in ${TARPN_ETC} was left in place"
}

# ---------------------------------------------------------------------------
# Enable / disable / lifecycle
# ---------------------------------------------------------------------------

module_enable() {
    local name="$1" unit
    # During a dry run nothing was recorded as installed, so skip the check
    # rather than fail on a module the same run just "installed".
    if [ "$TARPN_DRY_RUN" != true ]; then
        module_is_installed "$name" || die "module ${name} is not installed"
    fi
    for unit in $(module_enable_units "$name"); do
        run systemctl enable "$unit"
    done
}

module_disable() {
    local name="$1" unit
    for unit in $(module_enable_units "$name"); do
        if unit_is_enabled "$unit"; then run systemctl disable "$unit"; fi
    done
}

# start/stop/restart operate on the enable-units so that, for example,
# restarting `routes` restarts the timer rather than firing the oneshot.
module_lifecycle() {
    local action="$1" name="$2" unit
    if [ "$TARPN_DRY_RUN" != true ]; then
        module_is_installed "$name" || die "module ${name} is not installed"
    fi
    for unit in $(module_enable_units "$name"); do
        run systemctl "$action" "$unit"
    done
}
