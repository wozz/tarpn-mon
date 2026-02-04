import React, { useState, useEffect, useRef, useCallback, useContext } from 'react';
import {
    StyleSheet,
    Text,
    View,
    TextInput,
    TouchableOpacity,
    Modal,
    KeyboardAvoidingView,
    Platform,
    ScrollView,
    ActivityIndicator,
    Alert,
} from 'react-native';
import { FlashList } from '@shopify/flash-list';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppContext } from '../context/AppContext';

// Message type badge colors
const TYPE_COLORS = {
    P: '#4ade80', // Personal - green
    B: '#60a5fa', // Bulletin - blue
    T: '#f59e0b', // Traffic/NTS - amber
};

// Status indicators
const STATUS_INFO = {
    N: { label: 'New', color: '#4ade80' },
    Y: { label: 'Read', color: '#888' },
    F: { label: 'Forwarded', color: '#60a5fa' },
    K: { label: 'Killed', color: '#ef4444' },
    H: { label: 'Held', color: '#f59e0b' },
    D: { label: 'Draft', color: '#888' },
};

// Message list item component
const MessageListItem = React.memo(({ item, onPress }) => {
    const typeColor = TYPE_COLORS[item.type] || '#888';
    const statusInfo = STATUS_INFO[item.status] || { label: item.status, color: '#888' };

    return (
        <TouchableOpacity style={styles.messageItem} onPress={() => onPress(item)}>
            <View style={styles.messageHeader}>
                <View style={styles.messageLeft}>
                    <View style={[styles.typeBadge, { backgroundColor: typeColor }]}>
                        <Text style={styles.typeBadgeText}>{item.type}</Text>
                    </View>
                    <Text style={styles.messageNumber}>#{item.number}</Text>
                    {item.status === 'N' && (
                        <View style={styles.newDot} />
                    )}
                </View>
                <Text style={styles.messageDate}>{item.date}</Text>
            </View>
            <View style={styles.messageBody}>
                <Text style={styles.messageFrom}>
                    {item.type === 'P' ? `${item.from} -> ${item.to}` : item.from}
                </Text>
                <Text style={styles.messageSubject} numberOfLines={1}>{item.subject}</Text>
            </View>
            <View style={styles.messageFooter}>
                <Text style={[styles.statusText, { color: statusInfo.color }]}>{statusInfo.label}</Text>
                <Text style={styles.messageSize}>{item.size} bytes</Text>
            </View>
        </TouchableOpacity>
    );
});

// Message detail modal component
const MessageDetailModal = ({ visible, message, onClose, onDelete, onReply }) => {
    const insets = useSafeAreaInsets();

    if (!message) return null;

    const typeColor = TYPE_COLORS[message.type] || '#888';
    const statusInfo = STATUS_INFO[message.status] || { label: message.status, color: '#888' };

    return (
        <Modal
            animationType="slide"
            transparent={false}
            visible={visible}
            onRequestClose={onClose}
        >
            <View style={[styles.modalContainer, { paddingTop: insets.top }]}>
                <View style={styles.modalHeader}>
                    <TouchableOpacity onPress={onClose} style={styles.modalBackButton}>
                        <Ionicons name="arrow-back" size={24} color="#fff" />
                    </TouchableOpacity>
                    <Text style={styles.modalTitle}>Message #{message.number}</Text>
                    <View style={styles.modalActions}>
                        {onReply && (
                            <TouchableOpacity onPress={onReply} style={styles.modalActionButton}>
                                <Ionicons name="arrow-undo" size={20} color="#4ade80" />
                            </TouchableOpacity>
                        )}
                        {onDelete && (
                            <TouchableOpacity onPress={onDelete} style={styles.modalActionButton}>
                                <Ionicons name="trash-outline" size={20} color="#ef4444" />
                            </TouchableOpacity>
                        )}
                    </View>
                </View>

                <ScrollView style={styles.messageDetailContent}>
                    <View style={styles.messageDetailHeader}>
                        <View style={styles.messageDetailRow}>
                            <Text style={styles.messageDetailLabel}>Type:</Text>
                            <View style={[styles.typeBadge, { backgroundColor: typeColor }]}>
                                <Text style={styles.typeBadgeText}>{message.type}</Text>
                            </View>
                            <Text style={[styles.statusText, { color: statusInfo.color, marginLeft: 10 }]}>
                                {statusInfo.label}
                            </Text>
                        </View>
                        <View style={styles.messageDetailRow}>
                            <Text style={styles.messageDetailLabel}>From:</Text>
                            <Text style={styles.messageDetailValue}>{message.from}</Text>
                        </View>
                        <View style={styles.messageDetailRow}>
                            <Text style={styles.messageDetailLabel}>To:</Text>
                            <Text style={styles.messageDetailValue}>{message.to}</Text>
                        </View>
                        <View style={styles.messageDetailRow}>
                            <Text style={styles.messageDetailLabel}>Date:</Text>
                            <Text style={styles.messageDetailValue}>{message.date}</Text>
                        </View>
                        <View style={styles.messageDetailRow}>
                            <Text style={styles.messageDetailLabel}>Subject:</Text>
                            <Text style={styles.messageDetailValue}>{message.subject}</Text>
                        </View>
                    </View>

                    <View style={styles.messageBodySection}>
                        <Text style={styles.messageBodyText}>{message.body || '(No body)'}</Text>
                    </View>
                </ScrollView>
            </View>
        </Modal>
    );
};

