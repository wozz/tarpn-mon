import React, { useState, useEffect, useRef, useCallback, useContext, useMemo } from 'react';
import {
    StyleSheet,
    Text,
    View,
    TextInput,
    TouchableOpacity,
    KeyboardAvoidingView,
    Platform,
    ActivityIndicator,
    Modal,
    Alert,
} from 'react-native';
import { FlashList } from '@shopify/flash-list';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
// AsyncStorage no longer needed — credentials managed by backend
import { AppContext } from '../context/AppContext';
import { hashCallsign } from '../utils/colorUtils';

// Feature credentials are now managed by the backend settings system

const getStatusColor = (status) => {
    switch (status) {
        case 'ACT': return '#4ade80'; // green
        case 'IDL': return '#888';    // gray
        case 'AFK': return '#f59e0b'; // amber
        case 'BBS': return '#60a5fa'; // blue
        default:    return '#666';
    }
};

// Message component
const ChatMessageRow = React.memo(({ item }) => {
    const getMessageStyle = () => {
        switch (item.type) {
            case 'chat_join':
                return styles.systemMessage;
            case 'chat_leave':
                return styles.systemMessage;
            case 'chat_topic':
                return styles.systemMessage;
            case 'chat_status':
                return styles.statusMessage;
            case 'chat_error':
                return styles.errorMessage;
            case 'chat_th':
                return styles.thMessage;
            default:
                return null;
        }
    };

    const renderContent = () => {
        if (item.type === 'chat_status') {
            return (
                <Text style={[styles.messageText, styles.statusText]}>
                    {item.connected ? 'Connected to chat server' : 'Disconnected from chat server'}
                </Text>
            );
        }

        if (item.type === 'chat_join' || item.type === 'chat_leave' || item.type === 'chat_topic') {
            return (
                <View style={styles.systemMessageContent}>
                    {item.timestamp ? <Text style={styles.timestamp}>{item.timestamp}</Text> : null}
                    <Text style={[styles.messageText, styles.systemText]}>
                        *** {item.message}
                    </Text>
                </View>
            );
        }

        if (item.type === 'chat_error') {
            return (
                <Text style={[styles.messageText, styles.errorText]}>
                    Error: {item.message}
                </Text>
            );
        }

        if (item.type === 'chat_th') {
            return (
                <View style={styles.systemMessageContent}>
                    {item.timestamp ? <Text style={styles.timestamp}>{item.timestamp}</Text> : null}
                    <Text style={[styles.messageText, styles.thText]}>
                        [$TH] {item.from}: {item.message}
                    </Text>
                </View>
            );
        }

        // Regular chat message
        const callsignColor = item.from ? hashCallsign(item.from) : null;
        return (
            <View style={styles.chatMessageContent}>
                <Text style={styles.timestamp}>{item.timestamp}</Text>
                {item.from ? (
                    <>
                        <Text style={[styles.callsign, { color: callsignColor }]}>{item.from}</Text>
                        {item.fromName && (
                            <Text style={styles.userName}> {item.fromName}</Text>
                        )}
                        <Text style={styles.separator}> : </Text>
                    </>
                ) : null}
                <Text style={styles.messageText}>{item.message}</Text>
            </View>
        );
    };

    return (
        <View style={[styles.messageRow, getMessageStyle()]}>
            {renderContent()}
        </View>
    );
});

