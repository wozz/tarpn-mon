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
# Bytes written, used to size the hold in _cmd_drain.
_CMD_BYTES=0

say() {
    local s="$*"
    s="${s%"${s##*[![:space:]]}"}"
    _CMD_BYTES=$(( _CMD_BYTES + ${#s} + 2 ))
    printf '%s\r\n' "$s"
}
blank() { _CMD_BYTES=$(( _CMD_BYTES + 2 )); printf '\r\n'; }

# Stay alive briefly after writing, before exiting.
#
# Not politeness, and not a workaround for slow radio: without it output is
# silently lost, on a local telnet session as readily as over the air.
#
# There is nothing to flush. Our writes reach the socket immediately and LinBPQ
# receives them. It then moves them onward in stages - socket into
# FromHostBuffer, FromHostBuffer into the session queue at most PACLEN per
# driver poll, and one buffer off that queue per poll. When the handler exits,
# LinBPQ sees EOF, counts NeedDisc down, and tears the session down - at which
# point it discards both stages outright (TelnetV6.c):
#
#     sockptr->FromHostBuffPutptr = sockptr->FromHostBuffGetptr = 0;
#     while (PACTORtoBPQ_Q) { buffptr = Q_REM(...); ReleaseBuffer(buffptr); }
#
# So whatever has not been delivered when the countdown expires is freed, not
# sent. Anything written early gets through - a header printed before a slow
# query always arrives - while a burst written just before exit does not, and
# how much survives varies with where the polls happened to fall. It exits 0
# having written every line, which is why it looks like a display or radio
# fault rather than a timing one.
#
# Every legacy TARPN handler ends in a bare `sleep 3` for this. Scaled by what
# was actually written rather than fixed: 120 bytes per second is roughly a
# 1200 baud port, the slowest link these are read over. Floor of 3s to match
# the legacy behaviour on short replies, ceiling well inside RuntimeMaxSec.
_cmd_drain() {
    local secs=$(( _CMD_BYTES / 120 ))
    [ "$secs" -lt 3 ] && secs=3
    [ "$secs" -gt 20 ] && secs=20
    sleep "$secs"
}
trap _cmd_drain EXIT

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
