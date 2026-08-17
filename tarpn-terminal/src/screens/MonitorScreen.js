import React, { useContext, useState, useRef, memo, useCallback, useMemo } from 'react';
import { StyleSheet, Text, View, TouchableOpacity, Modal, ActivityIndicator } from 'react-native';
import { FlashList } from '@shopify/flash-list';
import { AppContext } from '../context/AppContext';
import { htmlDecode, encodeNonPrintable } from '../utils/ax25Utils';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

// Memoized Log Row for Performance
const LogRow = memo(({ item, onPress, getPortColor, compact }) => {
    // Helper to decode and encode non-printable chars for display
    const decodeForDisplay = (text) => encodeNonPrintable(htmlDecode(text));

    if (compact) {
        // Compact mode: inline layout with minimal spacing
        const prefixText = `${item.prefix}${item.port}`;
        return (
            <TouchableOpacity
                style={[styles.logRow, item.ax25Info && styles.logRowClickable]}
                onPress={() => item.ax25Info ? onPress(item) : null}
            >
                <Text style={styles.logTime}>{item.displayTimestamp}</Text>
                {item.raw ? (
                    <Text style={styles.logRaw}>{decodeForDisplay(item.raw)}</Text>
                ) : (
                    <View style={{flexDirection: 'row', flex: 1, flexWrap: 'wrap'}}>
                        <Text style={[styles.logPrefix, {color: getPortColor(item.port)}]}>
                            {prefixText}
                        </Text>
                        {item.isRetry && (
                            <Text style={styles.retryText}>🔁</Text>
                        )}
                        <Text style={[styles.logRoute, {color: item.routeColor || '#fff'}]}>
                            &nbsp;{item.route}&nbsp;
                        </Text>
                        <Text style={styles.logContent}>
                            {decodeForDisplay(item.message)}
                        </Text>
                    </View>
                )}
            </TouchableOpacity>
        );
    }

    // Standard mode: fixed-width columns for alignment
    return (
        <TouchableOpacity
            style={[styles.logRow, item.ax25Info && styles.logRowClickable]}
            onPress={() => item.ax25Info ? onPress(item) : null}
        >
            <Text style={styles.logTime}>{item.displayTimestamp}</Text>
            {item.raw ? (
                <Text style={styles.logRaw}>{decodeForDisplay(item.raw)}</Text>
            ) : (
                <>
                    {/* Direction column: Tx or Rx */}
                    <Text style={[styles.colDirection, {color: getPortColor(item.port)}]}>
                        {item.prefix}x
                    </Text>
                    {/* Port column: Port=num */}
                    <Text style={[styles.colPort, {color: getPortColor(item.port)}]}>
                        Port={item.port}
                    </Text>
                    {/* Retry column */}
                    <Text style={styles.colRetry}>
                        {item.isRetry ? '🔁' : ''}
                    </Text>
                    {/* Route column */}
                    <Text style={[styles.colRoute, {color: item.routeColor || '#fff'}]}>
                        {item.route}
                    </Text>
                    {/* Data column - takes remaining space */}
                    <Text style={styles.colData}>
                        {decodeForDisplay(item.message)}
                    </Text>
                </>
            )}
        </TouchableOpacity>
    );
});

// Standard ANSI/terminal-like colours, indexed by port. Module scope so the
// array is not rebuilt on every call - getPortColor runs once per visible row.
const PORT_COLORS = [
    '#ef4444', // Red (Port 0/6)
    '#22c55e', // Green (Port 1/7)
    '#eab308', // Yellow (Port 2/8)
    '#3b82f6', // Blue (Port 3/9)
    '#d946ef', // Magenta (Port 4/10)
    '#06b6d4', // Cyan (Port 5/11)
];

const getPortColor = (p) => PORT_COLORS[parseInt(p) % PORT_COLORS.length] || '#ccc';

