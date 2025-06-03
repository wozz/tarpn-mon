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
        const outputContainer = ref(null); // For autoscroll
        const messageCountsByMinute = reactive({}); // Key: UTC minute string, Value: count
        const graphMinuteSlots = ref([]); // Array of Date objects for the last 60 minutes (slots)

        const graphUpdateQueue = ref([]); // Stores utcDate objects of new messages for graph processing

        const tncDataUpdateQueue = ref([]); // Stores incoming TNC data objects for batch processing

        const logMessageQueue = ref([]); // Stores incoming log message objects for batch processing

        // Helper to parse "HH:MM:SS" (UTC) and return a Date object
        function parseMessageTimestamp(timestampStr) {
            if (typeof timestampStr !== 'string' || !/^\d{2}:\d{2}:\d{2}$/.test(timestampStr)) {
                // User's fix for regex was: !/^\d{2}:\d{2}:\d{2}$/
                // console.log("Invalid timestamp format:", timestampStr, typeof timestampStr); // Keep user's console.log if intended for debugging
                return null; // Invalid format
            }
            const parts = timestampStr.split(':');
            const hours = parseInt(parts[0], 10);
            const minutes = parseInt(parts[1], 10);
            const seconds = parseInt(parts[2], 10);

            const now = new Date(); // Current local date, to get current year/month/day in UTC
            // Construct a Date object using UTC setters
            const msgUtcDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hours, minutes, seconds));

            // Heuristic for messages from the previous UTC day
            // If msgUtcDate is more than 1 hour in the future from current UTC time, assume it's from yesterday (UTC)
            if (msgUtcDate.getTime() > Date.now() + 60 * 60 * 1000) {
                // console.log("msgDate (UTC) is in the future, adjusting to previous UTC day:", msgUtcDate); // Keep user's console.log
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
            keyDate.setUTCSeconds(0, 0); // Normalize to the start of the minute
            return keyDate.toISOString(); // e.g., "2023-10-27T14:35:00.000Z"
        }

        // Computed property to prepare data for graph rendering
        const displayedGraphData = computed(() => {
            return graphMinuteSlots.value.map(slotDate => {
                const minuteKey = getMinuteKey(slotDate);
                const count = messageCountsByMinute[minuteKey] || 0;
                const label = slotDate.toLocaleTimeString('en-US', {
                    hour: '2-digit',
                    minute: '2-digit',
                    hour12: false
                });
                return { label, count, minuteKey }; // minuteKey for debugging or future use
            });
        });

        function updateGraphSlots() {
            const now = new Date();
            const newSlots = [];
            for (let i = 59; i >= 0; i--) {
                const slotDate = new Date(now.getTime() - i * 60 * 1000);
                slotDate.setUTCSeconds(0, 0); // Align to the start of the minute
                newSlots.push(slotDate);
            }
            graphMinuteSlots.value = newSlots;
        }

        // Function to populate messageCountsByMinute from existing logMessages (e.g., on load)
        function processHistoricalMessagesForGraph() {
            logMessages.value.forEach(msg => {
                if (msg.utcDate) {
                    const minuteKey = getMinuteKey(msg.utcDate);
                    if (minuteKey) {
                        messageCountsByMinute[minuteKey] = (messageCountsByMinute[minuteKey] || 0) + 1;
                    }
                }
            });
            updateGraphSlots(); // Ensure slots are also up-to-date
        }

        // Computed property for sorted TNC data
        const sortedTncData = computed(() => {
            return Object.keys(tncData)
                .sort((a, b) => parseInt(a) - parseInt(b))
                .reduce((obj, key) => {
                    obj[key] = tncData[key];
                    return obj;
                }, {});
        });

        // Computed property for sorted unique ports for display in checkboxes
        const sortedUniquePorts = computed(() => {
            return Array.from(uniquePorts.value).sort((a, b) => parseInt(a) - parseInt(b));
        });
        
        // Watch for new ports and add them to visiblePorts by default
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
                if (utcDate) { // Ensure utcDate is valid
                    const minuteKey = getMinuteKey(utcDate);
                    if (minuteKey) {
                        messageCountsByMinute[minuteKey] = (messageCountsByMinute[minuteKey] || 0) + 1;
                    }
                }
            });
            graphUpdateQueue.value = []; // Clear the queue after processing
        }

        const scheduleGraphUpdate = createDebouncer(processGraphUpdateQueue, 100);

        function processTncDataUpdateQueue() {
            if (tncDataUpdateQueue.value.length === 0) return;

            tncDataUpdateQueue.value.forEach(data => {
                tncData[data.portNum] = data.data; // Directly assign, reactivity handles the rest
                if (!uniquePorts.value.has(String(data.portNum))) {
                    uniquePorts.value.add(String(data.portNum));
                }
            });
            tncDataUpdateQueue.value = []; // Clear the queue after processing
        }

        const scheduleTncDataUpdate = createDebouncer(processTncDataUpdateQueue, 100);

        function processLogMessageQueue() {
            if (logMessageQueue.value.length === 0) return;

            const messagesToAdd = logMessageQueue.value;
            logMessages.value.push(...messagesToAdd); // Add all queued messages

            messagesToAdd.forEach(msg => {
                if (msg.port && !uniquePorts.value.has(msg.port)) {
                    uniquePorts.value.add(msg.port);
                }
            });

            logMessageQueue.value = []; // Clear the queue
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
                        const msgObject = { ...data }; // Clone to avoid modifying original if it's reused
                        msgObject.utcDate = parseMessageTimestamp(data.timestamp);
                        if (msgObject.utcDate) {
                            msgObject.displayTimestamp = msgObject.utcDate.toLocaleTimeString('en-US', { hour12: false });
                            // Update graph data - queue for batched processing
                            // const minuteKey = getMinuteKey(msgObject.utcDate);
                            // if (minuteKey) {
                            //     messageCountsByMinute[minuteKey] = (messageCountsByMinute[minuteKey] || 0) + 1;
                            // }
                            graphUpdateQueue.value.push(msgObject.utcDate);
                            scheduleGraphUpdate();
                        } else {
                            msgObject.displayTimestamp = data.timestamp; // Fallback to raw timestamp
                        }
                        // logMessages.value.push(msgObject);
                        // if (data.port && !uniquePorts.value.has(data.port)) {
                        //     uniquePorts.value.add(data.port);
                        // }
                        logMessageQueue.value.push(msgObject);
                        scheduleLogMessageUpdate();
                    } else if (data.type === 'tnc_data') {
                        // tncData[data.portNum] = data.data; // Directly assign, reactivity handles the rest
                        //  if (!uniquePorts.value.has(String(data.portNum))) {
                        //     uniquePorts.value.add(String(data.portNum));
                        // }
                        tncDataUpdateQueue.value.push(data);
                        scheduleTncDataUpdate();
                    }
                } catch (e) {
                    console.error("Error parsing incoming JSON data:", e, event.data);
                    // Fallback for non-JSON messages if any are expected
                    logMessages.value.push({ type: 'log', raw: event.data, timestamp: new Date().toLocaleTimeString('en-US', { hour12: false }) });
                }
            };

            socket.onerror = (error) => {
                console.error("WebSocket Error:", error);
                // Add a message to the log about the error
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
                setTimeout(connectWebSocket, 5000); // Reconnect after 5 seconds
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

        // Auto-scroll logic
        watch(logMessages, async () => {
            if (autoScrollEnabled.value) {
                await nextTick(); // Wait for DOM update
                const container = document.getElementById('output-container'); // Re-query in case it wasn't there before
                if (container) {
                    container.scrollTop = container.scrollHeight;
                }
            }
        }, { deep: true });

        // Initial actions
        connectWebSocket();
        fetchVersion();
        updateGraphSlots(); // Initial setup of graph slots

        // Periodic timer to slide the graph window and update current minute
        setInterval(() => {
            updateGraphSlots();
            // Optional: Prune very old entries from messageCountsByMinute here if it becomes an issue
        }, 1000); // Update every second for a responsive current minute bar and smooth slide

        return { // Expose to template
            logMessages,
            tncData,
            autoScrollEnabled,
            hideUSBRoutes,
            uniquePorts,
            visiblePorts,
            version,
            sortedTncData,
            sortedUniquePorts,
            isHidden,
            outputContainer, // For potential direct manipulation if needed, though id-based query is used now
            displayedGraphData // New data for graph
        };
    }
};

createApp(App).mount('#app'); 