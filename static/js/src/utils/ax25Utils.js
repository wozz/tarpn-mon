// Helper to decode HTML entities for parsing
export function htmlDecode(input) {
    if (!input) return "";
    const doc = new DOMParser().parseFromString(input, "text/html");
    return doc.documentElement.textContent;
}

export function parseAX25Callsign(callsignStr) {
    if (!callsignStr) return { call: '', ssid: null };
    const parts = callsignStr.split('-');
    const call = parts[0];
    const ssid = parts.length > 1 ? parts[1] : null;
    return { call, ssid };
}

export function getFrameTypeAndExplanation(controlContent) {
    if (!controlContent) return { type: "Unknown/Text", explanation: "No AX.25 control field present. Assumed to be plain text or similar.", isCommand: false, isResponse: false, pollFinal: null, ns: null, nr: null, detailsString: "", parsedPIDFromUI: null, parsedLengthFromUI: null, parsedFrmrDataBytes: null };

    const parts = controlContent.split(/\s+/);
    let frameType = "Unknown";
    let explanation = "";
    let isCommand = parts.includes('C');
    let isResponse = parts.includes('R');
    let pollFinal = null;
    if (parts.includes('P')) pollFinal = 'Poll';
    if (parts.includes('F')) pollFinal = 'Final';

    let ns = null;
    let nr = null;
    let parsedPIDFromUI = null;
    let parsedLengthFromUI = null;
    let parsedFrmrDataBytes = null;

    const mainToken = parts[0];

    if (mainToken === 'I') {
        frameType = "Information (I)";
        explanation = "Carries Layer 3 data, sequenced and acknowledged.";
    } else if (mainToken === 'UI') {
        frameType = "Unnumbered Information (UI)";
        explanation = "Carries Layer 3 data, unsequenced and unacknowledged.";
        const pidMatch = controlContent.match(/pid=([0-9A-Fa-f]{2})/i);
        const lenMatch = controlContent.match(/Len=(\d+)/i);
        if (pidMatch) {
            parsedPIDFromUI = pidMatch[1];
            explanation += ` PID: 0x${parsedPIDFromUI}.`;
        }
        if (lenMatch) {
            parsedLengthFromUI = lenMatch[1];
            explanation += ` Length: ${parsedLengthFromUI}.`;
        }
        // If neither PID nor Length specifically matched but it's a UI frame,
        // and the controlContent is more than just "UI", append it for context.
        //if (!pidMatch && !lenMatch && controlContent.trim() !== "UI") {
        //    explanation += ` Raw Content: ${controlContent}.`;
        //}
    } else if (mainToken === 'SABM' || mainToken === 'C') {
        frameType = "Set Asynchronous Balanced Mode (SABM)";
        explanation = "Command to initiate a data link connection (standard mode).";
    } else if (mainToken === 'SABME') {
        frameType = "Set Asynchronous Balanced Mode Extended (SABME)";
        explanation = "Command to initiate a data link connection (extended mode, for modulo 128 sequence numbers).";
    } else if (mainToken === 'DISC' || mainToken === 'D') {
        frameType = "Disconnect (DISC)";
        explanation = "Command to terminate a data link connection.";
    } else if (mainToken === 'DM') {
        frameType = "Disconnected Mode (DM)";
        explanation = "Response indicating the station is logically disconnected.";
    } else if (mainToken === 'UA') {
        frameType = "Unnumbered Acknowledgment (UA)";
        explanation = "Response acknowledging receipt and acceptance of SABM, SABME, or DISC commands.";
    } else if (mainToken === 'FRMR') {
        frameType = "Frame Reject (FRMR)";
        explanation = "Response reporting receipt of an invalid or unimplementable frame.";
        const frmrData = [];
        let dataStartIndex = 1; // Index in 'parts' where FRMR data might start

        // Check if parts after "FRMR" are control flags like C/R or P/F before data bytes
        while(dataStartIndex < parts.length) {
            const part = parts[dataStartIndex];
            if (part === 'C' || part === 'R' || part === 'P' || part === 'F') {
                dataStartIndex++;
            } else {
                break; // First non-flag part is where data should start
            }
        }

        // FRMR data is typically 3 hex bytes.
        for (let i = 0; i < 3 && (dataStartIndex + i) < parts.length; i++) {
            const dataPart = parts[dataStartIndex + i];
            // Check if it looks like a hex byte (1 or 2 hex chars)
            if (/^[0-9A-Fa-f]{1,2}$/.test(dataPart)) {
                frmrData.push(dataPart);
            } else {
                // If a non-hex part is encountered where data is expected, assume end of FRMR data.
                break;
            }
        }

        if (frmrData.length > 0) {
            parsedFrmrDataBytes = frmrData;
            explanation += ` Data: ${parsedFrmrDataBytes.join(' ')}.`;
        }
    } else if (mainToken === 'RR') {
        frameType = "Receive Ready (RR)";
        explanation = "Supervisory frame indicating readiness to receive I-frames; acknowledges I-frames up to N(R)-1.";
    } else if (mainToken === 'RNR') {
        frameType = "Receive Not Ready (RNR)";
        explanation = "Supervisory frame indicating a temporary inability to receive I-frames; acknowledges I-frames up to N(R)-1.";
    } else if (mainToken === 'REJ') {
        frameType = "Reject (REJ)";
        explanation = "Supervisory frame requesting retransmission of I-frames starting with N(R).";
    } else if (mainToken === 'XID') {
        frameType = "Exchange Identification (XID)";
        explanation = "Used to exchange station identification and operational parameters.";
    } else if (mainToken === 'TEST') {
        frameType = "Test (TEST)";
        explanation = "Used to test the data link; the information field can be echoed back.";
    } else if (mainToken === 'SREJ') {
        frameType = "Selective Reject (SREJ)";
        explanation = "Supervisory frame requesting retransmission of a single specific I-frame N(S).";
    } else {
        explanation = "Control field: " + controlContent;
    }

    let controlDetailsText = [];
    if (isCommand && !isResponse && !['RR', 'RNR', 'REJ'].includes(mainToken)) controlDetailsText.push("Command indication");
    if (isResponse && !isCommand && !['RR', 'RNR', 'REJ'].includes(mainToken)) controlDetailsText.push("Response indication");

    if (pollFinal) controlDetailsText.push(`${pollFinal} bit set`);

    parts.forEach(part => {
        if (part.startsWith('S') && part.length > 1 && !isNaN(part.substring(1))) {
            ns = part.substring(1);
            controlDetailsText.push(`N(S)=${ns}`);
        }
    });

    const nrCandidateParts = parts.filter(p => p.match(/^R\d+$/));
    if (nrCandidateParts.length > 0) {
        const nrVal = nrCandidateParts[0].substring(1);
        if (mainToken === 'I' || mainToken === 'RR' || mainToken === 'RNR' || mainToken === 'REJ' || mainToken === 'SREJ') {
            nr = nrVal;
            controlDetailsText.push(`N(R)=${nr}`);
        }
    }

    return {
        type: frameType,
        explanation: explanation,
        isCommand,
        isResponse,
        pollFinal,
        ns,
        nr,
        detailsString: controlDetailsText.join(', '),
        parsedPIDFromUI,
        parsedLengthFromUI,
        parsedFrmrDataBytes
    };
}

