const output = document.getElementById("output");
const tncDataBody = document.getElementById("tncDataBody");
const autoScrollToggle = document.getElementById("toggleAutoScroll");
const hideUSBToggle = document.getElementById("toggleHideUSB");
const portFiltersContainer = document.getElementById("portFiltersContainer");
const tncDataRows = [];
let autoScrollEnabled = true;
let hideUSBEnabled = false;
const uniquePorts = new Set();
const portVisibility = {};

function extractPortNumber(element) {
  if (!element || !element.classList) {
    return null;
  }
  for (const className of element.classList) {
    if (className.startsWith("port-")) {
      return className.substring(5); // Get the part after "port-"
    }
  }
  return null;
}

function updateMessageVisibility(messageElement) {
  const isUSBMessage = messageElement.classList.contains("route-tnc-usb");
  const messagePort = extractPortNumber(messageElement);
  let shouldBeHidden = false;
  // Check TNC>USB filter
  if (hideUSBEnabled && isUSBMessage) {
    shouldBeHidden = true;
  }
  // Check Port filter (only if not already hidden by USB filter)
  if (!shouldBeHidden && messagePort !== null) {
    // If portVisibility[messagePort] is false, it means this port should be hidden
    if (portVisibility[messagePort] === false) {
      shouldBeHidden = true;
    }
  }
  // Apply or remove the 'hidden' class
  if (shouldBeHidden) {
    messageElement.classList.add("hidden");
  } else {
    messageElement.classList.remove("hidden");
  }
}

function updateAllMessagesVisibility() {
  const allMessages = output.querySelectorAll(".message");
  allMessages.forEach((msg) => updateMessageVisibility(msg));
  if (autoScrollEnabled) {
    output.scrollTop = output.scrollHeight; // Auto-scroll to bottom
  }
}

function renderPortCheckboxes() {
  portFiltersContainer.innerHTML = "";
  if (uniquePorts.size === 0) {
    return;
  }
  const sortedPorts = Array.from(uniquePorts).sort(
    (a, b) => parseInt(a) - parseInt(b)
  );
  sortedPorts.forEach((port) => {
    if (portVisibility[port] === undefined) {
      portVisibility[port] = true;
    }
    const checkboxItem = document.createElement("div");
    checkboxItem.classList.add("port-checkbox-item");
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.id = `port-${port}-checkbox`;
    checkbox.checked = portVisibility[port];

    const label = document.createElement("label");
    label.htmlFor = `port-${port}-checkbox`;
    label.textContent = `Port ${port}:`;

    checkbox.addEventListener("change", (e) => {
      portVisibility[port] = e.target.checked;
      updateAllMessagesVisibility();
    });
    checkboxItem.appendChild(label);
    checkboxItem.appendChild(checkbox);
    portFiltersContainer.appendChild(checkboxItem);
  });
}

document.addEventListener("DOMContentLoaded", function () {
  autoScrollToggle.addEventListener("change", function (event) {
    autoScrollEnabled = event.target.checked;
  });
  hideUSBToggle.addEventListener("change", function (event) {
    hideUSBEnabled = event.target.checked;
    updateAllMessagesVisibility();
  });
});

function createWebSocket() {
  const websocket = new WebSocket(`ws://${window.location.host}/ws`);

  websocket.onopen = () => {
    console.log("WebSocket connection established.");
  };

  websocket.onmessage = (event) => {
    if (event.data.startsWith("TNC_DATA:")) {
      let data = event.data.substring(event.data.indexOf(":") + 1);
      const portNumStr = data.substring(0, data.indexOf(":"));
      const jsonDataStr = data.substring(data.indexOf(":") + 1);
      const portNum = parseInt(portNumStr);
      const jsonData = JSON.parse(jsonDataStr);
      const rowId = `tnc-datarow-${portNum}`;
      const existingRow = document.getElementById(rowId);
      if (existingRow) {
        tncDataRows.forEach((rowObj, index) => {
          if (rowObj.id === rowId) {
            tncDataRows.splice(index, 1);
          }
        });
        existingRow.remove();
      }

      const row = document.createElement("tr");
      row.id = rowId;

      const addDataCell = (key, value) => {
        const valueCell = document.createElement("td");
        valueCell.id = key.replace(" ", "-");
        valueCell.textContent = value;
        row.appendChild(valueCell);
      };

      // Data keys and values extracted from jsonData
      const dataKeysAndValues = [
        ["Firmware Version", jsonData.firmwareVersion],
        ["KAUP8R", jsonData.kaup8r],
        ["Uptime", jsonData.uptime],
        ["Board ID", jsonData.boardId],
        ["Switch Positions", jsonData.switchPositions],
        ["Config Mode", jsonData.configMode],
        ["AX.25 Received Packets", jsonData.ax25ReceivedPackets],
        ["IL2P Correctable Packets", jsonData.il2pCorrectablePackets],
        ["IL2P Uncorrectable Packets", jsonData.il2pUncorrectablePackets],
        ["Transmit Packets", jsonData.transmitPackets],
        ["Preamble Word Count", jsonData.preambleWordCount],
        ["Main Loop Cycle Count", jsonData.mainLoopCycleCount],
        ["PTT On Time", jsonData.pttOnTime],
        ["DCD On Time", jsonData.dcdOnTime],
        ["Received Data Bytes", jsonData.receivedDataBytes],
        ["Transmit Data Bytes", jsonData.transmitDataBytes],
        ["FEC Bytes Corrected", jsonData.fecBytesCorrected],
      ];

      // Add data to the row
      addDataCell("Port Num", portNum);
      dataKeysAndValues.forEach(([key, value]) => {
        addDataCell(key, value);
      });

      tncDataRows.push({ id: rowId, rowElement: row });

      // Sort and append rows to the table
      tncDataRows.sort(
        (a, b) => parseInt(a.id.split("-")[2]) - parseInt(b.id.split("-")[2])
      );
      tncDataBody.innerHTML = ""; // Clear existing rows
      tncDataRows.forEach((rowObj) => {
        tncDataBody.appendChild(rowObj.rowElement);
      });
    } else {
      // Create a new element for the message
      const messageElement = document.createElement("div");
      messageElement.innerHTML = event.data;
      let route = "unknown";
      if (
        messageElement.firstElementChild &&
        messageElement.firstElementChild.hasAttribute("route")
      ) {
        route = messageElement.firstElementChild.getAttribute("route");
      }
      let port = "unknown";
      if (
        messageElement.firstElementChild &&
        messageElement.firstElementChild.hasAttribute("port")
      ) {
        port = messageElement.firstElementChild.getAttribute("port");
      }

      if (!uniquePorts.has(port)) {
        uniquePorts.add(port);
        renderPortCheckboxes();
      }

      messageElement.classList.add("message");
      if (route === "TNC>USB") {
        messageElement.classList.add("route-tnc-usb");
      }
      messageElement.classList.add("port-" + port);

      updateMessageVisibility(messageElement);

      // Append the message to the output
      output.appendChild(messageElement);
      if (autoScrollEnabled) {
        output.scrollTop = output.scrollHeight; // Auto-scroll to bottom
      }
    }
  };

  websocket.onerror = (error) => {
    console.error("WebSocket error:", error);
    websocket.close(); // Close the WebSocket in case of an error
  };

  websocket.onclose = () => {
    console.log("WebSocket connection closed.");
    setTimeout(createWebSocket, 5000); // Attempt to reconnect after 5 seconds
  };
}

createWebSocket();