export default function MonitorScreen() {
    const {
        logMessages,
        settings,
        setSettings,
        visiblePorts,
        clearLogs,
        loadMoreHistory,
        isLoadingMore,
        hasMoreHistory,
        bufferInfo
    } = useContext(AppContext);
    const [selectedMessage, setSelectedMessage] = useState(null);
    const [isAtBottom, setIsAtBottom] = useState(true);
    const flatListRef = useRef(null);
    const insets = useSafeAreaInsets();

    const lastScrollY = useRef(0);

    const handleScroll = useCallback((event) => {
        const { layoutMeasurement, contentOffset, contentSize } = event.nativeEvent;

        // Check if near top for loading more history
        const paddingToTop = 100;
        const isNearTop = contentOffset.y < paddingToTop;
        if (isNearTop && hasMoreHistory && !isLoadingMore) {
            loadMoreHistory();
        }

        // Check if near bottom for auto-scroll
        const paddingToBottom = 50;
        const isCloseToBottom = layoutMeasurement.height + contentOffset.y >= contentSize.height - paddingToBottom;
        setIsAtBottom(isCloseToBottom);

        // Detect scroll direction - if scrolling up (away from bottom), disable auto-scroll
        // This handles web where onScrollBeginDrag doesn't fire for mouse wheel
        const scrollingUp = contentOffset.y < lastScrollY.current;
        lastScrollY.current = contentOffset.y;

        if (scrollingUp && settings.autoScroll && !isCloseToBottom) {
            // User is scrolling up away from bottom - disable auto-scroll
            setSettings(prev => ({ ...prev, autoScroll: false }));
        } else if (isCloseToBottom && !settings.autoScroll) {
            // User scrolled back to bottom - re-enable auto-scroll
            setSettings(prev => ({ ...prev, autoScroll: true }));
        }
    }, [settings.autoScroll, setSettings, hasMoreHistory, isLoadingMore, loadMoreHistory]);

    // Filter Logic
    //
    // Memoised because this walks the whole log, and the context value it comes
    // from is rebuilt on every batch - so without this it re-filtered several
    // times a second whether or not anything relevant had changed. visiblePorts
    // becomes a Set so the per-message lookup is constant rather than a scan of
    // every visible port.
    const visiblePortSet = useMemo(() => new Set(visiblePorts), [visiblePorts]);

    const filteredMessages = useMemo(() => logMessages.filter(msg => {
        if (settings.hideUSBRoutes && msg.route === "TNC>USB") return false;
        if (msg.port && !visiblePortSet.has(msg.port)) return false;
        return true;
    }), [logMessages, settings.hideUSBRoutes, visiblePortSet]);

    const renderLogItem = useCallback(({ item }) => (
        <LogRow item={item} onPress={setSelectedMessage} getPortColor={getPortColor} compact={settings.compactLayout} />
    ), [settings.compactLayout]);

    return (
        <View style={styles.container}>
            <View style={[styles.headerBar, { paddingTop: insets.top + 10 }]}>
                 <Text style={styles.headerTitle}>Monitor Feed</Text>
                 <View style={styles.headerRight}>
                     <Text style={styles.countText}>{filteredMessages.length} msgs</Text>
                     <TouchableOpacity onPress={clearLogs} style={styles.clearButton}>
                        <Ionicons name="trash-outline" size={16} color="#aaa" />
                     </TouchableOpacity>
                 </View>
            </View>
            
            <FlashList
                ref={flatListRef}
                data={filteredMessages}
                renderItem={renderLogItem}
                keyExtractor={(item) => item.id.toString()}
                estimatedItemSize={28}
                contentContainerStyle={{ paddingBottom: 60 }}
                onScroll={handleScroll}
                onScrollBeginDrag={() => {
                    if (settings.autoScroll) {
                        setSettings(prev => ({ ...prev, autoScroll: false }));
                    }
                }}
                scrollEventThrottle={16}
                onContentSizeChange={() => {
                    if (settings.autoScroll && filteredMessages.length > 0) {
                        flatListRef.current?.scrollToEnd({ animated: false });
                    }
                }}
                ListHeaderComponent={
                    isLoadingMore ? (
                        <View style={styles.loadingMoreContainer}>
                            <ActivityIndicator size="small" color="#4ade80" />
                            <Text style={styles.loadingMoreText}>Loading older messages...</Text>
                        </View>
                    ) : hasMoreHistory ? (
                        <TouchableOpacity
                            style={styles.loadMoreButton}
                            onPress={() => loadMoreHistory()}
                        >
                            <Text style={styles.loadMoreText}>Load older messages</Text>
                        </TouchableOpacity>
                    ) : bufferInfo.count > 0 ? (
                        <View style={styles.noMoreContainer}>
                            <Text style={styles.noMoreText}>Beginning of buffer</Text>
                        </View>
                    ) : null
                }
            />

            {!isAtBottom && !settings.autoScroll && (
                <TouchableOpacity 
                    style={styles.scrollToBottomButton} 
                    onPress={() => {
                        flatListRef.current?.scrollToEnd({ animated: true });
                        if (!settings.autoScroll) {
                            setSettings(prev => ({ ...prev, autoScroll: true }));
                        }
                    }}
                >
                    <Ionicons name="arrow-down" size={24} color="#fff" />
                </TouchableOpacity>
            )}

            {/* Detail Modal */}
            <Modal
                animationType="fade"
                transparent={true}
                visible={!!selectedMessage}
                onRequestClose={() => setSelectedMessage(null)}
            >
                <View style={styles.modalOverlay}>
                    <View style={styles.modalContent}>
                        <Text style={styles.modalTitle}>AX.25 Packet Details</Text>
                        {selectedMessage && selectedMessage.ax25Info && (
                            <View>
                                <Text style={styles.modalText}><Text style={styles.bold}>From:</Text> {selectedMessage.ax25Info.source.call}</Text>
                                <Text style={styles.modalText}><Text style={styles.bold}>To:</Text> {selectedMessage.ax25Info.destination.call}</Text>
                                <Text style={styles.modalText}><Text style={styles.bold}>Frame Type:</Text> {selectedMessage.ax25Info.frameType}</Text>
                                <Text style={styles.modalItalic}>{selectedMessage.ax25Info.frameTypeExplanation}</Text>
                                
                                <Text style={styles.modalText}><Text style={styles.bold}>Control:</Text> {selectedMessage.ax25Info.controlRaw}</Text>
                                {selectedMessage.ax25Info.controlDetails.detailsString ? (
                                    <Text style={styles.modalItalic}>Details: {selectedMessage.ax25Info.controlDetails.detailsString}</Text>
                                ) : null}

                                <Text style={styles.modalText}><Text style={styles.bold}>PID:</Text> {selectedMessage.ax25Info.pid}</Text>
                                <Text style={styles.modalItalic}>{selectedMessage.ax25Info.pidExplanation}</Text>
                                
                                <Text style={styles.modalText}><Text style={styles.bold}>Info:</Text></Text>
                                <View style={styles.codeBlock}>
                                    <Text style={styles.codeText}>{selectedMessage.ax25Info.info}</Text>
                                </View>
                            </View>
                        )}
                        <TouchableOpacity style={styles.closeButton} onPress={() => setSelectedMessage(null)}>
                            <Text style={styles.closeButtonText}>Close</Text>
                        </TouchableOpacity>
                    </View>
                </View>
            </Modal>
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
      alignItems: 'center'
  },
  headerTitle: {
      color: '#fff',
      fontWeight: 'bold',
      fontSize: 16
  },
  headerRight: {
      flexDirection: 'row',
      alignItems: 'center'
  },
  countText: {
      color: '#888',
      fontSize: 12,
      marginRight: 10
  },
  clearButton: {
      padding: 5,
  },
  logRow: {
    flexDirection: 'row',
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#333',
  },
  logRowClickable: {
      backgroundColor: '#252525'
  },
  logTime: {
    color: '#888',
    fontFamily: '"Courier New", Courier, monospace',
    marginRight: 8,
    fontSize: 12,
  },
  logPrefix: {
    fontFamily: '"Courier New", Courier, monospace',
    fontWeight: 'bold',
    fontSize: 12,
  },
  logRoute: {
    fontFamily: '"Courier New", Courier, monospace',
    fontWeight: 'bold',
    fontSize: 12,
  },
  logContent: {
    color: '#ddd',
    fontFamily: '"Courier New", Courier, monospace',
    fontSize: 12,
    flex: 1,
  },
  logRaw: {
      color: '#aaa',
      fontFamily: '"Courier New", Courier, monospace',
      fontSize: 12,
  },
  retryText: {
      fontSize: 12,
      marginHorizontal: 2,
      color: '#fbbf24' // Warning color
  },
  // Fixed-width column styles for standard (non-compact) mode
  colDirection: {
      fontFamily: '"Courier New", Courier, monospace',
      fontWeight: 'bold',
      fontSize: 12,
      width: 24, // "Tx" or "Rx"
      textAlign: 'left',
  },
  colPort: {
      fontFamily: '"Courier New", Courier, monospace',
      fontWeight: 'bold',
      fontSize: 12,
      width: 56, // "Port=XX" (up to 2 digit port numbers)
      textAlign: 'left',
      marginRight: 8,
  },
  colRetry: {
      fontSize: 12,
      width: 20, // Emoji or empty
      textAlign: 'center',
  },
  colRoute: {
      fontFamily: '"Courier New", Courier, monospace',
      fontWeight: 'bold',
      fontSize: 12,
      width: 140, // "CALLSIGN-15>CALLSIGN-15" max ~21 chars
      marginRight: 8,
  },
  colData: {
      color: '#ddd',
      fontFamily: '"Courier New", Courier, monospace',
      fontSize: 12,
      flex: 1,
  },
  scrollToBottomButton: {
      position: 'absolute',
      right: 20,
      bottom: 20,
      backgroundColor: '#3b82f6',
      width: 40,
      height: 40,
      borderRadius: 20,
      justifyContent: 'center',
      alignItems: 'center',
      elevation: 5,
      shadowColor: "#000",
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.25,
      shadowRadius: 3.84,
  },
  // Modal
  modalOverlay: {
      flex: 1,
      backgroundColor: 'rgba(0,0,0,0.7)',
      justifyContent: 'center',
      alignItems: 'center',
      padding: 20
  },
  modalContent: {
      backgroundColor: '#2c2c2c',
      borderRadius: 10,
      padding: 20,
      width: '100%',
      maxHeight: '80%',
      shadowColor: "#000",
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.25,
      shadowRadius: 3.84,
      elevation: 5,
  },
  modalTitle: {
      color: '#fff',
      fontSize: 20,
      fontWeight: 'bold',
      marginBottom: 15,
      borderBottomWidth: 1,
      borderBottomColor: '#444',
      paddingBottom: 5
  },
  modalText: {
      color: '#ddd',
      marginBottom: 5,
  },
  bold: {
      fontWeight: 'bold',
      color: '#fff'
  },
  modalItalic: {
      color: '#aaa',
      fontStyle: 'italic',
      marginBottom: 10,
  },
  codeBlock: {
      backgroundColor: '#111',
      padding: 10,
      borderRadius: 5,
      marginTop: 5,
      marginBottom: 15
  },
  codeText: {
      color: '#89ddff',
      fontFamily: '"Courier New", Courier, monospace',
  },
  closeButton: {
      backgroundColor: '#444',
      padding: 12,
      borderRadius: 5,
      alignItems: 'center',
      marginTop: 10
  },
  closeButtonText: {
      color: '#fff',
      fontWeight: 'bold'
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
});