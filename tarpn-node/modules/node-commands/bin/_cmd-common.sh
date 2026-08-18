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
# Output is collected and written in one go rather than a line at a time, then
# the socket is held open briefly. Both matter, for the same reason.
#
# LinBPQ moves what we send in stages: socket into FromHostBuffer, then at most
# PACLEN of that into the session queue per driver poll, then exactly one
# buffer off that queue per poll - one buffer, whatever its size. On EOF it
# counts NeedDisc down, about ten polls, and then tears the session down,
# discarding both stages outright (TelnetV6.c):
#
#     sockptr->FromHostBuffPutptr = sockptr->FromHostBuffGetptr = 0;
#     while (PACTORtoBPQ_Q) { buffptr = Q_REM(...); ReleaseBuffer(buffptr); }
#
# Writing a line at a time is what made this bite: the polls fall between our
# writes, so each line tends to become its own buffer, and eight lines need
# eight polls to clear against a ten poll countdown. That is why output was
# lost, why the amount varied, and why losses fell on line boundaries.
#
# Written as one block instead, the same eight lines are chunked at PACLEN into
# two buffers and clear in a handful of polls. It also keeps the queue far
# below the fifteen frames at which LinBPQ stops reading us altogether, so this
# no longer depends on how fast the link drains - which is what made the
# previous fix need a hold long enough for the radio.
_CMD_BUF=""

say() {
    local s="$*"
    _CMD_BUF="${_CMD_BUF}${s%"${s##*[![:space:]]}"}"$'\r\n'
}
blank() { _CMD_BUF="${_CMD_BUF}"$'\r\n'; }

# Write everything buffered so far as a single block. Handlers that prompt must
# do this first, or the question is still sitting in the buffer while we wait
# for its answer - `ask` does it for them.
cmd_flush() {
    [ -n "$_CMD_BUF" ] || return 0
    printf '%s' "$_CMD_BUF"
    _CMD_BUF=""
}

# Flush, then give LinBPQ time to move it on before the teardown starts. A
# couple of buffers clear in well under half a second at the usual poll rate;
# a second is margin, not a wait for the radio. Only a reply beyond about
# fifteen frames could need longer, and none of these come close.
_cmd_finish() {
    cmd_flush
    sleep 1
}
trap _cmd_finish EXIT

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
    cmd_flush
    printf '%s' "$prompt"
    if IFS= read -r -t "$timeout" line; then
        printf '%s' "$line" | tr -d '\r\n'
        return 0
    fi
    blank
    say "(no response - giving up)"
    return 1
}