// Compose message modal component
const ComposeModal = ({ visible, onClose, onSend, replyTo }) => {
    const insets = useSafeAreaInsets();
    const [to, setTo] = useState('');
    const [subject, setSubject] = useState('');
    const [body, setBody] = useState('');
    const [isBulletin, setIsBulletin] = useState(false);
    const [sending, setSending] = useState(false);

    useEffect(() => {
        if (replyTo) {
            setTo(replyTo.from);
            setSubject(replyTo.subject?.startsWith('Re:') ? replyTo.subject : `Re: ${replyTo.subject}`);
            setBody(`\n\n--- Original message from ${replyTo.from} ---\n${replyTo.body || ''}`);
            setIsBulletin(false);
        } else {
            setTo('');
            setSubject('');
            setBody('');
            setIsBulletin(false);
        }
    }, [replyTo, visible]);

    const handleSend = async () => {
        if (!to.trim() || !subject.trim()) return;
        setSending(true);
        try {
            await onSend(to.trim().toUpperCase(), subject.trim(), body.trim(), isBulletin);
            onClose();
        } finally {
            setSending(false);
        }
    };

    return (
        <Modal
            animationType="slide"
            transparent={false}
            visible={visible}
            onRequestClose={onClose}
        >
            <KeyboardAvoidingView
                style={[styles.modalContainer, { paddingTop: insets.top }]}
                behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
            >
                <View style={styles.modalHeader}>
                    <TouchableOpacity onPress={onClose} style={styles.modalBackButton}>
                        <Ionicons name="close" size={24} color="#fff" />
                    </TouchableOpacity>
                    <Text style={styles.modalTitle}>
                        {replyTo ? 'Reply' : 'New Message'}
                    </Text>
                    <TouchableOpacity
                        onPress={handleSend}
                        style={[styles.sendHeaderButton, (!to.trim() || !subject.trim() || sending) && styles.sendHeaderButtonDisabled]}
                        disabled={!to.trim() || !subject.trim() || sending}
                    >
                        {sending ? (
                            <ActivityIndicator size="small" color="#4ade80" />
                        ) : (
                            <Text style={styles.sendHeaderButtonText}>Send</Text>
                        )}
                    </TouchableOpacity>
                </View>

                <ScrollView style={styles.composeContent}>
                    <View style={styles.composeField}>
                        <Text style={styles.composeLabel}>To:</Text>
                        <TextInput
                            style={styles.composeInput}
                            value={to}
                            onChangeText={setTo}
                            placeholder="Callsign or bulletin area"
                            placeholderTextColor="#666"
                            autoCapitalize="characters"
                            autoCorrect={false}
                        />
                    </View>

                    <View style={styles.composeField}>
                        <Text style={styles.composeLabel}>Subject:</Text>
                        <TextInput
                            style={styles.composeInput}
                            value={subject}
                            onChangeText={setSubject}
                            placeholder="Subject line"
                            placeholderTextColor="#666"
                            autoCorrect={false}
                        />
                    </View>

                    <TouchableOpacity
                        style={styles.bulletinToggle}
                        onPress={() => setIsBulletin(!isBulletin)}
                    >
                        <Ionicons
                            name={isBulletin ? 'checkbox' : 'square-outline'}
                            size={24}
                            color={isBulletin ? '#4ade80' : '#888'}
                        />
                        <Text style={styles.bulletinToggleText}>Send as Bulletin</Text>
                    </TouchableOpacity>

                    <View style={styles.composeBodyField}>
                        <Text style={styles.composeLabel}>Message:</Text>
                        <TextInput
                            style={styles.composeBodyInput}
                            value={body}
                            onChangeText={setBody}
                            placeholder="Type your message..."
                            placeholderTextColor="#666"
                            multiline
                            textAlignVertical="top"
                        />
                    </View>
                </ScrollView>
            </KeyboardAvoidingView>
        </Modal>
    );
};

