const output = document.getElementById('output');
const tncDataOutput = document.getElementById('tncData');
const highlightToggle = document.getElementById('toggleHighlight');
const websocket = new WebSocket(`ws://${window.location.host}/ws`);

document.addEventListener('DOMContentLoaded', function () {
  let highlightingEnabled = false;
  highlightToggle.addEventListener('change', function(event) {
    highlightingEnabled = event.target.checked;
  });
  output.addEventListener('mouseover', function(event) {
    if (!highlightingEnabled) return;
    const target = event.target.closest('.logline');
    if (target) {
      const routeValue = target.getAttribute('route');
      document.querySelectorAll('.logline').forEach(line => {
        if (line.getAttribute('route') === routeValue) {
          line.classList.add('highlight');
        }
      });
    }
  });
  output.addEventListener('mouseout', function(event) {
    if (!highlightingEnabled) return;
    const target = event.target.closest('.logline');
    if (target) {
      const routeValue = target.getAttribute('route');
      document.querySelectorAll('.logline').forEach(line => {
        if (line.getAttribute('route') === routeValue) {
          line.classList.remove('highlight');
        }
      });
    }
  });
});

websocket.onopen = () => {
    console.log('WebSocket connection established.');
};

websocket.onmessage = (event) => {
  websocket.onmessage = (event) => {
    if (event.data.startsWith("TNC_DATA:")) {
        // Parse the JSON data
        const jsonData = JSON.parse(event.data.substring(9)); // Remove "TNC_DATA:" prefix

        // Clear previous TNC data
        tncDataOutput.innerHTML = '';

        // Create a table for TNC data
        const table = document.createElement('table');

        // Add two rows to the table initially
        const headerRow = table.insertRow();
        const valueRow = table.insertRow();

        // Function to add key or value to their respective rows
        const addData = (key, value) => {
            const keyCell = headerRow.insertCell();
            const valueCell = valueRow.insertCell();

            keyCell.textContent = key;
            valueCell.textContent = value;
        };

        // Data keys and values extracted from jsonData
        const dataKeysAndValues = [
            ['Firmware Version', jsonData.firmwareVersion],
            ['KAUP8R', jsonData.kaup8r],
            ['Uptime (ms)', jsonData.uptimeMillis],
            ['Board ID', jsonData.boardId],
            ['Switch Positions', jsonData.switchPositions],
            ['Config Mode', jsonData.configMode],
            ['AX.25 Received Packets', jsonData.ax25ReceivedPackets],
            ['IL2P Correctable Packets', jsonData.il2pCorrectablePackets],
            ['IL2P Uncorrectable Packets', jsonData.il2pUncorrectablePackets],
            ['Transmit Packets', jsonData.transmitPackets],
            ['Preamble Word Count', jsonData.preambleWordCount],
            ['Main Loop Cycle Count', jsonData.mainLoopCycleCount],
            ['PTT On Time (ms)', jsonData.pttOnTimeMillis],
            ['DCD On Time (ms)', jsonData.dcdOnTimeMillis],
            ['Received Data Bytes', jsonData.receivedDataBytes],
            ['Transmit Data Bytes', jsonData.transmitDataBytes],
            ['FEC Bytes Corrected', jsonData.fecBytesCorrected]
        ];

        // Add data to the table
        dataKeysAndValues.forEach(([key, value]) => {
            addData(key, value);
        });

        // Append the table to the output
        tncDataOutput.appendChild(table);
    } else {
        // Create a new element for the message
        const messageElement = document.createElement('div');
        messageElement.innerHTML = event.data

        // Append the message to the output
        output.appendChild(messageElement);
        output.scrollTop = output.scrollHeight; // Auto-scroll to bottom
    }
  };
};

websocket.onerror = (error) => {
    console.error('WebSocket error:', error);
};

websocket.onclose = () => {
    console.log('WebSocket connection closed.');
};
