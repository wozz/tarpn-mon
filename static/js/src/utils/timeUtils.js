export function parseMessageTimestamp(timestampStr) {
    if (typeof timestampStr !== 'string' || !/^\d{2}:\d{2}:\d{2}$/.test(timestampStr)) {
        return null;
    }
    const parts = timestampStr.split(':');
    const hours = parseInt(parts[0], 10);
    const minutes = parseInt(parts[1], 10);
    const seconds = parseInt(parts[2], 10);

    const now = new Date();
    const msgUtcDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hours, minutes, seconds));

    // If the parsed time is in the future (e.g. message from 23:59:59 and current time is 00:00:01 of the next day UTC)
    // assume it was from the previous day.
    if (msgUtcDate.getTime() > Date.now() + 60 * 60 * 1000) { // Allow for some clock skew (1 hour)
        msgUtcDate.setUTCDate(msgUtcDate.getUTCDate() - 1);
    }
    return msgUtcDate;
}

export function getMinuteKey(dateObj) {
    if (!(dateObj instanceof Date) || isNaN(dateObj)) return null;
    const keyDate = new Date(dateObj.getTime());
    keyDate.setUTCSeconds(0, 0);
    return keyDate.toISOString();
} 