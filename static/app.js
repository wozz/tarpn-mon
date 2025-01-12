const output = document.getElementById('output');
const websocket = new WebSocket(`ws://${window.location.host}/ws`);

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

        // Function to add a row to the table
        const addRow = (key, value) => {
            const row = table.insertRow();
            const cell1 = row.insertCell();
            const cell2 = row.insertCell();
            cell1.textContent = key;
            cell2.textContent = value;
        };

        // Add data to the table
        addRow('Firmware Version', jsonData.firmwareVersion);
        addRow('KAUP8R', jsonData.kaup8r);
        addRow('Uptime (ms)', jsonData.uptimeMillis);
        addRow('Board ID', jsonData.boardId);
        addRow('Switch Positions', jsonData.switchPositions);
        addRow('Config Mode', jsonData.configMode);
        addRow('AX.25 Received Packets', jsonData.ax25ReceivedPackets);
        addRow('IL2P Correctable Packets', jsonData.il2pCorrectablePackets);
        addRow('IL2P Uncorrectable Packets', jsonData.il2pUncorrectablePackets);
        addRow('Transmit Packets', jsonData.transmitPackets);
        addRow('Preamble Word Count', jsonData.preambleWordCount);
        addRow('Main Loop Cycle Count', jsonData.mainLoopCycleCount);
        addRow('PTT On Time (ms)', jsonData.pttOnTimeMillis);
        addRow('DCD On Time (ms)', jsonData.dcdOnTimeMillis);
        addRow('Received Data Bytes', jsonData.receivedDataBytes);
        addRow('Transmit Data Bytes', jsonData.transmitDataBytes);
        addRow('FEC Bytes Corrected', jsonData.fecBytesCorrected);

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
