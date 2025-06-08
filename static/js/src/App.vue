<template>
  <main>
    <h1>TARPN Monitor</h1>
    <div id="output-container" ref="outputContainerRef">
      <div v-if="logMessages.length === 0" class="empty-log-placeholder">Waiting for messages...</div>
      <div v-for="(msg, index) in logMessages" :key="index" class="logline"
           :class="[
               msg.prefix ? 'prefix-' + msg.prefix : '',
               msg.port ? 'port-' + msg.port : '',
               isHidden(msg) ? 'hidden' : '',
               { 'highlight': index === selectedLogIndex }
           ]"
           :data-port="msg.port"
           :data-route="msg.route"
           @click="handleLogLineClick(msg, index, $event)">
        <span class="time">{{ msg.displayTimestamp }}</span>&nbsp;
        <template v-if="msg.raw">
          <span class="raw-message">{{ msg.raw }}</span>
        </template>
        <template v-else>
          <span :class="msg.prefix">{{ msg.prefix }}x Port={{ msg.port }}</span>&nbsp;
          <span class="msg" :style="{ color: msg.routeColor }">{{ msg.route }} <span class="message-content" v-html="msg.message"></span></span>
        </template>
      </div>
    </div>

    <div id="messageRateGraph" class="graph-container">
      <div v-if="!displayedGraphData || displayedGraphData.length === 0 || displayedGraphData.every(bar => bar.count === 0)" class="empty-graph-placeholder">Waiting for data...</div>
      <div v-else v-for="(barData, index) in displayedGraphData" :key="barData.minuteKey || index" class="graph-bar-container">
        <div class="graph-bar" :title="barData.label + ': ' + barData.count + ' message' + (barData.count === 1 ? '' : 's')" :style="{ height: Math.min(100, barData.count) + 'px' }"></div>
      </div>
    </div>

    <h2>TNC Data</h2>
    <table id="tncDataTable">
      <thead>
      <tr>
        <th>Port Num</th>
        <th>Firmware Version</th>
        <th>KAUP8R</th>
        <th>Uptime</th>
        <th>Board ID</th>
        <th>Switch Positions</th>
        <th>Config Mode</th>
        <th>AX.25 Rx</th>
        <th>IL2P Ok</th>
        <th>IL2P Err</th>
        <th>Tx Packets</th>
        <th>Preamble</th>
        <th>Main Loop</th>
        <th>PTT On</th>
        <th>DCD On</th>
        <th>Rx Bytes</th>
        <th>Tx Bytes</th>
        <th>FEC Corrected</th>
      </tr>
      </thead>
      <tbody id="tncDataBody">
      <tr v-if="Object.keys(tncData).length === 0">
        <td :colspan="18" style="text-align: center;">No TNC data received yet.</td>
      </tr>
      <tr v-for="(data, port) in sortedTncData" :key="port">
        <td>{{ port }}</td>
        <td>{{ data.firmwareVersion }}</td>
        <td>{{ data.kaup8r }}</td>
        <td>{{ data.uptime }}</td>
        <td>{{ data.boardId }}</td>
        <td>{{ data.switchPositions }}</td>
        <td>{{ data.configMode }}</td>
        <td>{{ data.ax25ReceivedPackets }}</td>
        <td>{{ data.il2pCorrectablePackets }}</td>
        <td>{{ data.il2pUncorrectablePackets }}</td>
        <td>{{ data.transmitPackets }}</td>
        <td>{{ data.preambleWordCount }}</td>
        <td>{{ data.mainLoopCycleCount }}</td>
        <td>{{ data.pttOnTime }}</td>
        <td>{{ data.dcdOnTime }}</td>
        <td>{{ data.receivedDataBytes }}</td>
        <td>{{ data.transmitDataBytes }}</td>
        <td>{{ data.fecBytesCorrected }}</td>
      </tr>
      </tbody>
    </table>

    <h3>Settings</h3>
    <label for="toggleAutoScroll" title="Enable or disable automatic scrolling of the log output. When enabled, the log will scroll to the newest message.">Auto-scroll:</label>
    <input type="checkbox" id="toggleAutoScroll" v-model="autoScrollEnabled" title="Enable or disable automatic scrolling of the log output. When enabled, the log will scroll to the newest message."><br/>
    <label for="toggleHideUSB" title="Hide messages that are routed from the TNC to the USB interface. Useful for focusing on over-the-air packets.">Hide TNC&gt;USB Packets:</label>
    <input type="checkbox" id="toggleHideUSB" v-model="hideUSBRoutes" title="Hide messages that are routed from the TNC to the USB interface. Useful for focusing on over-the-air packets."><br/>

    <h4>Port Filters</h4>
    <div id="portFiltersContainer" class="port-checkbox-group">
      <span v-if="uniquePorts.size === 0">No ports detected yet.</span>
      <div v-for="port in sortedUniquePorts" :key="port" class="port-checkbox-item">
        <label :for="'port-' + port + '-checkbox'" :title="'Show or hide messages from port ' + port">Port {{ port }}:</label>
        <input type="checkbox" :id="'port-' + port + '-checkbox'" :value="port" v-model="visiblePorts" :title="'Show or hide messages from port ' + port">
      </div>
    </div>
  </main>

  <footer>
    <span id="version-placeholder">Version: {{ version }}</span>
  </footer>

  <!-- AX.25 Tooltip -->
  <div id="ax25-tooltip" class="ax25-tooltip" v-show="tooltip.visible" :style="{ top: tooltip.y + 'px', left: tooltip.x + 'px' }" @click.stop>
    <div v-if="tooltip.data && tooltip.data.source">
      <h4>AX.25 Packet Details</h4>
      <p>
        <strong>From:</strong> {{ tooltip.data.source.call }}{{ tooltip.data.source.ssid ? '-' + tooltip.data.source.ssid : '' }}
        <strong>To:</strong> {{ tooltip.data.destination.call }}{{ tooltip.data.destination.ssid ? '-' + tooltip.data.destination.ssid : '' }}
      </p>
      <p><strong>Frame Type:</strong> {{ tooltip.data.frameType }}</p>
      <p v-if="tooltip.data.frameTypeExplanation"><em>{{ tooltip.data.frameTypeExplanation }}</em></p>

      <template v-if="tooltip.data.controlRaw">
        <p><strong>Control Field:</strong> <code>{{ tooltip.data.controlRaw }}</code></p>
        <p v-if="tooltip.data.controlDetails && tooltip.data.controlDetails.detailsString"><em>Details: {{ tooltip.data.controlDetails.detailsString }}</em></p>
      </template>
      <template v-else>
        <p><em>No standard control field present.</em></p>
      </template>

      <p v-if="tooltip.data.pid">
        <strong>PID:</strong> {{ tooltip.data.pid }}
        <em v-if="tooltip.data.pidExplanation"> ({{ tooltip.data.pidExplanation }})</em>
      </p>
      <p v-if="tooltip.data.protocol"><strong>L3 Protocol:</strong> {{ tooltip.data.protocol }}</p>
      <div v-if="tooltip.data.info && tooltip.data.info.trim() !== '' && tooltip.data.info.trim() !== ':'">
        <p><strong>Information:</strong></p>
        <pre>{{ tooltip.data.info }}</pre>
      </div>
    </div>
    <div v-else>
      <!-- Fallback or placeholder if tooltip.data is not fully populated but tooltip is visible -->
      <p>Parsing AX.25 details...</p>
    </div>
    <button @click="closeTooltip" class="tooltip-close-button">✖</button>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, nextTick, onMounted } from 'vue';
