import React, { useState, useMemo } from 'react';
import { StyleSheet, Text, View, TouchableOpacity, ScrollView } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

const formatDuration = (startedAt, endedAt) => {
    if (!startedAt) return '-';
    const start = new Date(startedAt);
    const end = endedAt ? new Date(endedAt) : new Date();
    const secs = Math.floor((end - start) / 1000);
    if (secs < 60) return `${secs}s`;
    if (secs < 3600) return `${Math.floor(secs/60)}m${secs%60}s`;
    const hours = Math.floor(secs / 3600);
    const mins = Math.floor((secs % 3600) / 60);
    return `${hours}h${mins}m`;
};

const stateColors = {
    connected: '#4ade80',
    connecting: '#fbbf24',
    disconnecting: '#fbbf24',
    disconnected: '#666',
};

const getRetryColor = (retryRate) => {
    if (retryRate < 2) return '#4ade80';
    if (retryRate < 5) return '#fbbf24';
    return '#ef4444';
};

function SidebarSessionRow({ session, filterState, setFilterState }) {
    const [expanded, setExpanded] = useState(false);
    const isSelected = filterState.sessionId === session.id;
    const hasCircuits = session.circuits && session.circuits.length > 0;

    const handlePress = () => {
        if (isSelected) {
            setFilterState({ ...filterState, sessionId: null });
        } else {
            setFilterState({ ...filterState, sessionId: session.id });
        }
    };

    const protoFlags = [
        session.hasNetROM && 'NR',
        session.hasIP && 'IP',
        session.hasText && 'TXT',
    ].filter(Boolean).join('/');

    return (
        <>
            <TouchableOpacity
                style={[sidebarStyles.row, isSelected && sidebarStyles.rowSelected]}
                onPress={handlePress}
            >
                <View style={sidebarStyles.topLine}>
                    {hasCircuits ? (
                        <TouchableOpacity
                            onPress={(e) => { e.stopPropagation(); setExpanded(!expanded); }}
                            style={sidebarStyles.expandBtn}
                        >
                            <Ionicons name={expanded ? 'chevron-down' : 'chevron-forward'} size={10} color="#888" />
                        </TouchableOpacity>
                    ) : (
                        <View style={sidebarStyles.expandBtn} />
                    )}
                    <Text style={sidebarStyles.portBadge}>P{session.port}</Text>
                    <Text style={sidebarStyles.callText} numberOfLines={1}>
                        {session.initiator} {'↔'} {session.responder}
                    </Text>
                </View>
                <View style={sidebarStyles.bottomLine}>
                    <Text style={[sidebarStyles.stateText, { color: stateColors[session.state] || '#666' }]}>
                        {session.state}
                    </Text>
                    <Text style={sidebarStyles.dimText}>
                        {formatDuration(session.startedAt, session.endedAt)}
                    </Text>
                    <Text style={sidebarStyles.dimText}>
                        I:{session.iFramesSent}/{session.iFramesReceived}
                    </Text>
                    <Text style={[sidebarStyles.dimText, { color: getRetryColor(session.retryRate) }]}>
                        Ret:{session.retryCount}
                    </Text>
                    {protoFlags ? <Text style={sidebarStyles.protoText}>{protoFlags}</Text> : null}
                </View>
            </TouchableOpacity>
            {expanded && hasCircuits && session.circuits.map((circuit) => (
                <View key={circuit.id} style={sidebarStyles.circuitRow}>
                    <Text style={sidebarStyles.circuitText} numberOfLines={1}>
                        {'  ↳ '}{circuit.remote} {'→'} {circuit.local}
                    </Text>
                    <Text style={[sidebarStyles.circuitState, { color: stateColors[circuit.state] || '#666' }]}>
                        {circuit.state} | {circuit.segsSent}/{circuit.segsRcvd}
                    </Text>
                </View>
            ))}
        </>
    );
}

