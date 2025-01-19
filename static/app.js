const output = document.getElementById('output');
const tncDataBody = document.getElementById('tncDataBody');
const highlightToggle = document.getElementById('toggleHighlight');
const tncDataRows = [];

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

function createWebSocket() {
  const websocket = new WebSocket(`ws://${window.location.host}/ws`);

  websocket.onopen = () => {
    console.log('WebSocket connection established.');
  };

  websocket.onmessage = (event) => {
    if (event.data.startsWith("TNC_DATA:")) {
      const [_, portNumStr, jsonDataStr] = event.data.split(':');
      const portNum = parseInt(portNumStr);
      const jsonData = JSON.parse(jsonDataStr);
      const rowId = `tnc-datarow-${portNum}`;
      const existingRow = document.getElementById(rowId);
      if (existingRow) {
        tncDataRows.forEach((rowObj, index) => {
            if (rowObj.id === rowId) {
                tncDataRows.splice(index, 1);
                break;
            }
        });
        existingRow.remove();
      }

      const row = document.createElement('tr');
      row.id = rowId;

      const addDataCell = (key, value) => {
        const cell = document.createElement('td');
        cell.textContent = key;
        row.appendChild(cell);
        const valueCell = document.createElement('td');
        valueCell.textContent = value;
        row.appendChild(valueCell);
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

      // Add data to the row
      addDataCell('Port Num', portNum);
      dataKeysAndValues.forEach(([key, value]) => {
        addDataCell(key, value);
      });

      tncDataRows.push({ id: rowId, rowElement: row });

      // Sort and append rows to the table
      tncDataRows.sort((a, b) => parseInt(a.id.split('-')[2]) - parseInt(b.id.split('-')[2]));
      tncDataBody.innerHTML = ''; // Clear existing rows
      tncDataRows.forEach(rowObj => {
        tncDataBody.appendChild(rowObj.rowElement);
      });
    } else {
      // Create a new element for the message
      const messageElement = document.createElement('div');
      messageElement.innerHTML = event.data;
      // Append the message to the output
      output.appendChild(messageElement);
      output.scrollTop = output.scrollHeight; // Auto-scroll to bottom
    }
  };

  websocket.onerror = (error) => {
    console.error('WebSocket error:', error);
    websocket.close(); // Close the WebSocket in case of an error
  };

  websocket.onclose = () => {
    console.log('WebSocket connection closed.');
    setTimeout(createWebSocket, 5000); // Attempt to reconnect after 5 seconds
  };
}

createWebSocket();
