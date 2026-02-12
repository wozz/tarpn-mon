import React, { createContext, useState, useEffect, useRef, useCallback } from 'react';
import { Platform } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { htmlDecode, parseAX25Message } from '../utils/ax25Utils';
import { parseMessageTimestamp, getMinuteKey } from '../utils/timeUtils';
import { DEFAULT_FILTER_STATE } from '../components/FilterBar';
import {
  BATCH_INTERVAL_MS,
  RECONNECT_DELAY_MS,
  INITIAL_MESSAGE_LIMIT,
  LOAD_MORE_LIMIT,
  LOAD_MORE_TIMEOUT_MS,
  STATS_MAX_HISTORY_POINTS,
} from '../constants';

export const AppContext = createContext();
const STORAGE_KEY = '@tarpn_settings';

export const AppProvider = ({ children }) => {
  // --- State ---
  const [logMessages, setLogMessages] = useState([]);
  const [tncData, setTncData] = useState({});
  const [tarpnStatsHistory, setTarpnStatsHistory] = useState({});
  const [linkStats, setLinkStats] = useState(null); // L2 link stats from S command
  const [linkStatsHistory, setLinkStatsHistory] = useState({}); // portNum → [{hourStart, ...}]
  const [neighborStats, setNeighborStats] = useState({}); // "callsign-port" → { dataPoints: [...] }
  const [sessions, setSessions] = useState([]);
  const [filterState, setFilterState] = useState({ ...DEFAULT_FILTER_STATE });
  const [showFilterBar, setShowFilterBar] = useState(false);
  const [showSessionPanel, setShowSessionPanel] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [isSettingsLoaded, setIsSettingsLoaded] = useState(false);

  // Feature flags from server (true = feature available on server)
  const [features, setFeatures] = useState({
      chat: true,  // Default to true until we get server response
      bbs: true,
      node: true,
  });

  // Feature settings from backend (connection credentials, enabled state)
  const [featureSettings, setFeatureSettings] = useState({});

  // Feature status state (dynamic connection states)
  // States: 'disconnected' | 'connecting' | 'connected' | 'disconnecting' | 'error'
  const [featureStatus, setFeatureStatus] = useState({
      chat: { state: 'disconnected', callsign: null, host: null, port: null, error: null, connectedAt: null },
      bbs: { state: 'disconnected', callsign: null, host: null, port: null, error: null, connectedAt: null },
      node: { state: 'disconnected', callsign: null, host: null, port: null, error: null, connectedAt: null },
  });

  // Buffer info from server (for pagination)
  const [bufferInfo, setBufferInfo] = useState({
      minSeq: 0,
      maxSeq: 0,
      count: 0,
      capacity: 5000,
  });

  // Loading state for pagination
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [hasMoreHistory, setHasMoreHistory] = useState(true);

  // Settings
  const [settings, setSettings] = useState({
      host: Platform.OS === 'android' ? '10.0.2.2' : (Platform.OS === 'web' ? window.location.hostname : 'localhost'),
      port: Platform.OS === 'web' ? (window.location.port || '80') : '8212',
      hideUSBRoutes: false,
      autoScroll: true,
      compactLayout: false,
      showTHMessages: false
  });

  const [visiblePorts, setVisiblePorts] = useState([]);
  const [uniquePorts, setUniquePorts] = useState(new Set());

  // Graph Data
  const [messageCountsByMinute, setMessageCountsByMinute] = useState({});

  // Refs for queuing / batching
  const wsRef = useRef(null);
  const reconnectTimeoutRef = useRef(null);
  const incomingLogQueue = useRef([]);
  const incomingTncQueue = useRef([]);
  const incomingStatsQueue = useRef([]);
  const incomingNeighborQueue = useRef([]);
  const lastSeq = useRef(0);
  const minLoadedSeq = useRef(null); // Track oldest loaded message for pagination
  const lastNsRef = useRef({});
  const initialLoadDone = useRef(false);

  // --- Persistence ---
  useEffect(() => {
      const loadSettings = async () => {
          try {
              const jsonValue = await AsyncStorage.getItem(STORAGE_KEY);
              if (jsonValue != null) {
                  const saved = JSON.parse(jsonValue);
                  // Merge saved settings with defaults (handles new keys in future)
                  setSettings(prev => ({ ...prev, ...saved }));
              }
          } catch (e) {
              console.error("Failed to load settings", e);
          } finally {
              setIsSettingsLoaded(true);
          }
      };
      loadSettings();
  }, []);

  useEffect(() => {
      if (isSettingsLoaded) {
          const saveSettings = async () => {
              try {
                  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
              } catch (e) {
                  console.error("Failed to save settings", e);
              }
          };
          saveSettings();
      }
  }, [settings, isSettingsLoaded]);

  // --- Actions ---
  const clearLogs = useCallback(() => {
      setLogMessages([]);
      setMessageCountsByMinute({});
      minLoadedSeq.current = null;
      initialLoadDone.current = false;
  }, []);

  // Connect a feature (chat, bbs, or node) — uses backend-stored settings
  const connectFeature = useCallback((feature) => {
      if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
          console.error("WebSocket not connected");
          return;
      }
      console.log(`Connecting feature: ${feature}`);
      wsRef.current.send(JSON.stringify({
          cmd: 'feature_connect',
          feature,
      }));
  }, []);

  // Disconnect a feature
  const disconnectFeature = useCallback((feature) => {
      if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
          console.error("WebSocket not connected");
          return;
      }
      console.log(`Disconnecting feature: ${feature}`);
      wsRef.current.send(JSON.stringify({
          cmd: 'feature_disconnect',
          feature,
      }));
  }, []);

  // Request feature status update
  const refreshFeatureStatus = useCallback(() => {
      if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
          return;
      }
      wsRef.current.send(JSON.stringify({ cmd: 'feature_status' }));
  }, []);

  // Update feature settings on the backend (saves to config and optionally connects/disconnects)
  const updateFeatureSettings = useCallback((feature, newSettings) => {
      if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
          console.error("WebSocket not connected");
          return;
      }
      console.log(`Updating settings for feature: ${feature}`, newSettings);
      wsRef.current.send(JSON.stringify({
          cmd: 'update_settings',
          feature,
          settings: newSettings,
      }));
  }, []);

  // Load more history (older messages) for pagination
  const loadMoreHistory = useCallback((limit = LOAD_MORE_LIMIT) => {
      if (isLoadingMore || !hasMoreHistory || !wsRef.current) return;
      if (minLoadedSeq.current === null) return;

      console.log(`Loading more history before seq ${minLoadedSeq.current}`);
      setIsLoadingMore(true);

      wsRef.current.send(JSON.stringify({
          cmd: "load_before",
          before_seq: minLoadedSeq.current,
          limit: limit
      }));

      // The response will come through onmessage and be processed normally
      // We'll set isLoadingMore to false after a timeout or when we receive data
      // For now, use a simple timeout
      setTimeout(() => {
          setIsLoadingMore(false);
      }, LOAD_MORE_TIMEOUT_MS);
  }, [isLoadingMore, hasMoreHistory]);

  // --- WebSocket Logic ---
  const connectWebSocket = useCallback(() => {
    if (!isSettingsLoaded) return; // Wait for settings

    if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
    }
    if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
    }

    const { host, port } = settings;
    let wsUrl = `ws://${host}:${port}/ws`;
    
    console.log(`Connecting to WebSocket: ${wsUrl}`);
    try {
        const ws = new WebSocket(wsUrl);
        wsRef.current = ws;

        ws.onopen = () => {
          console.log("WebSocket connected");
          setIsConnected(true);
          // Server will send 'init' message first with features and buffer info
          // Then we request initial data - use 'latest' for initial load, 'sync' for reconnect
          if (initialLoadDone.current && lastSeq.current > 0) {
            // Reconnecting - sync from where we left off
            ws.send(JSON.stringify({ cmd: "sync", last_seq: lastSeq.current }));
          } else {
            // Initial load - get last messages
            ws.send(JSON.stringify({ cmd: "latest", limit: INITIAL_MESSAGE_LIMIT }));
          }
          // Request latest link stats
          ws.send(JSON.stringify({ cmd: "get_link_stats" }));
        };

        ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);

            // Handle init message from server
            if (data.type === 'init') {
                console.log("Received init from server:", data);
                if (data.features) {
                    setFeatures(data.features);
                }
                if (data.buffer) {
                    setBufferInfo(data.buffer);
                    // Check if there's more history available
                    setHasMoreHistory(data.buffer.count > INITIAL_MESSAGE_LIMIT);
                }
                // Handle feature statuses from init message
                if (data.featureStatuses) {
                    Object.entries(data.featureStatuses).forEach(([feature, status]) => {
                        setFeatureStatus(prev => ({
                            ...prev,
                            [feature]: {
                                state: status.state || 'disconnected',
                                callsign: status.callsign || null,
                                host: status.host || null,
                                port: status.port || null,
                                error: status.error || null,
                                connectedAt: status.connectedAt || null,
                            }
                        }));
                    });
                }
                // Handle feature settings from init message
                if (data.featureSettings) {
                    setFeatureSettings(data.featureSettings);
                }
                // Handle sessions from init message
                if (data.sessions) {
                    setSessions(data.sessions);
                }
                return;
            }

            // Handle settings updates from backend
            if (data.type === 'settings') {
                if (data.features) {
                    setFeatureSettings(data.features);
                }
                return;
            }

            // Handle feature status updates
            if (data.type === 'feature_status') {
                console.log("Received feature_status:", data);
                const feature = data.feature;
                if (feature) {
                    setFeatureStatus(prev => ({
                        ...prev,
                        [feature]: {
                            state: data.state || 'disconnected',
                            callsign: data.callsign || null,
                            host: data.host || null,
                            port: data.port || null,
                            error: data.error || null,
                            connectedAt: data.connectedAt || null,
                        }
                    }));
                }
                return;
            }

            // Handle link stats updates
            if (data.type === 'link_stats') {
                setLinkStats(data);
                // Request history for each port we haven't fetched yet
                if (data.ports && ws.readyState === WebSocket.OPEN) {
                    Object.keys(data.ports).forEach(portNum => {
                        ws.send(JSON.stringify({
                            cmd: 'get_link_stats_history',
                            port_num: parseInt(portNum, 10),
                            hours: 24,
                        }));
                    });
                }
                return;
            }

            // Handle link stats history response
            if (data.type === 'link_stats_history') {
                setLinkStatsHistory(prev => ({
                    ...prev,
                    [data.portNum]: data.data,
                }));
                return;
            }

            // Handle neighbor CQ stats broadcast
            if (data.type === 'neighbor_link_stats') {
                incomingNeighborQueue.current.push(data);
                return;
            }

            // Handle full sessions table (on init or get_sessions)
            if (data.type === 'sessions') {
                setSessions(data.sessions || []);
                return;
            }

            // Handle single session update
            if (data.type === 'session_update') {
                if (data.session) {
                    setSessions(prev => {
                        const idx = prev.findIndex(s => s.id === data.session.id);
                        if (idx >= 0) {
                            const next = [...prev];
                            next[idx] = data.session;
                            return next;
                        }
                        return [...prev, data.session];
                    });
                }
                return;
            }

            // Track sequence numbers
            if (data.seq && data.seq > lastSeq.current) {
                lastSeq.current = data.seq;
            }
            // Track minimum loaded sequence for pagination
            if (data.seq && (minLoadedSeq.current === null || data.seq < minLoadedSeq.current)) {
                minLoadedSeq.current = data.seq;
            }

            if (data.type === 'log') {
                // Push to queue, don't setState yet
                incomingLogQueue.current.push(data);
                // Mark initial load as done after receiving first batch
                if (!initialLoadDone.current) {
                    initialLoadDone.current = true;
                }
            } else if (data.type === 'tnc_data') {
                incomingTncQueue.current.push(data);
            } else if (data.type === 'tarpn_stat') {
                incomingStatsQueue.current.push(data);
            }
          } catch (e) {
            console.error("JSON Parse Error", e);
          }
        };

        ws.onerror = (e) => {
          console.log("WebSocket error", e.message);
          setIsConnected(false);
        };

        ws.onclose = () => {
          console.log("WebSocket closed");
          setIsConnected(false);
          reconnectTimeoutRef.current = setTimeout(() => {
              connectWebSocket();
          }, RECONNECT_DELAY_MS);
        };
    } catch (err) {
        console.log("WS Init Error", err);
        reconnectTimeoutRef.current = setTimeout(() => {
            connectWebSocket();
        }, RECONNECT_DELAY_MS);
    }
  }, [settings.host, settings.port, isSettingsLoaded]);

  useEffect(() => {
    connectWebSocket();
    return () => {
      if (wsRef.current) wsRef.current.close();
      if (reconnectTimeoutRef.current) clearTimeout(reconnectTimeoutRef.current);
    };
  }, [connectWebSocket]);

  // --- Batch Processing Loop ---
  useEffect(() => {
    const processBatch = () => {
        // 1. Process TNC Data
        if (incomingTncQueue.current.length > 0) {
            const tncUpdates = {};
            const newPorts = new Set();
            
            incomingTncQueue.current.forEach(data => {
                tncUpdates[data.portNum] = data.data;
                if (data.portNum) newPorts.add(String(data.portNum));
            });
            incomingTncQueue.current = []; // Clear queue

            setTncData(prev => ({ ...prev, ...tncUpdates }));
            
            // Check for new ports
            setUniquePorts(prev => {
                let changed = false;
                newPorts.forEach(p => {
                    if (!prev.has(p)) {
                        prev.add(p);
                        changed = true;
                    }
                });
                if (changed) {
                    const newSet = new Set(prev); // Trigger re-render
                    // Auto-enable new ports
                    const newPortsArr = Array.from(newPorts).filter(p => !visiblePorts.includes(p));
                    if (newPortsArr.length > 0) {
                         setTimeout(() => {
                            setVisiblePorts(curr => [...curr, ...newPortsArr]);
                         }, 0);
                    }
                    return newSet;
                }
                return prev;
            });
        }

        // 2. Process TARPN Stats
        if (incomingStatsQueue.current.length > 0) {
            const statsToProcess = incomingStatsQueue.current;
            incomingStatsQueue.current = [];

            setTarpnStatsHistory(prev => {
                const newHistory = { ...prev };
                statsToProcess.forEach(msg => {
                    // msg.data contains { callsign, tx, ret, buf }
                    // msg.port contains port
                    const key = `${msg.port}-${msg.data.callsign}`;
                    if (!newHistory[key]) {
                        newHistory[key] = {
                            port: msg.port,
                            callsign: msg.data.callsign,
                            dataPoints: []
                        };
                    }
                    // Add timestamp to data point
                    const dataPoint = {
                        ...msg.data,
                        timestamp: msg.timestamp,
                        utcDate: parseMessageTimestamp(msg.timestamp)
                    };
                    newHistory[key].dataPoints.push(dataPoint);
                    
                    // Limit size
                    if (newHistory[key].dataPoints.length > STATS_MAX_HISTORY_POINTS) {
                        newHistory[key].dataPoints.shift();
                    }
                });
                return newHistory;
            });
        }

        // 3. Process Neighbor Stats
        if (incomingNeighborQueue.current.length > 0) {
            const neighborsToProcess = incomingNeighborQueue.current;
            incomingNeighborQueue.current = [];

            setNeighborStats(prev => {
                const newStats = { ...prev };
                neighborsToProcess.forEach(msg => {
                    const key = `${msg.callsign}-${msg.reportedPort}`;
                    if (!newStats[key]) {
                        newStats[key] = {
                            callsign: msg.callsign,
                            reportedPort: msg.reportedPort,
                            rxPort: msg.rxPort,
                            dataPoints: [],
                        };
                    }
                    newStats[key].rxPort = msg.rxPort; // Update with latest rx port
                    newStats[key].dataPoints.push({
                        l2Rxed: msg.l2Rxed,
                        l2Sent: msg.l2Sent,
                        l2Timeouts: msg.l2Timeouts,
                        rejRxed: msg.rejRxed,
                        rxCrcErrors: msg.rxCrcErrors,
                        abandoned: msg.abandoned,
                        activeTxPct: msg.activeTxPct,
                        activeBusyPct: msg.activeBusyPct,
                        timestamp: msg.timestamp,
                    });
                    if (newStats[key].dataPoints.length > STATS_MAX_HISTORY_POINTS) {
                        newStats[key].dataPoints.shift();
                    }
                });
                return newStats;
            });
        }

        // 4. Process Logs
        if (incomingLogQueue.current.length > 0) {
            const logsToProcess = incomingLogQueue.current; // Grab ref
            incomingLogQueue.current = []; // Clear ref immediately

            const processedLogs = logsToProcess.map(data => {
                const msgObject = { ...data };
                msgObject.id = data.seq; // Use server sequence number as unique ID
                msgObject.utcDate = parseMessageTimestamp(data.timestamp);
                
                if (msgObject.utcDate) {
                    msgObject.displayTimestamp = msgObject.utcDate.toLocaleTimeString('en-US', { hour12: false });
                } else {
                    msgObject.displayTimestamp = data.timestamp;
                }

                // Parsing Logic
                let stringToParseForAX25 = "";
                if (msgObject.route && msgObject.message) {
                    if (msgObject.message.includes(">") && msgObject.message.match(/^[A-Z0-9-]+(?:-[0-9]+)?\s*>/i)) {
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

                    // Retry Detection
                    if (msgObject.ax25Info && msgObject.ax25Info.frameType === "Information (I)" && msgObject.ax25Info.controlDetails && msgObject.ax25Info.controlDetails.ns !== null) {
                        const src = msgObject.ax25Info.source.call;
                        const dst = msgObject.ax25Info.destination.call;
                        const key = `${src}>${dst}`;
                        const currentNs = msgObject.ax25Info.controlDetails.ns;

                        if (lastNsRef.current[key] === currentNs) {
                            msgObject.isRetry = true;
                        }
                        lastNsRef.current[key] = currentNs;
                    }
                }
                return msgObject;
            });

            // Update Graph Stats (Counts)
            const newCounts = {};
            processedLogs.forEach(msg => {
                if (msg.utcDate) {
                    const minuteKey = getMinuteKey(msg.utcDate);
                    if (minuteKey) {
                        newCounts[minuteKey] = (newCounts[minuteKey] || 0) + 1;
                    }
                }
            });

            setMessageCountsByMinute(prev => {
                const nextCounts = { ...prev };
                Object.keys(newCounts).forEach(key => {
                    nextCounts[key] = (nextCounts[key] || 0) + newCounts[key];
                });
                return nextCounts;
            });

            // Update Log State
            setLogMessages(prev => {
                // Check if these are older messages (load_before) or new ones
                // by comparing sequence numbers
                if (prev.length > 0 && processedLogs.length > 0) {
                    const prevMinSeq = Math.min(...prev.map(m => m.seq));
                    const newMaxSeq = Math.max(...processedLogs.map(m => m.seq));

                    if (newMaxSeq < prevMinSeq) {
                        // These are older messages, prepend them
                        return [...processedLogs, ...prev];
                    }
                }
                // Normal case: append new messages
                return [...prev, ...processedLogs];
            });

            // Check if we've loaded all available history
            if (processedLogs.length > 0 && bufferInfo.minSeq > 0) {
                const loadedMinSeq = Math.min(...processedLogs.map(m => m.seq));
                if (loadedMinSeq <= bufferInfo.minSeq) {
                    setHasMoreHistory(false);
                }
            }

            // Update Unique Ports from Logs
            const newPortsFromLogs = new Set();
            processedLogs.forEach(msg => {
                if (msg.port) newPortsFromLogs.add(msg.port);
            });

            if (newPortsFromLogs.size > 0) {
                 setUniquePorts(prev => {
                    let changed = false;
                    newPortsFromLogs.forEach(p => {
                        if (!prev.has(p)) {
                            prev.add(p);
                            changed = true;
                        }
                    });
                    if (changed) {
                        const newSet = new Set(prev);
                        const newPortsArr = Array.from(newPortsFromLogs).filter(p => !visiblePorts.includes(p));
                         if (newPortsArr.length > 0) {
                             setTimeout(() => {
                                setVisiblePorts(curr => [...curr, ...newPortsArr]);
                             }, 0);
                        }
                        return newSet;
                    }
                    return prev;
                });
            }
        }
    };

    const intervalId = setInterval(processBatch, BATCH_INTERVAL_MS);
    return () => clearInterval(intervalId);
  }, [visiblePorts]); // Dependency on visiblePorts for the nested update, harmless re-attach

  // --- Context Value ---
  const value = {
      logMessages,
      tncData,
      isConnected,
      settings,
      setSettings,
      visiblePorts,
      setVisiblePorts,
      uniquePorts,
      messageCountsByMinute,
      tarpnStatsHistory,
      linkStats,
      linkStatsHistory,
      neighborStats,
      clearLogs,
      // Feature flags
      features,
      // Feature status and connection management
      featureStatus,
      featureSettings,
      connectFeature,
      disconnectFeature,
      refreshFeatureStatus,
      updateFeatureSettings,
      // Pagination
      loadMoreHistory,
      isLoadingMore,
      hasMoreHistory,
      bufferInfo,
      // Sessions & Filtering
      sessions,
      filterState,
      setFilterState,
      showFilterBar,
      setShowFilterBar,
      showSessionPanel,
      setShowSessionPanel,
  };

  return (
    <AppContext.Provider value={value}>
      {children}
    </AppContext.Provider>
  );
};