function SessionRow({ session, filterState, setFilterState }) {
    const [expanded, setExpanded] = useState(false);
    const isSelected = filterState.sessionId === session.id;
    const hasCircuits = session.circuits && session.circuits.length > 0;

    const handlePress = () => {
        if (isSelected) {
            setFilterState({ ...filterState, sessionId: null });
        } else {
            setFilterState({ ...filterState, sessionId: session.id });
        }
    };

    const handleExpandPress = (e) => {
        e.stopPropagation();
        setExpanded(!expanded);
    };

    return (
        <>
            <TouchableOpacity
                style={[
                    styles.row,
                    isSelected && styles.rowSelected,
                ]}
                onPress={handlePress}
            >
                {hasCircuits ? (
                    <TouchableOpacity onPress={handleExpandPress} style={styles.expandButton}>
                        <Ionicons
                            name={expanded ? 'chevron-down' : 'chevron-forward'}
                            size={12}
                            color="#888"
                        />
                    </TouchableOpacity>
                ) : (
                    <View style={styles.expandButton} />
                )}
                <Text style={[styles.cellText, { width: 35 }]}>{session.port}</Text>
                <Text style={[styles.cellText, { width: 70 }]} numberOfLines={1}>{session.initiator}</Text>
                <Text style={[styles.cellText, { width: 70 }]} numberOfLines={1}>{session.responder}</Text>
                <Text style={[styles.cellText, { width: 70, color: stateColors[session.state] || '#666' }]}>
                    {session.state}
                </Text>
                <Text style={[styles.cellText, { width: 55 }]}>
                    {session.iFramesSent}/{session.iFramesReceived}
                </Text>
                <Text style={[styles.cellText, { width: 70, color: getRetryColor(session.retryRate) }]}>
                    {session.retryCount} ({session.timeoutRetries}T/{session.rejRetries}R)
                </Text>
                <Text style={[styles.cellText, { width: 55 }]}>
                    {formatDuration(session.startedAt, session.endedAt)}
                </Text>
                <Text style={[styles.cellText, { flex: 1 }]} numberOfLines={1}>
                    {[
                        session.hasNetROM && 'NR',
                        session.hasIP && 'IP',
                        session.hasText && 'TXT',
                    ].filter(Boolean).join('/')}
                </Text>
            </TouchableOpacity>
            {expanded && hasCircuits && session.circuits.map((circuit) => (
                <View key={circuit.id} style={styles.circuitRow}>
                    <View style={styles.circuitIndent} />
                    <Text style={[styles.cellText, { width: 70 }]} numberOfLines={1}>{circuit.remote}</Text>
                    <Text style={[styles.cellText, { width: 70 }]} numberOfLines={1}>{circuit.local}</Text>
                    <Text style={[styles.cellText, { width: 70, color: stateColors[circuit.state] || '#666' }]}>
                        {circuit.state}
                    </Text>
                    <Text style={[styles.cellText, { flex: 1 }]}>
                        {circuit.segsSent}/{circuit.segsRcvd} ({circuit.segsResent} resent)
                    </Text>
                </View>
            ))}
        </>
    );
}

export default function SessionPanel({ sessions, filterState, setFilterState, visible, sidebar }) {
    if (!visible) return null;

    const sortedSessions = useMemo(() => {
        if (!sessions) return [];
        const sorted = [...sessions].sort((a, b) => {
            const aActive = a.state === 'connected' || a.state === 'connecting' || a.state === 'disconnecting';
            const bActive = b.state === 'connected' || b.state === 'connecting' || b.state === 'disconnecting';
            if (aActive && !bActive) return -1;
            if (!aActive && bActive) return 1;
            const aTime = new Date(a.lastActivity || 0).getTime();
            const bTime = new Date(b.lastActivity || 0).getTime();
            return bTime - aTime;
        });
        return sorted.slice(0, 50);
    }, [sessions]);

    if (sidebar) {
        return (
            <View style={sidebarStyles.container}>
                <View style={sidebarStyles.header}>
                    <Text style={sidebarStyles.headerTitle}>Sessions</Text>
                    <Text style={sidebarStyles.headerCount}>{sortedSessions.length}</Text>
                </View>
                <ScrollView style={sidebarStyles.scrollView}>
                    {sortedSessions.map((session) => (
                        <SidebarSessionRow
                            key={session.id}
                            session={session}
                            filterState={filterState}
                            setFilterState={setFilterState}
                        />
                    ))}
                    {sortedSessions.length === 0 && (
                        <View style={sidebarStyles.emptyRow}>
                            <Text style={sidebarStyles.emptyText}>No sessions</Text>
                        </View>
                    )}
                </ScrollView>
            </View>
        );
    }

    return (
        <View style={styles.container}>
            <View style={styles.headerRow}>
                <View style={styles.expandButton} />
                <Text style={[styles.headerText, { width: 35 }]}>Port</Text>
                <Text style={[styles.headerText, { width: 70 }]}>Src</Text>
                <Text style={[styles.headerText, { width: 70 }]}>Dst</Text>
                <Text style={[styles.headerText, { width: 70 }]}>State</Text>
                <Text style={[styles.headerText, { width: 55 }]}>I-Frm</Text>
                <Text style={[styles.headerText, { width: 70 }]}>Retries</Text>
                <Text style={[styles.headerText, { width: 55 }]}>Dur</Text>
                <Text style={[styles.headerText, { flex: 1 }]}>Proto</Text>
            </View>
            <ScrollView style={styles.scrollView}>
                {sortedSessions.map((session) => (
                    <SessionRow
                        key={session.id}
                        session={session}
                        filterState={filterState}
                        setFilterState={setFilterState}
                    />
                ))}
                {sortedSessions.length === 0 && (
                    <View style={styles.emptyRow}>
                        <Text style={styles.emptyText}>No sessions</Text>
                    </View>
                )}
            </ScrollView>
        </View>
    );
}