export function parseAX25Message(ax25String) {
    if (!ax25String || typeof ax25String !== 'string') {
        return null;
    }
    // Ensure that calls to other utility functions within this file are correctly referenced if they were not also exported
    // or if they are not passed in as parameters. In this case, parseAX25Callsign and getFrameTypeAndExplanation are exported
    // and will be imported in App.vue, or this utility will be imported as a whole.
    // For simplicity, if these were intended to be private helpers for parseAX25Message only, they wouldn't be exported.

    // Helper function to get example PIDs for explanations
    function getExamplePidForProtocol(protocolName) {
        if (!protocolName) return "unknown";
        const lowerProto = protocolName.toLowerCase();
        if (lowerProto.includes("net/rom")) return "0xCF";
        if (lowerProto.includes("ip")) return "0xCC / 0x08"; // Standard IP / Fragmented IP
        if (lowerProto.includes("arp")) return "0xCD";
        if (lowerProto.includes("text") || lowerProto.includes("aprs")) return "0xF0";
        return "unknown";
    }

    const ax25Pattern = /^([A-Z0-9\-]+(?:-[0-9]+)?(?:\s+VIA\s+[A-Z0-9\-]+(?:-[0-9]+)?)*)\s*>\s*([A-Z0-9\-]+(?:-[0-9]+)?(?:,[A-Z0-9\-]+(?:-[0-9]+)?)*)\s*(?:<([^>]+)>)?\s*[:]?\s*(.*)$/si;

    let match = ax25String.match(ax25Pattern);

    if (match) {
        const sourceCallsignRaw = match[1] ? match[1].trim() : "";
        const destCallsignRaw = match[2] ? match[2].trim() : "";
        const sourceCallsign = parseAX25Callsign(sourceCallsignRaw.split(/\s+VIA\s+/i)[0]);
        const destCallsign = parseAX25Callsign(destCallsignRaw.split(',')[0]);

        const controlContent = match[3] ? match[3].trim() : null;
        let infoPart = match[4] ? match[4].trim() : "";

        const frameDetails = getFrameTypeAndExplanation(controlContent);
        let protocol = null;
        let pidString = null;
        let pidExplanation = null;

        // Initial protocol guess from infoPart
        if (infoPart) {
            if (/NET.ROM/i.test(infoPart)) protocol = "NET/ROM";
            else if (/^ARP\s/i.test(infoPart)) protocol = "ARP";
            else if (/^IP\s/i.test(infoPart)) protocol = "IP";
            // Note: "Text/APRS" protocol is usually inferred from PID 0xF0 or lack of other indicators.
        }

        if (frameDetails.parsedPIDFromUI) { // UI frame with explicit pid=XX in control string
            const pidUpper = frameDetails.parsedPIDFromUI.toUpperCase();
            pidString = `0x${pidUpper}`;
            switch (pidUpper) {
                case 'F0':
                    pidExplanation = "No Layer 3 Protocol / Text / APRS data.";
                    if (!protocol) protocol = "Text/APRS";
                    break;
                case 'CF':
                    pidExplanation = "NET/ROM Protocol.";
                    protocol = "NET/ROM";
                    break;
                case 'CC':
                    pidExplanation = "IP (Internet Protocol).";
                    protocol = "IP";
                    break;
                case 'CD':
                    pidExplanation = "ARP (Address Resolution Protocol).";
                    protocol = "ARP";
                    break;
                case '08':
                    pidExplanation = "Fragmented IP.";
                    if (!protocol || protocol.toLowerCase() !== "ip") protocol = "IP"; // Ensure protocol is IP
                    break;
                default:
                    pidExplanation = `Layer 3 Protocol ID: 0x${pidUpper}.`;
                    // protocol might remain from keyword search or be null
            }
        } else if (frameDetails.type === "Information (I)") { // True I-Frame (not UI)
            if (protocol) { // Protocol guessed from infoPart keywords
                pidString = `L3 (${protocol})`;
                const examplePid = getExamplePidForProtocol(protocol);
                pidExplanation = `Layer 3 Data: ${protocol}. The specific PID (e.g., ${examplePid}) is part of the AX.25 I-frame structure but not displayed in the control string.`;
            } else {
                // I-frame, but no L3 protocol keyword found in infoPart.
                if (infoPart) { // If there's info, and no other protocol, assume text
                    protocol = "Text";
                    pidString = "L3 (Text)";
                } else { // No info part, protocol is unknown
                    protocol = "Unknown L3";
                    pidString = "L3 Data (Unknown)";
                }
                pidExplanation = "Layer 3 Data. The PID (e.g., 0xF0 for Text/No L3) is part of the AX.25 I-frame structure but not displayed in the control string.";
            }
        } else if (frameDetails.type.includes("UI")) { // UI-Frame without explicit pid in control string
            if (protocol) { // Protocol guessed from infoPart keywords for a UI frame
                const examplePid = getExamplePidForProtocol(protocol);
                pidString = `UI (${protocol})`;
                pidExplanation = `Unnumbered Information for ${protocol}. Expected PID (e.g., ${examplePid}) not displayed in control string.`;
            } else { // Generic UI without explicit PID and no keywords
                pidString = "0xF0 (Default for UI)";
                pidExplanation = "Typically No Layer 3 Protocol, Text, or APRS data for UI frames without an explicit PID in the control string.";
                if (!protocol) protocol = "Text/APRS";
            }
        } else if (!controlContent && infoPart) { // No control field, but info is present
            pidString = "Text (Assumed)";
            pidExplanation = "No AX.25 control field; assumed to be plain text or similar.";
            if (!protocol) protocol = "Text";
        }
        // For other frame types (SABM, RR, etc.), pidString and pidExplanation will remain null.

        return {
            source: sourceCallsign,
            destination: destCallsign,
            controlRaw: controlContent,
            frameType: frameDetails.type,
            frameTypeExplanation: frameDetails.explanation,
            controlDetails: frameDetails,
            pid: pidString,
            pidExplanation: pidExplanation,
            protocol: protocol,
            info: infoPart,
            _sourceRaw: sourceCallsignRaw,
            _destRaw: destCallsignRaw
        };
    } else {
        return null;
    }
} 