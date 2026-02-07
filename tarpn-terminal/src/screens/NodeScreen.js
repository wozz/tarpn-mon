import React, { useState, useEffect, useRef, useCallback, useContext } from 'react';
import {
    StyleSheet,
    Text,
    View,
    TextInput,
    TouchableOpacity,
    ScrollView,
    KeyboardAvoidingView,
    Platform,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppContext } from '../context/AppContext';

// Quick action buttons for common node commands
const QUICK_ACTIONS = [
    { label: 'Nodes', cmd: 'N' },
    { label: 'Routes', cmd: 'R' },
    { label: 'MH', cmd: 'MH' },
    { label: 'Users', cmd: 'U' },
    { label: 'Links', cmd: 'L' },
    { label: 'Info', cmd: 'I' },
    { label: 'Ports', cmd: 'P' },
    { label: 'Stats', cmd: 'S' },
];

// Terminal output line component
const TerminalLine = React.memo(({ line, isPrompt }) => {
    return (
        <Text style={[styles.terminalLine, isPrompt && styles.promptLine]}>
            {line}
        </Text>
    );
});

export default function NodeScreen() {
    const { settings, connectFeature, disconnectFeature, featureStatus } = useContext(AppContext);
    const [outputLines, setOutputLines] = useState([]);
    const [inputText, setInputText] = useState('');
    const [prompt, setPrompt] = useState('');

    // Derive connection state from featureStatus
    const nodeStatus = featureStatus?.node || { state: 'disconnected' };
    const isConnected = nodeStatus.state === 'connected';
    const isConnecting = nodeStatus.state === 'connecting';
    const [commandHistory, setCommandHistory] = useState([]);
    const [historyIndex, setHistoryIndex] = useState(-1);
    const scrollViewRef = useRef(null);
    const inputRef = useRef(null);
    const wsRef = useRef(null);
    const lastSeqRef = useRef(0);
    const reconnectTimeoutRef = useRef(null);
    const insets = useSafeAreaInsets();

    const connectWebSocket = useCallback(() => {
        if (wsRef.current) {
            wsRef.current.close();
            wsRef.current = null;
        }
        if (reconnectTimeoutRef.current) {
            clearTimeout(reconnectTimeoutRef.current);
            reconnectTimeoutRef.current = null;
        }

        const { host, port } = settings;
        const wsUrl = `ws://${host}:${port}/ws/node`;

        console.log(`Connecting to Node WebSocket: ${wsUrl}`);

        try {
            const ws = new WebSocket(wsUrl);
            wsRef.current = ws;

            ws.onopen = () => {
                console.log("Node WebSocket connected");
                // Request sync of missed messages
                ws.send(JSON.stringify({ cmd: "sync", last_seq: lastSeqRef.current }));
            };

            ws.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);

                    if (data.seq && data.seq > lastSeqRef.current) {
                        lastSeqRef.current = data.seq;
                    }

                    switch (data.type) {
                        case 'node_status':
                            // Connection state managed by featureStatus from AppContext
                            if (data.prompt) {
                                setPrompt(data.prompt);
                            }
                            break;
                        case 'node_output':
                            if (data.lines && data.lines.length > 0) {
                                setOutputLines(prev => [...prev, ...data.lines]);
                            }
                            break;
                        case 'node_prompt':
                            setPrompt(data.prompt);
                            // Add prompt to output
                            if (data.prompt) {
                                setOutputLines(prev => [...prev, data.prompt]);
                            }
                            break;
                        case 'node_error':
                            setOutputLines(prev => [...prev, `ERROR: ${data.error}`]);
                            break;
                    }
                } catch (e) {
                    console.error("Node JSON Parse Error", e);
                }
            };

            ws.onerror = (e) => {
                console.log("Node WebSocket error", e.message);
            };

            ws.onclose = () => {
                console.log("Node WebSocket closed");
                reconnectTimeoutRef.current = setTimeout(() => {
                    connectWebSocket();
                }, 5000);
            };
        } catch (err) {
            console.log("Node WS Init Error", err);
            reconnectTimeoutRef.current = setTimeout(() => {
                connectWebSocket();
            }, 5000);
        }
    }, [settings.host, settings.port]);

    useEffect(() => {
        connectWebSocket();
        return () => {
            if (wsRef.current) wsRef.current.close();
            if (reconnectTimeoutRef.current) clearTimeout(reconnectTimeoutRef.current);
        };
    }, [connectWebSocket]);

    // Auto-scroll to bottom when new output arrives
    useEffect(() => {
        if (scrollViewRef.current) {
            setTimeout(() => {
                scrollViewRef.current?.scrollToEnd({ animated: true });
            }, 100);
        }
    }, [outputLines.length]);

    const sendCommand = useCallback((cmd) => {
        if (!wsRef.current || !isConnected) return;

        const command = cmd || inputText.trim();
        if (!command) return;

        // Add command to output (echo)
        setOutputLines(prev => [...prev, `> ${command}`]);

        // Add to history
        if (command && !commandHistory.includes(command)) {
            setCommandHistory(prev => [...prev.slice(-49), command]); // Keep last 50 commands
        }
        setHistoryIndex(-1);

        // Send command
        wsRef.current.send(JSON.stringify({ cmd: "exec", command }));

        // Clear input and keep focus
        setInputText('');

        // Re-focus the input after a brief delay
        setTimeout(() => {
            inputRef.current?.focus();
        }, 50);
    }, [inputText, isConnected, commandHistory]);

    const handleQuickAction = useCallback((cmd) => {
        sendCommand(cmd);
    }, [sendCommand]);

    const handleConnectDisconnect = useCallback(() => {
        if (isConnected) {
            disconnectFeature('node');
        } else {
            connectFeature('node');
        }
    }, [isConnected, connectFeature, disconnectFeature]);

    const navigateHistory = useCallback((direction) => {
        if (commandHistory.length === 0) return;

        let newIndex;
        if (direction === 'up') {
            // Going up: start from end of history, or go to previous item
            newIndex = historyIndex < 0
                ? commandHistory.length - 1
                : Math.max(0, historyIndex - 1);
        } else {
            // Going down: go to next item, or back to blank (-1)
            if (historyIndex < 0) {
                return; // Already at blank, nothing to do
            }
            newIndex = historyIndex + 1;
            if (newIndex >= commandHistory.length) {
                newIndex = -1; // Past the end, go back to blank
            }
        }

        setHistoryIndex(newIndex);
        if (newIndex >= 0 && newIndex < commandHistory.length) {
            setInputText(commandHistory[newIndex]);
        } else {
            setInputText(''); // Back to blank
        }
    }, [commandHistory, historyIndex]);

    // Handle keyboard events for history navigation (web)
    const handleKeyDown = useCallback((e) => {
        if (e.key === 'ArrowUp') {
            e.preventDefault();
            navigateHistory('up');
        } else if (e.key === 'ArrowDown') {
            e.preventDefault();
            navigateHistory('down');
        }
    }, [navigateHistory]);

    return (
        <KeyboardAvoidingView
            style={styles.container}
            behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
            keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
        >
            <View style={[styles.headerBar, { paddingTop: insets.top + 10 }]}>
                <View style={styles.headerLeft}>
                    <View style={[styles.statusDot,
                        isConnected ? styles.statusConnected :
                        isConnecting ? styles.statusConnecting :
                        styles.statusDisconnected
                    ]} />
                    <Text style={styles.headerTitle}>Node</Text>
                </View>
                <View style={styles.headerRight}>
                    <Text style={styles.promptText} numberOfLines={1}>
                        {prompt || (isConnecting ? 'Connecting...' : isConnected ? 'Connected' : 'Disconnected')}
                    </Text>
                    <TouchableOpacity onPress={handleConnectDisconnect} style={styles.connectButton} disabled={isConnecting}>
                        <Ionicons
                            name={isConnected ? "stop-circle-outline" : "play-circle-outline"}
                            size={20}
                            color={isConnecting ? "#fbbf24" : isConnected ? "#ef4444" : "#4ade80"}
                        />
                    </TouchableOpacity>
                </View>
            </View>

            {/* Quick Actions Bar */}
            <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                style={styles.quickActionsContainer}
                contentContainerStyle={styles.quickActionsContent}
            >
                {QUICK_ACTIONS.map((action) => (
                    <TouchableOpacity
                        key={action.cmd}
                        style={[styles.quickActionButton, !isConnected && styles.quickActionDisabled]}
                        onPress={() => handleQuickAction(action.cmd)}
                        disabled={!isConnected || isConnecting}
                    >
                        <Text style={[styles.quickActionText, !isConnected && styles.quickActionTextDisabled]}>
                            {action.label}
                        </Text>
                    </TouchableOpacity>
                ))}
            </ScrollView>

            {/* Terminal Output */}
            <ScrollView
                ref={scrollViewRef}
                style={styles.terminalContainer}
                contentContainerStyle={styles.terminalContent}
            >
                {outputLines.map((line, index) => (
                    <TerminalLine
                        key={index}
                        line={line}
                        isPrompt={line.includes(' de ') && line.endsWith('>')}
                    />
                ))}
                {outputLines.length === 0 && (
                    <Text style={styles.placeholderText}>
                        {isConnected
                            ? 'Ready. Type a command or use quick actions above.'
                            : isConnecting
                            ? 'Connecting to node...'
                            : 'Press play to connect to node console.'}
                    </Text>
                )}
            </ScrollView>

            {/* Command Input */}
            <View style={[styles.inputContainer, { paddingBottom: Math.max(insets.bottom, 10) }]}>
                <View style={styles.historyButtons}>
                    <TouchableOpacity
                        style={styles.historyButton}
                        onPress={() => navigateHistory('up')}
                        disabled={commandHistory.length === 0}
                    >
                        <Ionicons
                            name="chevron-up"
                            size={18}
                            color={commandHistory.length > 0 ? "#4ade80" : "#666"}
                        />
                    </TouchableOpacity>
                    <TouchableOpacity
                        style={styles.historyButton}
                        onPress={() => navigateHistory('down')}
                        disabled={commandHistory.length === 0}
                    >
                        <Ionicons
                            name="chevron-down"
                            size={18}
                            color={commandHistory.length > 0 ? "#4ade80" : "#666"}
                        />
                    </TouchableOpacity>
                </View>
                <TextInput
                    ref={inputRef}
                    style={styles.textInput}
                    value={inputText}
                    onChangeText={setInputText}
                    placeholder={isConnected ? "Enter command..." : "Not connected"}
                    placeholderTextColor="#666"
                    editable={isConnected}
                    returnKeyType="send"
                    onSubmitEditing={() => sendCommand()}
                    autoCapitalize="characters"
                    autoCorrect={false}
                    blurOnSubmit={false}
                    {...(Platform.OS === 'web' ? { onKeyDown: handleKeyDown } : {})}
                />
                <TouchableOpacity
                    style={[styles.sendButton, (!isConnected || !inputText.trim()) && styles.sendButtonDisabled]}
                    onPress={() => sendCommand()}
                    disabled={!isConnected || !inputText.trim()}
                >
                    <Ionicons name="send" size={20} color={isConnected && inputText.trim() ? "#fff" : "#666"} />
                </TouchableOpacity>
            </View>
        </KeyboardAvoidingView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#1e1e1e',
    },
    headerBar: {
        paddingHorizontal: 15,
        paddingBottom: 10,
        backgroundColor: '#252525',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
    },
    headerLeft: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    statusDot: {
        width: 8,
        height: 8,
        borderRadius: 4,
        marginRight: 8,
    },
    statusConnected: {
        backgroundColor: '#4ade80',
    },
    statusConnecting: {
        backgroundColor: '#fbbf24',
    },
    statusDisconnected: {
        backgroundColor: '#ef4444',
    },
    headerTitle: {
        color: '#fff',
        fontWeight: 'bold',
        fontSize: 16,
    },
    headerRight: {
        flexDirection: 'row',
        alignItems: 'center',
        flex: 1,
        justifyContent: 'flex-end',
    },
    promptText: {
        color: '#888',
        fontSize: 11,
        fontFamily: '"Courier New", Courier, monospace',
        marginRight: 10,
        maxWidth: 150,
    },
    connectButton: {
        padding: 5,
    },
    quickActionsContainer: {
        backgroundColor: '#252525',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
        maxHeight: 44,
    },
    quickActionsContent: {
        paddingHorizontal: 10,
        paddingVertical: 8,
        gap: 8,
        flexDirection: 'row',
    },
    quickActionButton: {
        backgroundColor: '#333',
        paddingHorizontal: 12,
        paddingVertical: 6,
        borderRadius: 4,
        borderWidth: 1,
        borderColor: '#444',
    },
    quickActionDisabled: {
        opacity: 0.5,
    },
    quickActionText: {
        color: '#4ade80',
        fontSize: 12,
        fontWeight: 'bold',
    },
    quickActionTextDisabled: {
        color: '#666',
    },
    terminalContainer: {
        flex: 1,
        backgroundColor: '#0d0d0d',
    },
    terminalContent: {
        padding: 10,
    },
    terminalLine: {
        color: '#ddd',
        fontSize: 12,
        fontFamily: '"Courier New", Courier, monospace',
        lineHeight: 18,
    },
    promptLine: {
        color: '#4ade80',
        fontWeight: 'bold',
    },
    placeholderText: {
        color: '#666',
        fontSize: 12,
        fontStyle: 'italic',
        textAlign: 'center',
        marginTop: 20,
    },
    inputContainer: {
        flexDirection: 'row',
        paddingHorizontal: 10,
        paddingTop: 10,
        backgroundColor: '#252525',
        borderTopWidth: 1,
        borderTopColor: '#333',
        alignItems: 'center',
    },
    historyButtons: {
        flexDirection: 'column',
        marginRight: 8,
    },
    historyButton: {
        padding: 2,
    },
    textInput: {
        flex: 1,
        backgroundColor: '#0d0d0d',
        color: '#4ade80',
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderRadius: 4,
        borderWidth: 1,
        borderColor: '#444',
        fontSize: 14,
        fontFamily: '"Courier New", Courier, monospace',
        marginRight: 10,
    },
    sendButton: {
        backgroundColor: '#4ade80',
        width: 40,
        height: 40,
        borderRadius: 4,
        justifyContent: 'center',
        alignItems: 'center',
    },
    sendButtonDisabled: {
        backgroundColor: '#333',
    },
});
