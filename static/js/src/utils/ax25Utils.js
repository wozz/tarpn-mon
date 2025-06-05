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
    if (!controlContent) return { type: "Unknown/Text", explanation: "No AX.25 control field present. Assumed to be plain text or similar.", isCommand: false, isResponse: false, pollFinal: null, ns: null, nr: null, detailsString: "" };

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

    const mainToken = parts[0];

    if (mainToken === 'I') {
        frameType = "Information (I)";
        explanation = "Carries Layer 3 data, sequenced and acknowledged.";
    } else if (mainToken === 'UI') {
        frameType = "Unnumbered Information (UI)";
        explanation = "Carries Layer 3 data, unsequenced and unacknowledged (e.g., APRS, broadcasts).";
    } else if (mainToken === 'SABM') {
        frameType = "Set Asynchronous Balanced Mode (SABM)";
        explanation = "Command to initiate a data link connection (standard mode).";
    } else if (mainToken === 'SABME') {
        frameType = "Set Asynchronous Balanced Mode Extended (SABME)";
        explanation = "Command to initiate a data link connection (extended mode, for modulo 128 sequence numbers).";
    } else if (mainToken === 'DISC') {
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
    } else if (mainToken === 'RR') {
        frameType = "Receive Ready (RR)";
        explanation = "Supervisory frame indicating readiness to receive I-frames; acknowledges I-frames up to N(R)-1.";
    } else if (mainToken === 'RNR') {
        frameType = "Receive Not Ready (RNR)";
        explanation = "Supervisory frame indicating a temporary inability to receive I-frames; acknowledges I-frames up to N(R)-1.";
    } else if (mainToken === 'REJ') {
        frameType = "Reject (REJ)";
        explanation = "Supervisory frame requesting retransmission of I-frames starting with N(R).";
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
        if (mainToken === 'I' || mainToken === 'RR' || mainToken === 'RNR' || mainToken === 'REJ') {
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
        detailsString: controlDetailsText.join(', ')
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

    const ax25Pattern = /^([A-Z0-9\-]+(?:-[0-9]+)?(?:\s+VIA\s+[A-Z0-9\-]+(?:-[0-9]+)?)?)\s*>\s*([A-Z0-9\-]+(?:-[0-9]+)?(?:,[A-Z0-9\-]+(?:-[0-9]+)?)*)\s*(?:<([^>]+)>)?\s*[:]?\s*(.*)$/si;

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
        let pid = null;
        let pidExplanation = null;

        if (infoPart) {
            if (/NET.ROM/i.test(infoPart)) protocol = "NET/ROM";
            else if (/^ARP\s/i.test(infoPart)) protocol = "ARP";
            else if (/^IP\s/i.test(infoPart)) protocol = "IP";
            else if (frameDetails.type.includes("UI") && infoPart.startsWith(":")) {
                // APRS or simple text
            }
        }

        if ((frameDetails.type.includes("UI") || (!controlContent && infoPart)) && !protocol) {
            pid = "0xF0 (No L3 / Text)";
            pidExplanation = "Typically No Layer 3 Protocol, Text, or APRS data.";
        } else if (frameDetails.type.includes("I") && !protocol) {
            pid = "L3 Data (e.g. 0xCF, 0x06)";
            pidExplanation = "Layer 3 Data (e.g., X.25 PLP, NET/ROM, TCP/IP).";
        }

        return {
            source: sourceCallsign,
            destination: destCallsign,
            controlRaw: controlContent,
            frameType: frameDetails.type,
            frameTypeExplanation: frameDetails.explanation,
            controlDetails: frameDetails,
            pid: pid,
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