const sidebarStyles = StyleSheet.create({
    container: {
        width: 320,
        backgroundColor: '#252525',
        borderLeftWidth: 1,
        borderLeftColor: '#333',
    },
    header: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        paddingVertical: 6,
        paddingHorizontal: 10,
        backgroundColor: '#1e1e1e',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    headerTitle: {
        color: '#888',
        fontSize: 11,
        fontWeight: 'bold',
    },
    headerCount: {
        color: '#666',
        fontSize: 10,
    },
    scrollView: {
        flex: 1,
    },
    row: {
        paddingVertical: 5,
        paddingHorizontal: 8,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333',
    },
    rowSelected: {
        borderLeftWidth: 2,
        borderLeftColor: '#4ade80',
    },
    topLine: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 2,
    },
    expandBtn: {
        width: 14,
        alignItems: 'center',
        justifyContent: 'center',
    },
    portBadge: {
        color: '#888',
        fontSize: 10,
        fontFamily: '"Courier New", Courier, monospace',
        marginRight: 6,
    },
    callText: {
        color: '#ccc',
        fontSize: 11,
        fontFamily: '"Courier New", Courier, monospace',
        flex: 1,
    },
    bottomLine: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingLeft: 14,
        gap: 8,
    },
    stateText: {
        fontSize: 10,
        fontFamily: '"Courier New", Courier, monospace',
    },
    dimText: {
        color: '#888',
        fontSize: 10,
        fontFamily: '"Courier New", Courier, monospace',
    },
    protoText: {
        color: '#6b7280',
        fontSize: 10,
        fontFamily: '"Courier New", Courier, monospace',
    },
    circuitRow: {
        paddingVertical: 3,
        paddingHorizontal: 8,
        paddingLeft: 22,
        backgroundColor: '#1e1e1e',
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333',
    },
    circuitText: {
        color: '#aaa',
        fontSize: 10,
        fontFamily: '"Courier New", Courier, monospace',
    },
    circuitState: {
        fontSize: 10,
        fontFamily: '"Courier New", Courier, monospace',
    },
    emptyRow: {
        paddingVertical: 20,
        alignItems: 'center',
    },
    emptyText: {
        color: '#666',
        fontSize: 11,
        fontStyle: 'italic',
    },
});

const styles = StyleSheet.create({
    container: {
        backgroundColor: '#252525',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
        maxHeight: 200,
    },
    headerRow: {
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: '#1e1e1e',
        paddingVertical: 4,
        paddingHorizontal: 6,
    },
    headerText: {
        color: '#888',
        fontSize: 10,
        fontWeight: 'bold',
        fontFamily: '"Courier New", Courier, monospace',
    },
    scrollView: {
        flex: 1,
    },
    row: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: 4,
        paddingHorizontal: 6,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333',
    },
    rowSelected: {
        borderLeftWidth: 2,
        borderLeftColor: '#4ade80',
    },
    cellText: {
        color: '#ccc',
        fontSize: 11,
        fontFamily: '"Courier New", Courier, monospace',
    },
    expandButton: {
        width: 16,
        alignItems: 'center',
        justifyContent: 'center',
    },
    circuitRow: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: 3,
        paddingHorizontal: 6,
        backgroundColor: '#1e1e1e',
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333',
    },
    circuitIndent: {
        width: 30,
    },
    emptyRow: {
        paddingVertical: 8,
        alignItems: 'center',
    },
    emptyText: {
        color: '#666',
        fontSize: 11,
        fontStyle: 'italic',
    },
});
