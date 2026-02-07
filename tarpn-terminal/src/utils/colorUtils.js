// Porting the color hash logic from Go to JS
import md5 from 'crypto-js/md5';

export function hashCallsign(callsign) {
    if (!callsign) return '#ccc';
    
    // MD5 hash
    const hash = md5(callsign).toString();
    
    // Take first 6 chars of hex hash -> 3 bytes -> int
    const hexHash = hash.substring(0, 6);
    let hue = parseInt(hexHash, 16);
    
    if (hue > 360) {
        hue = hue % 360;
    }
    
    const saturation = 60; // %
    const lightness = 67;  // %
    
    return `hsl(${hue}, ${saturation}%, ${lightness}%)`;
}