export default function ChatScreen() {
    const { settings, setSettings, connectFeature, disconnectFeature, featureStatus } = useContext(AppContext);
    const [messages, setMessages] = useState([]);
    const [inputText, setInputText] = useState('');
    const [users, setUsers] = useState([]);
    const [showUserList, setShowUserList] = useState(false);
    const [isLoadingMore, setIsLoadingMore] = useState(false);
    const [hasMoreHistory, setHasMoreHistory] = useState(true);
    const [bufferInfo, setBufferInfo] = useState({ minSeq: 0, maxSeq: 0, count: 0 });

    // Settings modal state
    const [showSettings, setShowSettings] = useState(false);
    const [chatName, setChatName] = useState('');
    const [chatQTH, setChatQTH] = useState('');
    const [chatTopic, setChatTopic] = useState('General');

    const flatListRef = useRef(null);
    const wsRef = useRef(null);
    const inputRef = useRef(null);
    const lastSeqRef = useRef(0);
    const minLoadedSeqRef = useRef(null);
    const reconnectTimeoutRef = useRef(null);
    const initialLoadDone = useRef(false);
    const seenSeqsRef = useRef(new Set());
    const insets = useSafeAreaInsets();

    // Derive connection state from featureStatus
    const chatStatus = featureStatus?.chat || { state: 'disconnected' };
    const isConnected = chatStatus.state === 'connected';
    const isConnecting = chatStatus.state === 'connecting';

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
        const wsUrl = `ws://${host}:${port}/ws/chat`;

        console.log(`Connecting to Chat WebSocket: ${wsUrl}`);

        try {
            const ws = new WebSocket(wsUrl);
            wsRef.current = ws;

            ws.onopen = () => {
                console.log("Chat WebSocket connected");
                // Check WebSocket is ready before sending
                if (ws.readyState === WebSocket.OPEN) {
                    if (initialLoadDone.current && lastSeqRef.current > 0) {
                        // Reconnecting - sync from where we left off
                        ws.send(JSON.stringify({ cmd: "sync", last_seq: lastSeqRef.current }));
                    } else {
                        // Initial load - get last 200 messages
                        ws.send(JSON.stringify({ cmd: "latest", limit: 200 }));
                    }
                    // Request user list and current settings
                    ws.send(JSON.stringify({ cmd: "users" }));
                    ws.send(JSON.stringify({ cmd: "get_settings" }));
                }
            };

            ws.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);

                    // Handle init message with buffer info
                    if (data.type === 'chat_init') {
                        console.log("Chat init received:", data);
                        if (data.buffer) {
                            setBufferInfo(data.buffer);
                            setHasMoreHistory(data.buffer.count > 200);
                        }
                        return;
                    }

                    // Handle load_before completion signal
                    if (data.type === 'load_before_complete') {
                        console.log("Load before complete:", data);
                        setIsLoadingMore(false);
                        setHasMoreHistory(data.hasMore);
                        return;
                    }

                    // Track sequence numbers
                    if (data.seq) {
                        if (data.seq > lastSeqRef.current) {
                            lastSeqRef.current = data.seq;
                        }
                        if (minLoadedSeqRef.current === null || data.seq < minLoadedSeqRef.current) {
                            minLoadedSeqRef.current = data.seq;
                        }
                    }

                    // Handle settings update
                    if (data.type === 'chat_settings') {
                        console.log("Chat settings received:", data);
                        if (data.name !== undefined) setChatName(data.name);
                        if (data.qth !== undefined) setChatQTH(data.qth);
                        if (data.topic !== undefined) setChatTopic(data.topic);
                        return;
                    }

                    // Connection status now managed by featureStatus from AppContext
                    if (data.type === 'chat_status') {
                        // Just log it - actual state comes from featureStatus
                        console.log("Chat status update:", data.connected);
                    } else if (data.type === 'chat_users') {
                        setUsers(data.users || []);
                    } else if (data.type === 'chat_msg' ||
                               data.type === 'chat_join' ||
                               data.type === 'chat_leave' ||
                               data.type === 'chat_topic' ||
                               data.type === 'chat_th' ||
                               data.type === 'chat_error') {
                        if (!initialLoadDone.current) {
                            initialLoadDone.current = true;
                        }
                        setMessages(prev => {
                            // Deduplicate by seq
                            if (data.seq && seenSeqsRef.current.has(data.seq)) {
                                return prev;
                            }
                            if (data.seq) {
                                seenSeqsRef.current.add(data.seq);
                            }

                            const newMsg = { ...data, id: data.seq || Date.now() };

                            // Fast path: seq is higher than last message — append
                            if (prev.length === 0 || !data.seq || data.seq >= prev[prev.length - 1].seq) {
                                return [...prev, newMsg];
                            }

                            // Insert at correct sorted position by seq
                            const idx = prev.findIndex(m => m.seq > data.seq);
                            if (idx === -1) {
                                return [...prev, newMsg];
                            }
                            return [...prev.slice(0, idx), newMsg, ...prev.slice(idx)];
                        });
                        // Request updated user list on join/leave
                        if ((data.type === 'chat_join' || data.type === 'chat_leave') &&
                            ws.readyState === WebSocket.OPEN) {
                            ws.send(JSON.stringify({ cmd: "users" }));
                        }
                    }
                } catch (e) {
                    console.error("Chat JSON Parse Error", e);
                }
            };

            ws.onerror = (e) => {
                console.log("Chat WebSocket error", e.message);
            };

            ws.onclose = () => {
                console.log("Chat WebSocket closed");
                reconnectTimeoutRef.current = setTimeout(() => {
                    connectWebSocket();
                }, 5000);
            };
        } catch (err) {
            console.log("Chat WS Init Error", err);
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

    // Auto-scroll to bottom when new messages arrive
    useEffect(() => {
        if (messages.length > 0 && flatListRef.current) {
            setTimeout(() => {
                flatListRef.current?.scrollToEnd({ animated: true });
            }, 100);
        }
    }, [messages.length]);

    const sendMessage = useCallback(() => {
        if (!inputText.trim() || !wsRef.current) return;
        // Check WebSocket is actually open before sending
        if (wsRef.current.readyState !== WebSocket.OPEN) {
            console.log("Chat WebSocket not ready, skipping send");
            return;
        }

        const text = inputText.trim();
        setInputText('');

        // Check if it's a command
        if (text.startsWith('/')) {
            wsRef.current.send(JSON.stringify({ cmd: "command", message: text }));
        } else {
            wsRef.current.send(JSON.stringify({ cmd: "send", message: text }));
        }

        // Refocus input after sending to allow quick consecutive messages
        setTimeout(() => {
            inputRef.current?.focus();
        }, 50);
    }, [inputText]);

    // Connect/disconnect handlers — backend uses stored settings
    const handleConnect = useCallback(() => {
        connectFeature('chat');
    }, [connectFeature]);

    const handleDisconnect = useCallback(() => {
        disconnectFeature('chat');
    }, [disconnectFeature]);

    const clearMessages = useCallback(() => {
        setMessages([]);
        seenSeqsRef.current.clear();
        minLoadedSeqRef.current = null;
        initialLoadDone.current = false;
        setHasMoreHistory(true);
    }, []);

    // Save name and QTH
    const saveNameAndQTH = useCallback(() => {
        if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
        wsRef.current.send(JSON.stringify({
            cmd: "set_name",
            name: chatName,
            qth: chatQTH
        }));
    }, [chatName, chatQTH]);

    // Save topic
    const saveTopic = useCallback(() => {
        if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
        if (!chatTopic.trim()) return;
        wsRef.current.send(JSON.stringify({
            cmd: "set_topic",
            topic: chatTopic.trim()
        }));
    }, [chatTopic]);

    // Load more history (older messages)
    const loadMoreHistory = useCallback(() => {
        if (isLoadingMore || !hasMoreHistory || !wsRef.current) return;
        if (minLoadedSeqRef.current === null) return;
        if (wsRef.current.readyState !== WebSocket.OPEN) return;

        // Check if we've already reached the beginning of the buffer
        if (bufferInfo.minSeq > 0 && minLoadedSeqRef.current <= bufferInfo.minSeq) {
            console.log('Already at beginning of chat history');
            setHasMoreHistory(false);
            return;
        }

        console.log(`Loading more chat history before seq ${minLoadedSeqRef.current}`);
        setIsLoadingMore(true);

        wsRef.current.send(JSON.stringify({
            cmd: "load_before",
            before_seq: minLoadedSeqRef.current,
            limit: 200
        }));

        // Server will send load_before_complete message when done
        // Set a safety timeout in case the message doesn't arrive
        setTimeout(() => {
            setIsLoadingMore(false);
        }, 10000);
    }, [isLoadingMore, hasMoreHistory]);

    // Handle scroll for loading more history
    const handleScroll = useCallback((event) => {
        const { contentOffset } = event.nativeEvent;
        // Check if near top for loading more history
        const paddingToTop = 100;
        if (contentOffset.y < paddingToTop && hasMoreHistory && !isLoadingMore) {
            loadMoreHistory();
        }
    }, [hasMoreHistory, isLoadingMore, loadMoreHistory]);

    // Filter out $TH messages unless the setting is enabled
    const filteredMessages = useMemo(() => messages.filter(msg => {
        if (!settings.showTHMessages && msg.type === 'chat_th') return false;
        return true;
    }), [messages, settings.showTHMessages]);

    const renderItem = useCallback(({ item }) => (
        <ChatMessageRow item={item} />
    ), []);

    return (
        <KeyboardAvoidingView
            style={styles.container}
            behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
            keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
        >
            <View style={[styles.headerBar, { paddingTop: insets.top + 10 }]}>
                <View style={styles.headerLeft}>
                    <View style={[styles.statusDot, isConnected ? styles.statusConnected : styles.statusDisconnected]} />
                    <Text style={styles.headerTitle}>Chat</Text>
                    {isConnecting && (
                        <ActivityIndicator size="small" color="#4ade80" style={{ marginLeft: 8 }} />
                    )}
                </View>
                <View style={styles.headerRight}>
                    <TouchableOpacity
                        onPress={() => setShowUserList(!showUserList)}
                        style={styles.usersButton}
                    >
                        <Ionicons name="people-outline" size={16} color={showUserList ? "#4ade80" : "#aaa"} />
                        <Text style={[styles.usersText, showUserList && styles.usersTextActive]}>
                            {users.length}
                        </Text>
                    </TouchableOpacity>
                    <TouchableOpacity onPress={() => setShowSettings(true)} style={styles.settingsButton}>
                        <Ionicons name="settings-outline" size={16} color="#aaa" />
                    </TouchableOpacity>
                    {isConnected ? (
                        <TouchableOpacity onPress={handleDisconnect} style={styles.connectButton}>
                            <Ionicons name="close-circle-outline" size={20} color="#ef4444" />
                        </TouchableOpacity>
                    ) : (
                        <TouchableOpacity
                            onPress={handleConnect}
                            style={styles.connectButton}
                            disabled={isConnecting}
                        >
                            <Ionicons
                                name="play-circle-outline"
                                size={20}
                                color={isConnecting ? "#666" : "#4ade80"}
                            />
                        </TouchableOpacity>
                    )}
                </View>
            </View>

            <View style={styles.contentContainer}>
                {showUserList && (
                    <View style={styles.userListPanel}>
                        <Text style={styles.userListTitle}>Online Users</Text>
                        {users.length === 0 ? (
                            <Text style={styles.noUsersText}>No users online</Text>
                        ) : (
                            <FlashList
                                data={users}
                                renderItem={({ item }) => (
                                    <View style={styles.userItem}>
                                        <View style={styles.userCallRow}>
                                            <Text style={styles.userCall}>{item.call}</Text>
                                            {item.status ? (
                                                <Text style={[styles.userStatus, { color: getStatusColor(item.status) }]}>
                                                    {item.status}
                                                </Text>
                                            ) : null}
                                        </View>
                                        {item.name && <Text style={styles.userNameInList}>{item.name}</Text>}
                                        <Text style={styles.userNode}>@{item.node}</Text>
                                        {item.topic && <Text style={styles.userTopic}>{item.topic}</Text>}
                                    </View>
                                )}
                                keyExtractor={(item) => `${item.call}@${item.node}`}
                                estimatedItemSize={50}
                            />
                        )}
                    </View>
                )}
                <View style={[styles.messagesContainer, showUserList && styles.messagesContainerWithUsers]}>
                    <FlashList
                        ref={flatListRef}
                        data={filteredMessages}
                        renderItem={renderItem}
                        keyExtractor={(item) => item.id?.toString() || Math.random().toString()}
                        estimatedItemSize={40}
                        contentContainerStyle={{ paddingBottom: 10 }}
                        onScroll={handleScroll}
                        scrollEventThrottle={16}
                        ListHeaderComponent={
                            isLoadingMore ? (
                                <View style={styles.loadingMoreContainer}>
                                    <ActivityIndicator size="small" color="#4ade80" />
                                    <Text style={styles.loadingMoreText}>Loading older messages...</Text>
                                </View>
                            ) : hasMoreHistory && messages.length > 0 ? (
                                <TouchableOpacity
                                    style={styles.loadMoreButton}
                                    onPress={loadMoreHistory}
                                >
                                    <Text style={styles.loadMoreText}>Load older messages</Text>
                                </TouchableOpacity>
                            ) : messages.length > 0 ? (
                                <View style={styles.noMoreContainer}>
                                    <Text style={styles.noMoreText}>Beginning of history</Text>
                                </View>
                            ) : null
                        }
                    />
                </View>
            </View>

            <View style={[styles.inputContainer, { paddingBottom: Math.max(insets.bottom, 10) }]}>
                <TextInput
                    ref={inputRef}
                    style={styles.textInput}
                    value={inputText}
                    onChangeText={setInputText}
                    placeholder={isConnected ? "Type a message..." : "Not connected"}
                    placeholderTextColor="#666"
                    editable={isConnected}
                    returnKeyType="send"
                    onSubmitEditing={sendMessage}
                    blurOnSubmit={false}
                    autoCapitalize="none"
                    autoCorrect={false}
                />
                <TouchableOpacity
                    style={[styles.sendButton, (!isConnected || !inputText.trim()) && styles.sendButtonDisabled]}
                    onPress={sendMessage}
                    disabled={!isConnected || !inputText.trim()}
                >
                    <Ionicons name="send" size={20} color={isConnected && inputText.trim() ? "#fff" : "#666"} />
                </TouchableOpacity>
            </View>

            {/* Settings Modal */}
            <Modal
                visible={showSettings}
                transparent={true}
                animationType="fade"
                onRequestClose={() => setShowSettings(false)}
            >
                <View style={styles.modalOverlay}>
                    <View style={styles.modalContent}>
                        <View style={styles.modalHeader}>
                            <Text style={styles.modalTitle}>Chat Settings</Text>
                            <TouchableOpacity onPress={() => setShowSettings(false)}>
                                <Ionicons name="close" size={24} color="#aaa" />
                            </TouchableOpacity>
                        </View>

                        <View style={styles.settingRow}>
                            <Text style={styles.settingLabel}>Display Name</Text>
                            <TextInput
                                style={styles.settingInput}
                                value={chatName}
                                onChangeText={setChatName}
                                placeholder="Your name"
                                placeholderTextColor="#666"
                                autoCapitalize="words"
                            />
                        </View>

                        <View style={styles.settingRow}>
                            <Text style={styles.settingLabel}>QTH / Location</Text>
                            <TextInput
                                style={styles.settingInput}
                                value={chatQTH}
                                onChangeText={setChatQTH}
                                placeholder="Your location"
                                placeholderTextColor="#666"
                            />
                        </View>

                        <TouchableOpacity
                            style={[styles.saveButton, !isConnected && styles.saveButtonDisabled]}
                            onPress={() => {
                                saveNameAndQTH();
                                setShowSettings(false);
                            }}
                            disabled={!isConnected}
                        >
                            <Text style={styles.saveButtonText}>
                                {isConnected ? 'Save Name & QTH' : 'Connect to save'}
                            </Text>
                        </TouchableOpacity>

                        <View style={styles.settingDivider} />

                        <View style={styles.settingRow}>
                            <Text style={styles.settingLabel}>Current Topic</Text>
                            <TextInput
                                style={styles.settingInput}
                                value={chatTopic}
                                onChangeText={setChatTopic}
                                placeholder="Topic name"
                                placeholderTextColor="#666"
                            />
                        </View>

                        <TouchableOpacity
                            style={[styles.saveButton, !isConnected && styles.saveButtonDisabled]}
                            onPress={() => {
                                saveTopic();
                                setShowSettings(false);
                            }}
                            disabled={!isConnected}
                        >
                            <Text style={styles.saveButtonText}>
                                {isConnected ? 'Change Topic' : 'Connect to change topic'}
                            </Text>
                        </TouchableOpacity>

                        <View style={styles.settingDivider} />

                        <TouchableOpacity
                            style={styles.thToggleRow}
                            onPress={() => setSettings(prev => ({ ...prev, showTHMessages: !prev.showTHMessages }))}
                        >
                            <Ionicons
                                name={settings.showTHMessages ? "checkbox" : "square-outline"}
                                size={20}
                                color={settings.showTHMessages ? "#4ade80" : "#666"}
                            />
                            <View style={styles.thToggleText}>
                                <Text style={styles.settingLabel}>Show TARPN Home status messages</Text>
                                <Text style={styles.thToggleHint}>$TH presence/status updates in chat</Text>
                            </View>
                        </TouchableOpacity>
                    </View>
                </View>
            </Modal>
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
    },
    usersButton: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 5,
        marginRight: 5,
    },
    usersText: {
        color: '#888',
        fontSize: 12,
        marginLeft: 4,
    },
    usersTextActive: {
        color: '#4ade80',
    },
    clearButton: {
        padding: 5,
    },
    connectButton: {
        padding: 5,
        marginLeft: 5,
    },
    contentContainer: {
        flex: 1,
        flexDirection: 'row',
    },
    userListPanel: {
        width: 150,
        backgroundColor: '#252525',
        borderRightWidth: 1,
        borderRightColor: '#333',
        padding: 10,
    },
    userListTitle: {
        color: '#4ade80',
        fontSize: 12,
        fontWeight: 'bold',
        marginBottom: 10,
        textTransform: 'uppercase',
    },
    noUsersText: {
        color: '#666',
        fontSize: 12,
        fontStyle: 'italic',
    },
    userItem: {
        paddingVertical: 6,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333',
    },
    userCall: {
        color: '#4ade80',
        fontSize: 12,
        fontWeight: 'bold',
        fontFamily: '"Courier New", Courier, monospace',
    },
    userNameInList: {
        color: '#aaa',
        fontSize: 11,
    },
    userCallRow: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    userStatus: {
        fontSize: 9,
        fontWeight: 'bold',
        marginLeft: 4,
        paddingHorizontal: 3,
        paddingVertical: 1,
        borderRadius: 2,
        backgroundColor: '#333',
        overflow: 'hidden',
    },
    userNode: {
        color: '#666',
        fontSize: 10,
    },
    userTopic: {
        color: '#888',
        fontSize: 10,
        fontStyle: 'italic',
    },
    messagesContainer: {
        flex: 1,
    },
    messagesContainerWithUsers: {
        // When user list is shown, messages take remaining space
    },
    messageRow: {
        paddingVertical: 4,
        paddingHorizontal: 12,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333',
    },
    chatMessageContent: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        alignItems: 'baseline',
    },
    systemMessageContent: {
        flexDirection: 'row',
        alignItems: 'baseline',
    },
    timestamp: {
        color: '#888',
        fontFamily: '"Courier New", Courier, monospace',
        fontSize: 12,
        marginRight: 8,
    },
    callsign: {
        fontFamily: '"Courier New", Courier, monospace',
        fontSize: 12,
        fontWeight: 'bold',
    },
    userName: {
        color: '#aaa',
        fontSize: 12,
    },
    separator: {
        color: '#666',
        fontSize: 12,
    },
    messageText: {
        color: '#ddd',
        fontSize: 14,
        flex: 1,
    },
    systemMessage: {
        backgroundColor: '#2a2a2a',
    },
    systemText: {
        color: '#888',
        fontStyle: 'italic',
    },
    statusMessage: {
        backgroundColor: '#1a2a1a',
    },
    statusText: {
        color: '#4ade80',
    },
    errorMessage: {
        backgroundColor: '#2a1a1a',
    },
    errorText: {
        color: '#ef4444',
    },
    thMessage: {
        backgroundColor: '#1a1a2a',
    },
    thText: {
        color: '#666',
        fontStyle: 'italic',
        fontSize: 12,
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
    textInput: {
        flex: 1,
        backgroundColor: '#1e1e1e',
        color: '#fff',
        paddingHorizontal: 15,
        paddingVertical: 10,
        borderRadius: 20,
        borderWidth: 1,
        borderColor: '#444',
        fontSize: 14,
        marginRight: 10,
    },
    sendButton: {
        backgroundColor: '#4ade80',
        width: 40,
        height: 40,
        borderRadius: 20,
        justifyContent: 'center',
        alignItems: 'center',
    },
    sendButtonDisabled: {
        backgroundColor: '#333',
    },
    // Loading more / pagination styles
    loadingMoreContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center',
        paddingVertical: 12,
        backgroundColor: '#2a2a2a',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    loadingMoreText: {
        color: '#888',
        marginLeft: 8,
        fontSize: 12,
    },
    loadMoreButton: {
        paddingVertical: 12,
        alignItems: 'center',
        backgroundColor: '#2a2a2a',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    loadMoreText: {
        color: '#4ade80',
        fontSize: 12,
    },
    noMoreContainer: {
        paddingVertical: 8,
        alignItems: 'center',
        backgroundColor: '#252525',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    noMoreText: {
        color: '#666',
        fontSize: 11,
        fontStyle: 'italic',
    },
    // Settings button and modal styles
    settingsButton: {
        padding: 5,
        marginRight: 5,
    },
    modalOverlay: {
        flex: 1,
        backgroundColor: 'rgba(0, 0, 0, 0.7)',
        justifyContent: 'center',
        alignItems: 'center',
        padding: 20,
    },
    modalContent: {
        backgroundColor: '#2a2a2a',
        borderRadius: 12,
        padding: 20,
        width: '100%',
        maxWidth: 400,
        borderWidth: 1,
        borderColor: '#444',
    },
    modalHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 20,
    },
    modalTitle: {
        color: '#fff',
        fontSize: 18,
        fontWeight: 'bold',
    },
    settingRow: {
        marginBottom: 15,
    },
    settingLabel: {
        color: '#aaa',
        fontSize: 12,
        marginBottom: 6,
        textTransform: 'uppercase',
    },
    settingInput: {
        backgroundColor: '#1e1e1e',
        color: '#fff',
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#444',
        fontSize: 14,
    },
    saveButton: {
        backgroundColor: '#4ade80',
        paddingVertical: 12,
        borderRadius: 8,
        alignItems: 'center',
        marginTop: 5,
    },
    saveButtonDisabled: {
        backgroundColor: '#333',
    },
    saveButtonText: {
        color: '#fff',
        fontWeight: 'bold',
        fontSize: 14,
    },
    settingDivider: {
        height: 1,
        backgroundColor: '#444',
        marginVertical: 20,
    },
    thToggleRow: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        paddingVertical: 4,
    },
    thToggleText: {
        marginLeft: 10,
        flex: 1,
    },
    thToggleHint: {
        color: '#666',
        fontSize: 11,
        marginTop: 2,
    },
});