// Filter tabs component
const FilterTabs = ({ selected, onSelect }) => {
    const filters = [
        { key: 'LM', label: 'Mine' },
        { key: 'LB', label: 'Bulletins' },
        { key: 'LL 30', label: 'Recent' },
    ];

    return (
        <View style={styles.filterTabs}>
            {filters.map(filter => (
                <TouchableOpacity
                    key={filter.key}
                    style={[styles.filterTab, selected === filter.key && styles.filterTabActive]}
                    onPress={() => onSelect(filter.key)}
                >
                    <Text style={[styles.filterTabText, selected === filter.key && styles.filterTabTextActive]}>
                        {filter.label}
                    </Text>
                </TouchableOpacity>
            ))}
        </View>
    );
};

export default function BBSScreen() {
    const { settings, connectFeature, disconnectFeature, featureStatus } = useContext(AppContext);
    const [messages, setMessages] = useState([]);

    // Derive connection state from featureStatus
    const bbsStatus = featureStatus?.bbs || { state: 'disconnected' };
    const isConnected = bbsStatus.state === 'connected';
    const isConnecting = bbsStatus.state === 'connecting';
    const [inBBSMode, setInBBSMode] = useState(false);
    const [loading, setLoading] = useState(false);
    const [selectedFilter, setSelectedFilter] = useState('LM');
    const [selectedMessage, setSelectedMessage] = useState(null);
    const [showDetail, setShowDetail] = useState(false);
    const [showCompose, setShowCompose] = useState(false);
    const [replyTo, setReplyTo] = useState(null);
    const [error, setError] = useState(null);
    const wsRef = useRef(null);
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
        const wsUrl = `ws://${host}:${port}/ws/bbs`;

        console.log(`Connecting to BBS WebSocket: ${wsUrl}`);

        try {
            const ws = new WebSocket(wsUrl);
            wsRef.current = ws;

            ws.onopen = () => {
                console.log("BBS WebSocket connected");
                // Request status
                ws.send(JSON.stringify({ cmd: "status" }));
            };

            ws.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    console.log("BBS message:", data.type);

                    switch (data.type) {
                        case 'bbs_status':
                            // Connection status now managed by featureStatus from AppContext
                            // Just update inBBSMode from the BBS-specific status
                            setInBBSMode(data.inBBSMode);
                            break;
                        case 'bbs_list':
                            setMessages(data.messages || []);
                            setLoading(false);
                            break;
                        case 'bbs_message':
                            setSelectedMessage(data.message);
                            setShowDetail(true);
                            setLoading(false);
                            break;
                        case 'bbs_sent':
                            setError(null);
                            // Refresh the list after sending
                            refreshMessages();
                            break;
                        case 'bbs_error':
                            setError(data.error);
                            setLoading(false);
                            break;
                    }
                } catch (e) {
                    console.error("BBS JSON Parse Error", e);
                }
            };

            ws.onerror = (e) => {
                console.log("BBS WebSocket error", e.message);
            };

            ws.onclose = () => {
                console.log("BBS WebSocket closed");
                // Connection status managed by featureStatus, just reset BBS mode
                setInBBSMode(false);
                reconnectTimeoutRef.current = setTimeout(() => {
                    connectWebSocket();
                }, 5000);
            };
        } catch (err) {
            console.log("BBS WS Init Error", err);
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

    // When connected, the backend auto-enters BBS mode via initConnection()
    // Just need to set inBBSMode when we get connected
    useEffect(() => {
        if (isConnected) {
            // Backend automatically enters BBS mode, so we can assume we're in BBS mode
            setInBBSMode(true);
        } else {
            setInBBSMode(false);
        }
    }, [isConnected]);

    // Refresh messages when BBS mode is entered or filter changes
    useEffect(() => {
        if (inBBSMode) {
            refreshMessages();
        }
    }, [inBBSMode, selectedFilter]);

    const refreshMessages = useCallback(() => {
        if (!wsRef.current || !inBBSMode) return;
        // Check WebSocket is actually open before sending
        if (wsRef.current.readyState !== WebSocket.OPEN) {
            console.log("BBS WebSocket not ready, skipping refresh");
            return;
        }
        setLoading(true);
        setError(null);
        wsRef.current.send(JSON.stringify({ cmd: "list", listType: selectedFilter }));
    }, [selectedFilter, inBBSMode]);

    const readMessage = useCallback((msgNum) => {
        if (!wsRef.current || !inBBSMode) return;
        if (wsRef.current.readyState !== WebSocket.OPEN) {
            console.log("BBS WebSocket not ready, skipping read");
            return;
        }
        setLoading(true);
        setError(null);
        wsRef.current.send(JSON.stringify({ cmd: "read", number: msgNum }));
    }, [inBBSMode]);

    const deleteMessage = useCallback((msgNum) => {
        if (!wsRef.current || !inBBSMode) return;
        if (wsRef.current.readyState !== WebSocket.OPEN) return;
        wsRef.current.send(JSON.stringify({ cmd: "delete", number: msgNum }));
        setShowDetail(false);
        setSelectedMessage(null);
        // Refresh the list
        setTimeout(() => refreshMessages(), 500);
    }, [inBBSMode, refreshMessages]);

    const sendMessage = useCallback(async (to, subject, body, isBulletin) => {
        if (!wsRef.current || !inBBSMode) return;
        if (wsRef.current.readyState !== WebSocket.OPEN) return;
        wsRef.current.send(JSON.stringify({
            cmd: "send",
            to,
            subject,
            body,
            bulletin: isBulletin,
        }));
    }, [inBBSMode]);

    const handleMessagePress = useCallback((item) => {
        readMessage(item.number);
    }, [readMessage]);

    const handleReply = useCallback(() => {
        if (selectedMessage) {
            setReplyTo(selectedMessage);
            setShowDetail(false);
            setShowCompose(true);
        }
    }, [selectedMessage]);

    const handleDelete = useCallback(() => {
        if (selectedMessage) {
            deleteMessage(selectedMessage.number);
        }
    }, [selectedMessage, deleteMessage]);

    const handleCompose = useCallback(() => {
        setReplyTo(null);
        setShowCompose(true);
    }, []);

    const renderItem = useCallback(({ item }) => (
        <MessageListItem item={item} onPress={handleMessagePress} />
    ), [handleMessagePress]);

    const handleConnectDisconnect = useCallback(() => {
        if (isConnected) {
            disconnectFeature('bbs');
        } else {
            connectFeature('bbs');
        }
    }, [isConnected, connectFeature, disconnectFeature]);

    const getStatusText = () => {
        if (isConnecting) return 'Connecting...';
        if (!isConnected) return 'Disconnected';
        if (!inBBSMode) return 'Entering BBS...';
        return 'Connected';
    };

    return (
        <View style={styles.container}>
            <View style={[styles.headerBar, { paddingTop: insets.top + 10 }]}>
                <View style={styles.headerLeft}>
                    <View style={[
                        styles.statusDot,
                        inBBSMode ? styles.statusConnected : (isConnecting ? styles.statusConnecting : styles.statusDisconnected)
                    ]} />
                    <Text style={styles.headerTitle}>BBS</Text>
                </View>
                <View style={styles.headerRight}>
                    <Text style={styles.statusText}>{getStatusText()}</Text>
                    <TouchableOpacity onPress={refreshMessages} style={styles.refreshButton} disabled={!inBBSMode || loading}>
                        {loading ? (
                            <ActivityIndicator size="small" color="#4ade80" />
                        ) : (
                            <Ionicons name="refresh" size={20} color={inBBSMode ? "#4ade80" : "#666"} />
                        )}
                    </TouchableOpacity>
                    <TouchableOpacity onPress={handleConnectDisconnect} style={styles.connectButton}>
                        <Ionicons
                            name={isConnected ? "stop-circle-outline" : "play-circle-outline"}
                            size={20}
                            color={isConnected ? "#ef4444" : "#4ade80"}
                        />
                    </TouchableOpacity>
                </View>
            </View>

            <FilterTabs selected={selectedFilter} onSelect={setSelectedFilter} />

            {error && (
                <View style={styles.errorBanner}>
                    <Ionicons name="warning" size={16} color="#ef4444" />
                    <Text style={styles.errorBannerText}>{error}</Text>
                    <TouchableOpacity onPress={() => setError(null)}>
                        <Ionicons name="close" size={16} color="#ef4444" />
                    </TouchableOpacity>
                </View>
            )}

            <View style={styles.messagesContainer}>
                {!inBBSMode ? (
                    <View style={styles.loadingContainer}>
                        <ActivityIndicator size="large" color="#4ade80" />
                        <Text style={styles.loadingText}>
                            {isConnected ? 'Entering BBS mode...' : 'Connecting to server...'}
                        </Text>
                    </View>
                ) : messages.length === 0 && !loading ? (
                    <View style={styles.emptyContainer}>
                        <Ionicons name="mail-outline" size={48} color="#666" />
                        <Text style={styles.emptyText}>No messages</Text>
                    </View>
                ) : (
                    <FlashList
                        data={messages}
                        renderItem={renderItem}
                        keyExtractor={(item) => item.number.toString()}
                        estimatedItemSize={100}
                        refreshing={loading}
                        onRefresh={refreshMessages}
                    />
                )}
            </View>

            <TouchableOpacity
                style={[styles.composeButton, { bottom: insets.bottom + 20 }, !inBBSMode && styles.composeButtonDisabled]}
                onPress={handleCompose}
                disabled={!inBBSMode}
            >
                <Ionicons name="create" size={24} color="#fff" />
            </TouchableOpacity>

            <MessageDetailModal
                visible={showDetail}
                message={selectedMessage}
                onClose={() => {
                    setShowDetail(false);
                    setSelectedMessage(null);
                }}
                onDelete={handleDelete}
                onReply={handleReply}
            />

            <ComposeModal
                visible={showCompose}
                onClose={() => {
                    setShowCompose(false);
                    setReplyTo(null);
                }}
                onSend={sendMessage}
                replyTo={replyTo}
            />
        </View>
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
        backgroundColor: '#f59e0b',
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
    statusText: {
        color: '#888',
        fontSize: 12,
        marginRight: 10,
    },
    refreshButton: {
        padding: 5,
    },
    connectButton: {
        padding: 5,
        marginLeft: 5,
    },
    filterTabs: {
        flexDirection: 'row',
        backgroundColor: '#252525',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    filterTab: {
        flex: 1,
        paddingVertical: 10,
        alignItems: 'center',
    },
    filterTabActive: {
        borderBottomWidth: 2,
        borderBottomColor: '#4ade80',
    },
    filterTabText: {
        color: '#888',
        fontSize: 14,
    },
    filterTabTextActive: {
        color: '#4ade80',
        fontWeight: 'bold',
    },
    errorBanner: {
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: '#2a1a1a',
        paddingHorizontal: 15,
        paddingVertical: 8,
        gap: 8,
    },
    errorBannerText: {
        flex: 1,
        color: '#ef4444',
        fontSize: 12,
    },
    messagesContainer: {
        flex: 1,
    },
    loadingContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    loadingText: {
        color: '#888',
        marginTop: 10,
    },
    emptyContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    emptyText: {
        color: '#888',
        marginTop: 10,
        fontSize: 16,
    },
    messageItem: {
        backgroundColor: '#252525',
        padding: 12,
        marginHorizontal: 10,
        marginTop: 10,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#333',
    },
    messageHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 6,
    },
    messageLeft: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    typeBadge: {
        paddingHorizontal: 6,
        paddingVertical: 2,
        borderRadius: 4,
        marginRight: 8,
    },
    typeBadgeText: {
        color: '#fff',
        fontSize: 10,
        fontWeight: 'bold',
    },
    messageNumber: {
        color: '#888',
        fontSize: 12,
        fontFamily: '"Courier New", Courier, monospace',
    },
    newDot: {
        width: 6,
        height: 6,
        borderRadius: 3,
        backgroundColor: '#4ade80',
        marginLeft: 6,
    },
    messageDate: {
        color: '#888',
        fontSize: 11,
    },
    messageBody: {
        marginBottom: 6,
    },
    messageFrom: {
        color: '#4ade80',
        fontSize: 12,
        fontWeight: 'bold',
        marginBottom: 2,
    },
    messageSubject: {
        color: '#ddd',
        fontSize: 14,
    },
    messageFooter: {
        flexDirection: 'row',
        justifyContent: 'space-between',
    },
    messageSize: {
        color: '#666',
        fontSize: 11,
    },
    composeButton: {
        position: 'absolute',
        right: 20,
        width: 56,
        height: 56,
        borderRadius: 28,
        backgroundColor: '#4ade80',
        justifyContent: 'center',
        alignItems: 'center',
        elevation: 4,
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.25,
        shadowRadius: 4,
    },
    composeButtonDisabled: {
        backgroundColor: '#333',
    },
    // Modal styles
    modalContainer: {
        flex: 1,
        backgroundColor: '#1e1e1e',
    },
    modalHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: 15,
        paddingVertical: 10,
        backgroundColor: '#252525',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    modalBackButton: {
        padding: 5,
    },
    modalTitle: {
        color: '#fff',
        fontSize: 16,
        fontWeight: 'bold',
    },
    modalActions: {
        flexDirection: 'row',
    },
    modalActionButton: {
        padding: 8,
        marginLeft: 5,
    },
    messageDetailContent: {
        flex: 1,
    },
    messageDetailHeader: {
        backgroundColor: '#252525',
        padding: 15,
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    messageDetailRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 8,
    },
    messageDetailLabel: {
        color: '#888',
        width: 60,
        fontSize: 12,
    },
    messageDetailValue: {
        color: '#fff',
        fontSize: 14,
        flex: 1,
    },
    messageBodySection: {
        padding: 15,
    },
    messageBodyText: {
        color: '#ddd',
        fontSize: 14,
        lineHeight: 22,
        fontFamily: '"Courier New", Courier, monospace',
    },
    // Compose modal styles
    sendHeaderButton: {
        paddingHorizontal: 15,
        paddingVertical: 8,
    },
    sendHeaderButtonDisabled: {
        opacity: 0.5,
    },
    sendHeaderButtonText: {
        color: '#4ade80',
        fontWeight: 'bold',
        fontSize: 14,
    },
    composeContent: {
        flex: 1,
        padding: 15,
    },
    composeField: {
        marginBottom: 15,
    },
    composeLabel: {
        color: '#888',
        fontSize: 12,
        marginBottom: 5,
    },
    composeInput: {
        backgroundColor: '#252525',
        color: '#fff',
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#333',
        fontSize: 14,
    },
    bulletinToggle: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 15,
        paddingVertical: 5,
    },
    bulletinToggleText: {
        color: '#ddd',
        marginLeft: 10,
        fontSize: 14,
    },
    composeBodyField: {
        flex: 1,
    },
    composeBodyInput: {
        backgroundColor: '#252525',
        color: '#fff',
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#333',
        fontSize: 14,
        minHeight: 200,
        fontFamily: '"Courier New", Courier, monospace',
    },
});
