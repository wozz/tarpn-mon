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

        function connectWebSocket() {
            const socket = new WebSocket(`ws://${window.location.host}/ws`);

            socket.onopen = () => {
                console.log("WebSocket connection established");
            };

            socket.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    if (data.type === 'log') {
                        logMessages.value.push(data);
                        if (data.port && !uniquePorts.value.has(data.port)) {
                            uniquePorts.value.add(data.port);
                        }
                    } else if (data.type === 'tnc_data') {
                        tncData[data.portNum] = data.data; // Directly assign, reactivity handles the rest
                         if (!uniquePorts.value.has(String(data.portNum))) {
                            uniquePorts.value.add(String(data.portNum));
                        }
                    }
                } catch (e) {
                    console.error("Error parsing incoming JSON data:", e, event.data);
                    // Fallback for non-JSON messages if any are expected
                    logMessages.value.push({ type: 'log', raw: event.data, timestamp: new Date().toLocaleTimeString() });
                }
            };

            socket.onerror = (error) => {
                console.error("WebSocket Error:", error);
                // Add a message to the log about the error
                 logMessages.value.push({ 
                    type: 'log', 
                    raw: `WebSocket Error: ${error.message || 'Connection failed'}`,
                    timestamp: new Date().toLocaleTimeString(), 
                    isError: true 
                });
            };

            socket.onclose = () => {
                console.log("WebSocket connection closed. Attempting to reconnect...");
                 logMessages.value.push({ 
                    type: 'log', 
                    raw: 'WebSocket connection closed. Attempting to reconnect...',
                    timestamp: new Date().toLocaleTimeString(), 
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
            outputContainer // For potential direct manipulation if needed, though id-based query is used now
        };
    }
};

createApp(App).mount('#app'); 