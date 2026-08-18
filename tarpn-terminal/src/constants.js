// Connection and timing constants for tarpn-terminal

// WebSocket reconnection settings
export const RECONNECT_DELAY_MS = 5000;

// UI timing constants
export const SCROLL_DELAY_MS = 100; // Hysteresis delay for auto-scroll behavior
export const INPUT_REFOCUS_DELAY_MS = 50;

// Message batching and processing
export const BATCH_INTERVAL_MS = 200; // Process message queues every 200ms

// Most live messages kept in memory on the monitor screen. Matches the
// backend's `-buffer-size`, since that is the most history it will ever serve -
// holding more client side buys nothing.
//
// The point of the cap is that it is bounded at all: before it existed the log
// grew for as long as the page was open, which showed up as the browser
// reporting high energy use and eventually discarding the tab. Older messages
// are dropped as new ones arrive; history pulled in deliberately by scrolling
// back is not affected.
export const MAX_LOG_MESSAGES = 20000;

// Pagination settings
export const INITIAL_MESSAGE_LIMIT = 1000; // Monitor screen initial load
export const CHAT_MESSAGE_LIMIT = 200; // Chat screen initial/pagination load
export const LOAD_MORE_LIMIT = 500; // Default limit for loadMoreHistory
export const PAGINATION_TIMEOUT_MS = 10000; // Timeout waiting for pagination response
export const LOAD_MORE_TIMEOUT_MS = 2000; // Safety timeout for loadMoreHistory

// BBS-specific timing
export const BBS_REFRESH_DELAY_MS = 500; // Delay before refreshing after delete

// Node buffer settings
export const NODE_BUFFER_SIZE = 200; // Node console message buffer

// Default port settings
export const DEFAULT_TELNET_PORT = 8010;
export const DEFAULT_MONITOR_PORT = 8011;
export const DEFAULT_BACKEND_PORT = 8212;

// Stats timing
export const STATS_UPDATE_INTERVAL_MS = 1000;
export const STATS_MAX_HISTORY_POINTS = 500;
export const STATS_WINDOW_MS = 60 * 60 * 1000; // 1 hour
