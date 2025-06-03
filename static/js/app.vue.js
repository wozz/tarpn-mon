const {
    createApp,
    ref,
    reactive,
    computed,
    watch,
    nextTick
} = Vue;

const App = {
    setup() {
        const logMessages = ref([]);
        const tncData = reactive({}); // Store TNC data by port number
        const autoScrollEnabled = ref(true);
        const hideUSBRoutes = ref(false);
        const uniquePorts = ref(new Set());
        const visiblePorts = ref([]); // Array of port numbers that are checked (visible)
        const version = ref("N/A");
        const ax25TooltipEnabled = ref(false); // New setting for AX.25 tooltip, off by default
        const outputContainer = ref(null); // For autoscroll
        const messageCountsByMinute = reactive({}); // Key: UTC minute string, Value: count
        const graphMinuteSlots = ref([]); // Array of Date objects for the last 60 minutes (slots)

        const graphUpdateQueue = ref([]); // Stores utcDate objects of new messages for graph processing
        const tncDataUpdateQueue = ref([]); // Stores incoming TNC data objects for batch processing
        const logMessageQueue = ref([]); // Stores incoming log message objects for batch processing

        const tooltip = reactive({ // For AX.25 details tooltip
            visible: false,
            data: {},
            x: 0,
            y: 0
        });

        // Helper to decode HTML entities for parsing
        function htmlDecode(input) {
            if (!input) return "";
            const doc = new DOMParser().parseFromString(input, "text/html");
            return doc.documentElement.textContent;
        }

        function parseAX25Callsign(callsignStr) {
            if (!callsignStr) return { call: '', ssid: null };
            const parts = callsignStr.split('-');
            const call = parts[0];
            const ssid = parts.length > 1 ? parts[1] : null;
            return { call, ssid };
        }

        function getFrameTypeAndExplanation(controlContent) {
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

        function parseAX25Message(ax25String) { 
            if (!ax25String || typeof ax25String !== 'string') {
                return null;
            }

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

        // Helper to parse "HH:MM:SS" (UTC) and return a Date object
        function parseMessageTimestamp(timestampStr) {
            if (typeof timestampStr !== 'string' || !/^\d{2}:\d{2}:\d{2}$/.test(timestampStr)) {
                return null; 
            }
            const parts = timestampStr.split(':');
            const hours = parseInt(parts[0], 10);
            const minutes = parseInt(parts[1], 10);
            const seconds = parseInt(parts[2], 10);

            const now = new Date(); 
            const msgUtcDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hours, minutes, seconds));

            if (msgUtcDate.getTime() > Date.now() + 60 * 60 * 1000) {
                msgUtcDate.setUTCDate(msgUtcDate.getUTCDate() - 1);
            }
            return msgUtcDate;
        }

        // Generic Debouncer
        function createDebouncer(processFn, delay) {
            let timer = null;
            return (...args) => {
                if (timer) {
                    clearTimeout(timer);
                }
                timer = setTimeout(() => {
                    processFn(...args);
                    timer = null;
                }, delay);
            };
        }

        // Helper to get a standardized UTC minute key from a Date object
        function getMinuteKey(dateObj) {
            if (!(dateObj instanceof Date) || isNaN(dateObj)) return null;
            const keyDate = new Date(dateObj.getTime());
            keyDate.setUTCSeconds(0, 0); 
            return keyDate.toISOString(); 
        }

        const displayedGraphData = computed(() => {
            return graphMinuteSlots.value.map(slotDate => {
                const minuteKey = getMinuteKey(slotDate);
                const count = messageCountsByMinute[minuteKey] || 0;
                const label = slotDate.toLocaleTimeString('en-US', {
                    hour: '2-digit',
                    minute: '2-digit',
                    hour12: false
                });
                return { label, count, minuteKey }; 
            });
        });

        function updateGraphSlots() {
            const now = new Date();
            const newSlots = [];
            for (let i = 59; i >= 0; i--) {
                const slotDate = new Date(now.getTime() - i * 60 * 1000);
                slotDate.setUTCSeconds(0, 0); 
                newSlots.push(slotDate);
            }
            graphMinuteSlots.value = newSlots;
        }

        function processHistoricalMessagesForGraph() {
            logMessages.value.forEach(msg => {
                if (msg.utcDate) {
                    const minuteKey = getMinuteKey(msg.utcDate);
                    if (minuteKey) {
                        messageCountsByMinute[minuteKey] = (messageCountsByMinute[minuteKey] || 0) + 1;
                    }
                }
            });
            updateGraphSlots(); 
        }

        const sortedTncData = computed(() => {
            return Object.keys(tncData)
                .sort((a, b) => parseInt(a) - parseInt(b))
                .reduce((obj, key) => {
                    obj[key] = tncData[key];
                    return obj;
                }, {});
        });

        const sortedUniquePorts = computed(() => {
            return Array.from(uniquePorts.value).sort((a, b) => parseInt(a) - parseInt(b));
        });
        
        watch(sortedUniquePorts, (newPorts, oldPorts) => {
            newPorts.forEach(port => {
                if (!visiblePorts.value.includes(port)) {
                    visiblePorts.value.push(port);
                }
            });
        });

        function isHidden(msg) {
            if (hideUSBRoutes.value && msg.route === "TNC>USB") {
                return true;
            }
            if (msg.port && !visiblePorts.value.includes(msg.port)) {
                return true;
            }
            return false;
        }

        function processGraphUpdateQueue() {
            if (graphUpdateQueue.value.length === 0) return;

            graphUpdateQueue.value.forEach(utcDate => {
                if (utcDate) { 
                    const minuteKey = getMinuteKey(utcDate);
                    if (minuteKey) {
                        messageCountsByMinute[minuteKey] = (messageCountsByMinute[minuteKey] || 0) + 1;
                    }
                }
            });
            graphUpdateQueue.value = []; 
        }

        const scheduleGraphUpdate = createDebouncer(processGraphUpdateQueue, 100);

        function processTncDataUpdateQueue() {
            if (tncDataUpdateQueue.value.length === 0) return;

            tncDataUpdateQueue.value.forEach(data => {
                tncData[data.portNum] = data.data; 
                if (!uniquePorts.value.has(String(data.portNum))) {
                    uniquePorts.value.add(String(data.portNum));
                }
            });
            tncDataUpdateQueue.value = []; 
        }

        const scheduleTncDataUpdate = createDebouncer(processTncDataUpdateQueue, 100);

        function processLogMessageQueue() {
            if (logMessageQueue.value.length === 0) return;

            const messagesToAdd = logMessageQueue.value;
            logMessages.value.push(...messagesToAdd); 

            messagesToAdd.forEach(msg => {
                if (msg.port && !uniquePorts.value.has(msg.port)) {
                    uniquePorts.value.add(msg.port);
                }
            });

            logMessageQueue.value = []; 
        }

        const scheduleLogMessageUpdate = createDebouncer(processLogMessageQueue, 50);

        function connectWebSocket() {
            const socket = new WebSocket(`ws://${window.location.host}/ws`);

            socket.onopen = () => {
                console.log("WebSocket connection established");
            };

            socket.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    if (data.type === 'log') {
                        const msgObject = { ...data }; 
                        msgObject.utcDate = parseMessageTimestamp(data.timestamp);
                        if (msgObject.utcDate) {
                            msgObject.displayTimestamp = msgObject.utcDate.toLocaleTimeString('en-US', { hour12: false });
                            graphUpdateQueue.value.push(msgObject.utcDate);
                            scheduleGraphUpdate();
                        } else {
                            msgObject.displayTimestamp = data.timestamp; 
                        }

                        let stringToParseForAX25 = "";
                        if (msgObject.route && msgObject.message) {
                            if (msgObject.message.includes(">") && msgObject.message.match(/^[A-Z0-9\-]+(?:-[0-9]+)?\s*>/i)) {
                                stringToParseForAX25 = htmlDecode(msgObject.message);
                            } else {
                                stringToParseForAX25 = htmlDecode(msgObject.route + " " + msgObject.message);
                            }
                        } else if (msgObject.message) { 
                             stringToParseForAX25 = htmlDecode(msgObject.message);
                        } else if (msgObject.raw) { 
                            stringToParseForAX25 = htmlDecode(msgObject.raw);
                        }
                        
                        if (stringToParseForAX25) {
                            msgObject.ax25Info = parseAX25Message(stringToParseForAX25);
                        }

                        logMessageQueue.value.push(msgObject);
                        scheduleLogMessageUpdate();
                    } else if (data.type === 'tnc_data') {
                        tncDataUpdateQueue.value.push(data);
                        scheduleTncDataUpdate();
                    }
                } catch (e) {
                    console.error("Error parsing incoming JSON data:", e, event.data);
                    logMessages.value.push({ type: 'log', raw: event.data, timestamp: new Date().toLocaleTimeString('en-US', { hour12: false }) });
                }
            };

            socket.onerror = (error) => {
                console.error("WebSocket Error:", error);
                 logMessages.value.push({ 
                    type: 'log', 
                    raw: `WebSocket Error: ${error.message || 'Connection failed'}`,
                    timestamp: new Date().toLocaleTimeString('en-US', { hour12: false }), 
                    isError: true 
                });
            };

            socket.onclose = () => {
                console.log("WebSocket connection closed. Attempting to reconnect...");
                 logMessages.value.push({ 
                    type: 'log', 
                    raw: 'WebSocket connection closed. Attempting to reconnect...',
                    timestamp: new Date().toLocaleTimeString('en-US', { hour12: false }), 
                    isWarning: true 
                });
                setTimeout(connectWebSocket, 5000); 
            };
        }

        function fetchVersion() {
            fetch("/version")
                .then(response => {
                    if (!response.ok) {
                        throw new Error(`HTTP error! status: ${response.status}`);
                    }
                    return response.text();
                })
                .then(data => version.value = data)
                .catch(error => {
                    console.error("Could not fetch version:", error);
                    version.value = "Error fetching version";
                });
        }

        watch(logMessages, async () => {
            if (autoScrollEnabled.value) {
                await nextTick(); 
                const container = document.getElementById('output-container'); 
                if (container) {
                    container.scrollTop = container.scrollHeight;
                }
            }
        }, { deep: true });

        connectWebSocket();
        fetchVersion();
        updateGraphSlots(); 

        setInterval(() => {
            updateGraphSlots();
        }, 1000); 

        function showTooltip(msg, event) {
            if (!ax25TooltipEnabled.value) {
                tooltip.visible = false; // Ensure it's hidden if disabled
                return; // Do not show tooltip if disabled
            }

            if (msg && msg.ax25Info && msg.ax25Info.source) { 
                tooltip.data = { ...msg.ax25Info }; 
                
                if (event && typeof event.clientX === 'number' && typeof event.clientY === 'number') {
                    tooltip.x = event.clientX + 15;
                    tooltip.y = event.clientY + 15;
                } else {
                    tooltip.x = 100; 
                    tooltip.y = 100;
                }

                tooltip.visible = true; 

                nextTick(() => { 
                    const tooltipEl = document.getElementById('ax25-tooltip');
                    if (tooltipEl) {
                        const rect = tooltipEl.getBoundingClientRect();
                        let adjustedX = tooltip.x;
                        let adjustedY = tooltip.y;

                        if (adjustedX + rect.width > window.innerWidth) {
                            adjustedX = window.innerWidth - rect.width - 10;
                        }
                        if (adjustedY + rect.height > window.innerHeight) {
                            adjustedY = window.innerHeight - rect.height - 10;
                        }
                        if (adjustedX < 0) adjustedX = 5; 
                        if (adjustedY < 0) adjustedY = 5; 
                        
                        tooltip.x = adjustedX;
                        tooltip.y = adjustedY;
                    }
                });
            } else {
                tooltip.visible = false; 
            }
        }

        function hideTooltip() {
            tooltip.visible = false;
        }

        return { 
            logMessages,
            tncData,
            autoScrollEnabled,
            hideUSBRoutes,
            uniquePorts,
            visiblePorts,
            version,
            ax25TooltipEnabled,
            sortedTncData,
            sortedUniquePorts,
            isHidden,
            outputContainer, 
            displayedGraphData, 
            tooltip,        
            showTooltip,    
            hideTooltip
        };
    }
};

createApp(App).mount('#app'); 