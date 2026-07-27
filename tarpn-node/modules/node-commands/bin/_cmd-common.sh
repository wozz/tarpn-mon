#!/bin/bash
# _cmd-common.sh - shared helpers for node command handlers.
#
# These run with stdin and stdout wired to a socket that LinBPQ connected to on
# behalf of a user at the node prompt, quite possibly over a 1200 baud RF link.
# That shapes everything here:
#
#   - Output is terse. Every line costs airtime.
#   - Never block waiting on input without a timeout; the user may have
#     dropped the link, and the unit's RuntimeMaxSec is the only other
#     backstop.
#   - Never echo anything an unauthenticated remote user could use, such as
#     passwords or filesystem paths outside the node's own config.

# shellcheck disable=SC2034
CMD_LIB_LOADED=1

TARPN_PREFIX="${TARPN_PREFIX:-/opt/tarpn}"
if [ -f "${TARPN_PREFIX}/lib/tarpn-common.sh" ]; then
    # shellcheck source=/dev/null
    . "${TARPN_PREFIX}/lib/tarpn-common.sh"
fi

# Say a line to the user. Telnet convention is CRLF; LinBPQ passes it through.
# Trailing whitespace is stripped: column padding at the end of a line is pure
# airtime on a 1200 baud link.
say() {
    local s="$*"
    printf '%s\r\n' "${s%"${s##*[![:space:]]}"}"
}
blank() { printf '\r\n'; }

# LinBPQ sends the calling station's callsign as the first line for
# applications declared with the trailing "S" in their APPLICATION entry.
# Handlers that prompt for input must consume it first, or the callsign gets
# read as the answer to the first question.
read_callsign() {
    local line
    if IFS= read -r -t 10 line; then
        printf '%s' "$(printf '%s' "$line" | tr -d '\r\n')"
    fi
}

# Read one answer from the user. Strips the CR that telnet clients send, and
# gives up rather than hanging if the link has gone away.
ask() {
    local prompt="$1" timeout="${2:-60}" line
    printf '%s' "$prompt"
    if IFS= read -r -t "$timeout" line; then
        printf '%s' "$line" | tr -d '\r\n'
        return 0
    fi
    blank
    say "(no response - giving up)"
    return 1
}