import { htmlDecode, parseAX25Message } from './utils/ax25Utils';
// Import the new time utility functions
import { parseMessageTimestamp, getMinuteKey } from './utils/timeUtils';

const logMessages = ref([]);
const tncData = reactive({}); // Store TNC data by port number
const autoScrollEnabled = ref(true);
const hideUSBRoutes = ref(false);
const uniquePorts = ref(new Set());
const visiblePorts = ref([]); // Array of port numbers that are checked (visible)
const version = ref("N/A");
const tooltipVisible = ref(false); // Indicates if any tooltip is currently shown
const selectedLogIndex = ref(null); // To track the highlighted log line's index
const outputContainerRef = ref(null); // For autoscroll, changed name to avoid conflict with global
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

// Time utility functions are now imported.

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

const displayedGraphData = computed(() => {
    return graphMinuteSlots.value.map(slotDate => {
        const minuteKey = getMinuteKey(slotDate); // getMinuteKey is now imported
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

watch(sortedUniquePorts, (newPorts) => {
    newPorts.forEach(port => {
        if (!visiblePorts.value.includes(port)) {
            visiblePorts.value.push(port);
        }
    });
}, { immediate: true });

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
            const minuteKey = getMinuteKey(utcDate); // getMinuteKey is now imported
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
                msgObject.utcDate = parseMessageTimestamp(data.timestamp); // parseMessageTimestamp is now imported
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
        const container = outputContainerRef.value;
        if (container) {
            container.scrollTop = container.scrollHeight;
        }
    }
}, { deep: true });

let globalClickHandlerForUnfreeze = null;

function closeTooltip() { // Renamed from unfreezeTooltip and simplified
    if (tooltip.visible) {
        tooltip.visible = false;
        tooltipVisible.value = false; // Track general visibility
        selectedLogIndex.value = null; // Clear highlight
        if (globalClickHandlerForUnfreeze) {
            document.removeEventListener('click', globalClickHandlerForUnfreeze, true);
            globalClickHandlerForUnfreeze = null;
        }
    }
}

globalClickHandlerForUnfreeze = function(event) {
    if (!tooltip.visible) return; // Check general visibility
    const tooltipEl = document.getElementById('ax25-tooltip');
    if (tooltipEl && tooltipEl.contains(event.target)) {
        return; // Click was inside the tooltip, do nothing
    }
    closeTooltip(); // Click was outside, close it
};

function handleLogLineClick(msg, index, event) { // Added index parameter
    // If a tooltip is already visible (potentially for another line), close it first.
    // This also clears selectedLogIndex.
    if (tooltip.visible) {
        closeTooltip();
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
        tooltipVisible.value = true; // Mark that a tooltip is now visible
        selectedLogIndex.value = index; // Set highlight for the current line

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
        // Always (re-)add the global click listener when a tooltip is shown
        document.removeEventListener('click', globalClickHandlerForUnfreeze, true); // Remove first to avoid duplicates
        document.addEventListener('click', globalClickHandlerForUnfreeze, true);
    } else {
        closeTooltip(); // If no valid data, ensure it's closed (this also clears highlight)
    }
}

onMounted(() => {
    connectWebSocket();
    fetchVersion();
    updateGraphSlots();
    setInterval(() => {
        updateGraphSlots();
    }, 1000);
});

</script>

<style scoped>
/* Styles specific to App.vue can go here if needed */
/* For example, if you wanted to override something from style.css but only for this component */

/* The main styles are still expected to be in static/style.css and loaded globally */

/* AX.25 Tooltip Styles - moved from style.css */
.ax25-tooltip {
    position: fixed;
    background-color: #2c2c2c; /* Slightly lighter than body */
    border: 1px solid #555;
    padding: 12px;
    border-radius: 6px;
    box-shadow: 3px 3px 8px rgba(0,0,0,0.6);
    z-index: 1000;
    font-family: Arial, sans-serif; /* More readable font for tooltip */
    font-size: 0.85em;
    color: #e0e0e0;
    max-width: 450px;
    line-height: 1.4;
}

.ax25-tooltip h4 {
    margin-top: 0;
    margin-bottom: 8px;
    color: #ffffff;
    font-size: 1.1em;
    border-bottom: 1px solid #444;
    padding-bottom: 5px;
}

.ax25-tooltip p {
    margin: 6px 0;
}

.ax25-tooltip strong {
    color: #ffffff;
}

.ax25-tooltip code {
    background-color: #1e1e1e;
    padding: 2px 5px;
    border-radius: 3px;
    font-family: "Courier New", Courier, monospace;
    color: #c8f0ff;
}

.ax25-tooltip em {
    color: #aaa;
}

.ax25-tooltip pre {
    white-space: pre-wrap;
    word-break: break-all;
    background-color: #1e1e1e;
    padding: 8px;
    border-radius: 4px;
    max-height: 150px;
    overflow-y: auto;
    border: 1px solid #404040;
    color: #d0d0d0;
}

/* Style for the new close button */
.tooltip-close-button {
    position: absolute;
    top: 5px;
    right: 8px;
    background: none;
    border: none;
    font-size: 1.2em;
    color: #aaa;
    cursor: pointer;
    padding: 2px;
    line-height: 1;
}
.tooltip-close-button:hover {
    color: #fff;
}
</style> 