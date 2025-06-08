import { parseAX25Message, getFrameTypeAndExplanation, parseAX25Callsign, htmlDecode } from './ax25Utils';

// Mock DOMParser for Jest environment
global.DOMParser = class {
  parseFromString(str, type) {
    return {
      documentElement: {
        textContent: str.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&'),
      },
    };
  }
};

describe('ax25Utils', () => {

  describe('htmlDecode', () => {
    it('should decode HTML entities', () => {
      expect(htmlDecode('Test &lt;tag&gt;')).toBe('Test <tag>');
    });
    it('should return empty string for null input', () => {
      expect(htmlDecode(null)).toBe('');
    });
  });

  describe('parseAX25Callsign', () => {
    it('should parse a callsign without SSID', () => {
      expect(parseAX25Callsign('N0CALL')).toEqual({ call: 'N0CALL', ssid: null });
    });
    it('should parse a callsign with SSID', () => {
      expect(parseAX25Callsign('N0CALL-1')).toEqual({ call: 'N0CALL', ssid: '1' });
    });
  });

  describe('getFrameTypeAndExplanation', () => {
    it('should identify UI frame with PID and Length', () => {
      const result = getFrameTypeAndExplanation('UI C pid=F0 Len=27');
      expect(result.type).toBe('Unnumbered Information (UI)');
      expect(result.parsedPIDFromUI).toBe('F0');
      expect(result.parsedLengthFromUI).toBe('27');
      expect(result.isCommand).toBe(true);
    });

    it('should identify a standard I-frame', () => {
      const result = getFrameTypeAndExplanation('I C S2 R3 P');
      expect(result.type).toBe('Information (I)');
      expect(result.ns).toBe('2');
      expect(result.nr).toBe('3');
      expect(result.pollFinal).toBe('Poll');
      expect(result.isCommand).toBe(true);
    });

    it('should identify an FRMR frame with data', () => {
      const result = getFrameTypeAndExplanation('FRMR R F 01 45 87');
      expect(result.type).toBe('Frame Reject (FRMR)');
      expect(result.isResponse).toBe(true);
      expect(result.pollFinal).toBe('Final');
      expect(result.parsedFrmrDataBytes).toEqual(['01', '45', '87']);
    });

    it('should identify an SREJ frame', () => {
        const result = getFrameTypeAndExplanation('SREJ R R4');
        expect(result.type).toBe('Selective Reject (SREJ)');
        expect(result.isResponse).toBe(true);
        expect(result.nr).toBe('4');
    });

    it('should identify a TEST frame', () => {
        const result = getFrameTypeAndExplanation('TEST C');
        expect(result.type).toBe('Test (TEST)');
        expect(result.isCommand).toBe(true);
    });

    it('should identify an XID frame', () => {
        const result = getFrameTypeAndExplanation('XID R F');
        expect(result.type).toBe('Exchange Identification (XID)');
        expect(result.isResponse).toBe(true);
        expect(result.pollFinal).toBe('Final');
    });
  });

  describe('parseAX25Message', () => {
    it('should parse a standard UI frame with APRS data', () => {
      const msg = 'N0CALL-1 > APRS <UI pid=F0 Len=50> :!4903.50N/07201.75W-Hello';
      const result = parseAX25Message(msg);
      expect(result.source.call).toBe('N0CALL');
      expect(result.source.ssid).toBe('1');
      expect(result.destination.call).toBe('APRS');
      expect(result.frameType).toBe('Unnumbered Information (UI)');
      expect(result.pid).toBe('0xF0');
      expect(result.protocol).toBe('Text/APRS');
      expect(result.info).toBe('!4903.50N/07201.75W-Hello');
    });

    it('should parse a standard I-frame with NET/ROM data', () => {
      const msg = 'N0CALL-2 > N0CALL-3 <I C S0 R1> :NET/ROM data here';
      const result = parseAX25Message(msg);
      expect(result.source.call).toBe('N0CALL');
      expect(result.source.ssid).toBe('2');
      expect(result.destination.call).toBe('N0CALL');
      expect(result.destination.ssid).toBe('3');
      expect(result.frameType).toBe('Information (I)');
      expect(result.pid).toBe('L3 (NET/ROM)');
      expect(result.protocol).toBe('NET/ROM');
      expect(result.controlDetails.ns).toBe('0');
      expect(result.controlDetails.nr).toBe('1');
      expect(result.info).toBe('NET/ROM data here');
      expect(result.pidExplanation).toContain('0xCF');
    });

    it('should parse a supervisory RR frame', () => {
      const msg = 'N0CALL-4 > N0CALL-5 <RR R F R6>';
      const result = parseAX25Message(msg);
      expect(result.source.call).toBe('N0CALL');
      expect(result.destination.call).toBe('N0CALL');
      expect(result.frameType).toBe('Receive Ready (RR)');
      expect(result.controlDetails.isResponse).toBe(true);
      expect(result.controlDetails.pollFinal).toBe('Final');
      expect(result.controlDetails.nr).toBe('6');
      expect(result.info).toBe('');
      expect(result.pid).toBe(null);
    });
    
    it('should parse a SABM command', () => {
        const msg = 'N0CALL-10 > N0CALL-11 <SABM C P>';
        const result = parseAX25Message(msg);
        expect(result.frameType).toBe('Set Asynchronous Balanced Mode (SABM)');
        expect(result.controlDetails.isCommand).toBe(true);
        expect(result.controlDetails.pollFinal).toBe('Poll');
        expect(result.protocol).toBe(null);
    });

    it('should parse a UA response', () => {
        const msg = 'N0CALL-11 > N0CALL-10 <UA R F>';
        const result = parseAX25Message(msg);
        expect(result.frameType).toBe('Unnumbered Acknowledgment (UA)');
        expect(result.controlDetails.isResponse).toBe(true);
        expect(result.controlDetails.pollFinal).toBe('Final');
    });

    it('should handle UI frame for IP protocol based on keyword', () => {
      const msg = 'N0CALL-1 > N0CALL-2 <UI R> :IP packet data';
      const result = parseAX25Message(msg);
      expect(result.frameType).toBe('Unnumbered Information (UI)');
      expect(result.protocol).toBe('IP');
      expect(result.pid).toBe('UI (IP)');
      expect(result.pidExplanation).toContain('0xCC / 0x08');
    });

    it('should handle a simple text message with no control field', () => {
      const msg = 'N0CALL-7 > N0CALL-8 :Just some text';
      const result = parseAX25Message(msg);
      expect(result.source.call).toBe('N0CALL');
      expect(result.destination.call).toBe('N0CALL');
      expect(result.frameType).toBe('Unknown/Text');
      expect(result.protocol).toBe('Text');
      expect(result.pid).toBe('Text (Assumed)');
      expect(result.info).toBe('Just some text');
    });

    it('should handle an I-frame with generic text', () => {
        const msg = 'N0CALL-1 > N0CALL-2 <I C S4 R5> :here is some text';
        const result = parseAX25Message(msg);
        expect(result.frameType).toBe('Information (I)');
        expect(result.protocol).toBe('Text');
        expect(result.pid).toBe('L3 (Text)');
        expect(result.pidExplanation).toContain('0xF0 for Text/No L3');
    });

    it('should return null for invalid input string', () => {
      expect(parseAX25Message('this is not an ax25 string')).toBe(null);
      expect(parseAX25Message(null)).toBe(null);
      expect(parseAX25Message('')).toBe(null);
    });

    it('should correctly parse source and dest with VIA digipeaters', () => {
        const msg = 'N0CALL-1 VIA DIGI1-2 > N0CALL-2 <UI R> :test';
        const result = parseAX25Message(msg);
        expect(result._sourceRaw).toBe('N0CALL-1 VIA DIGI1-2');
        expect(result.source.call).toBe('N0CALL');
        expect(result.source.ssid).toBe('1');
        // Note: Current implementation does not parse out digipeaters into a separate field.
        // The source callsign is correctly identified as the part before "VIA".
    });

    it('should parse a multi-line NET/ROM I-frame for a CON REQ', () => {
      const info = `NET/ROM
  WA2M-9 to WF8E-9 ttl 7 cct=0902 <CON REQ> w=3 WA2M-9 at WA2M-9 t/o 120`;
      const msg = `WA2M-1 > WF8E-1 <I C P S0 R0> :${info}`;
      const result = parseAX25Message(msg);

      expect(result).not.toBeNull();
      expect(result.frameType).toBe('Information (I)');
      expect(result.protocol).toBe('NET/ROM');
      expect(result.pid).toBe('L3 (NET/ROM)');
      expect(result.controlDetails.ns).toBe('0');
      expect(result.controlDetails.nr).toBe('0');
      expect(result.info).toBe(info);
    });

    it('should parse a UI frame with a multi-line text payload', () => {
      const info = `Terrestrial Amateur Radio Packet Network node MIKE  op is wa2m`;
      const msg = `MIKE > ID <UI C>:\n${info}`;
      const result = parseAX25Message(msg);

      expect(result).not.toBeNull();
      expect(result.frameType).toBe('Unnumbered Information (UI)');
      expect(result.protocol).toBe('Text/APRS');
      expect(result.pid).toBe('0xF0 (Default for UI)');
      expect(result.controlDetails.isCommand).toBe(true);
      expect(result.info).toBe(info);
    });

    it('should parse a multi-line NET/ROM I-frame for BPQChatServer info', () => {
      const info = `NET/ROM
  WF8E-2 to WA2M-9 ttl 7 cct=09D1  <INFO S0 R0>:
[BPQChatServer-6.0.21.40]`;
      const msg = `WF8E-2 > WA2M-9 <I C P S0 R0> :${info}`;
      const result = parseAX25Message(msg);
      
      expect(result).not.toBeNull();
      expect(result.source.call).toBe('WF8E');
      expect(result.source.ssid).toBe('2');
      expect(result.destination.call).toBe('WA2M');
      expect(result.destination.ssid).toBe('9');
      expect(result.frameType).toBe('Information (I)');
      expect(result.protocol).toBe('NET/ROM');
      expect(result.pid).toBe('L3 (NET/ROM)');
      expect(result.info).toBe(info);
    });
  });
}); 