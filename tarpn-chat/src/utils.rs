//! Utility functions shared across modules

/// Strip SSID from callsign (e.g., "TEST1-9" -> "TEST1", "N0CALL-7" -> "N0CALL")
/// This follows LinBPQ's convention of stripping the SSID for display purposes.
pub fn strip_ssid(callsign: &str) -> &str {
    callsign.split('-').next().unwrap_or(callsign)
}

/// Strip leading whitespace and newlines from bytes.
/// Used when parsing protocol messages that may have leading garbage.
pub fn strip_leading_whitespace(bytes: &[u8]) -> &[u8] {
    bytes
        .iter()
        .position(|&b| b != b'\n' && b != b'\r' && b != b' ')
        .map(|pos| &bytes[pos..])
        .unwrap_or(&[])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strip_ssid_with_ssid() {
        assert_eq!(strip_ssid("TEST1-9"), "TEST1");
        assert_eq!(strip_ssid("N0CALL-7"), "N0CALL");
        assert_eq!(strip_ssid("WA2M-15"), "WA2M");
        assert_eq!(strip_ssid("KB1ABC-1"), "KB1ABC");
    }

    #[test]
    fn test_strip_ssid_without_ssid() {
        assert_eq!(strip_ssid("TEST1"), "TEST1");
        assert_eq!(strip_ssid("N0CALL"), "N0CALL");
        assert_eq!(strip_ssid(""), "");
    }

    #[test]
    fn test_strip_ssid_multiple_dashes() {
        // Should only strip at the first dash (like LinBPQ)
        assert_eq!(strip_ssid("TEST-1-2"), "TEST");
    }

    #[test]
    fn test_strip_leading_whitespace_newlines() {
        assert_eq!(strip_leading_whitespace(b"\n\r\nhello"), b"hello");
        assert_eq!(strip_leading_whitespace(b"\r\n  test"), b"test");
        assert_eq!(strip_leading_whitespace(b"   data"), b"data");
    }

    #[test]
    fn test_strip_leading_whitespace_mixed() {
        assert_eq!(strip_leading_whitespace(b"\n \r \n test"), b"test");
        assert_eq!(strip_leading_whitespace(b"  \n\r  hello world"), b"hello world");
    }

    #[test]
    fn test_strip_leading_whitespace_no_whitespace() {
        assert_eq!(strip_leading_whitespace(b"hello"), b"hello");
        assert_eq!(strip_leading_whitespace(b"\x01Ktest"), b"\x01Ktest");
    }

    #[test]
    fn test_strip_leading_whitespace_empty() {
        assert_eq!(strip_leading_whitespace(b""), b"");
    }

    #[test]
    fn test_strip_leading_whitespace_all_whitespace() {
        assert_eq!(strip_leading_whitespace(b"   \n\r  "), b"");
    }

    #[test]
    fn test_strip_leading_whitespace_preserves_internal() {
        // Should only strip leading whitespace, not internal
        assert_eq!(strip_leading_whitespace(b"  hello world  "), b"hello world  ");
    }
}
