import React, { useContext, useMemo, useEffect, useState, useCallback, useRef } from 'react';
import { StyleSheet, Text, View, ScrollView, Pressable, Platform } from 'react-native';
import { AppContext } from '../context/AppContext';
import { getMinuteKey } from '../utils/timeUtils';
import { SkiaChart } from '../components/SkiaCompat';

// Tooltip descriptions for L2 stats columns
const L2_TOOLTIPS = {
    rxed: 'L2 Frames Rxed: AX.25 frames addressed to this station (not just overheard)',
    sent: 'L2 Frames Sent: All frames transmitted on this port',
    timeout: 'L2 Timeouts: T1/FRACK timer expirations waiting for ACK. Each retry adds 1 — not link failures',
    rej: 'REJ Rxed: Reject frames from neighbor requesting retransmission of a missed frame',
    crc: 'CRC Errors: Checksum failures on the KISS serial link (not RF-level CRC)',
    frmr: 'FRMR: Frame Reject — protocol violations detected. Sent + Received count',
    abandoned: 'Abandoned: Frames discarded because they could not be transmitted',
    txPct: 'TX%: Percentage of time transmitting (PTT active) in the last minute',
    busyPct: 'Busy%: Percentage of time the channel was busy (TX + RX) in the last minute',
};

// Tooltip component: hover on web, long-press on mobile
function Tooltip({ text, children }) {
    const [visible, setVisible] = useState(false);
    const timeoutRef = useRef(null);

    const show = useCallback(() => {
        setVisible(true);
        if (timeoutRef.current) clearTimeout(timeoutRef.current);
        timeoutRef.current = setTimeout(() => setVisible(false), 4000);
    }, []);

    const hide = useCallback(() => {
        setVisible(false);
        if (timeoutRef.current) clearTimeout(timeoutRef.current);
    }, []);

    useEffect(() => () => { if (timeoutRef.current) clearTimeout(timeoutRef.current); }, []);

    const hoverProps = Platform.OS === 'web'
        ? { onHoverIn: show, onHoverOut: hide }
        : {};

    return (
        <Pressable onLongPress={show} onPressOut={hide} {...hoverProps}>
            {children}
            {visible && (
                <View style={tooltipStyles.bubble}>
                    <Text style={tooltipStyles.text}>{text}</Text>
                </View>
            )}
        </Pressable>
    );
}

const tooltipStyles = StyleSheet.create({
    bubble: {
        position: 'absolute',
        top: '100%',
        left: 0,
        backgroundColor: '#333',
        borderWidth: 1,
        borderColor: '#555',
        borderRadius: 4,
        padding: 6,
        zIndex: 999,
        minWidth: 200,
        maxWidth: 300,
    },
    text: {
        color: '#eee',
        fontSize: 11,
        lineHeight: 15,
    },
});

// Format time for chart axis labels
function formatTime(date) {
    const h = date.getHours().toString().padStart(2, '0');
    const m = date.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
}

// Compute deltas between consecutive absolute counter readings
function computeDeltas(dataPoints, field) {
    if (dataPoints.length < 2) return [];
    const result = [];
    for (let i = 1; i < dataPoints.length; i++) {
        const prev = dataPoints[i - 1][field];
        const curr = dataPoints[i][field];
        // Handle counter rollover (reboot)
        const delta = curr >= prev ? curr - prev : curr;
        result.push({
            timestamp: dataPoints[i].timestamp,
            value: delta,
        });
    }
    return result;
}

export default function StatsScreen() {
    const {
        tncData, messageCountsByMinute, tarpnStatsHistory,
        linkStats, linkStatsHistory, neighborStats
    } = useContext(AppContext);
    const [graphSlots, setGraphSlots] = useState([]);
    const [now, setNow] = useState(new Date());
    const [expandedPorts, setExpandedPorts] = useState({});
    const [expandedNeighbors, setExpandedNeighbors] = useState({});

    useEffect(() => {
        const updateTimer = () => {
          const currentTime = new Date();
          setNow(currentTime);

          const newSlots = [];
          for (let i = 59; i >= 0; i--) {
            const slotDate = new Date(currentTime.getTime() - i * 60 * 1000);
            slotDate.setUTCSeconds(0, 0);
            newSlots.push(slotDate);
          }
          setGraphSlots(newSlots);
        };

        updateTimer();
        const interval = setInterval(updateTimer, 1000);
        return () => clearInterval(interval);
      }, []);

    const messageRateData = useMemo(() => {
        return graphSlots.map((slotDate, idx) => {
            const minuteKey = getMinuteKey(slotDate);
            const count = messageCountsByMinute[minuteKey] || 0;
            return { x: idx, count, label: formatTime(slotDate) };
        });
    }, [graphSlots, messageCountsByMinute]);

    const maxCount = useMemo(() => {
        return Math.max(1, ...messageRateData.map(d => d.count));
    }, [messageRateData]);

    const tarpnNodes = useMemo(() => {
        return Object.keys(tarpnStatsHistory).map(key => {
            const entry = tarpnStatsHistory[key];
            const latest = entry.dataPoints[entry.dataPoints.length - 1];

            let delta1h = null;
            if (latest && latest.utcDate) {
                const oneHourAgo = now.getTime() - 60 * 60 * 1000;
                const oldPoint = entry.dataPoints.find(p => p.utcDate && p.utcDate.getTime() >= oneHourAgo);

                if (oldPoint) {
                    delta1h = {
                        tx: latest.tx - oldPoint.tx,
                        ret: latest.ret - oldPoint.ret,
                        buf: latest.buf - oldPoint.buf
                    };
                }
            }

            return {
                key,
                port: entry.port,
                callsign: entry.callsign,
                latest,
                delta1h
            };
        }).sort((a,b) => {
            const portDiff = parseInt(a.port) - parseInt(b.port);
            if (portDiff !== 0) return portDiff;
            return a.callsign.localeCompare(b.callsign);
        });
    }, [tarpnStatsHistory, now]);

    const neighborNodes = useMemo(() => {
        return Object.keys(neighborStats).map(key => {
            const entry = neighborStats[key];
            const dp = entry.dataPoints;
            const latest = dp.length > 0 ? dp[dp.length - 1] : null;
            return {
                key,
                callsign: entry.callsign,
                reportedPort: entry.reportedPort,
                rxPort: entry.rxPort,
                latest,
                dataPoints: dp,
            };
        }).sort((a, b) => {
            const portDiff = a.reportedPort - b.reportedPort;
            if (portDiff !== 0) return portDiff;
            return a.callsign.localeCompare(b.callsign);
        });
    }, [neighborStats]);

    const togglePort = useCallback((portNum) => {
        setExpandedPorts(prev => ({ ...prev, [portNum]: !prev[portNum] }));
    }, []);

    const toggleNeighbor = useCallback((key) => {
        setExpandedNeighbors(prev => ({ ...prev, [key]: !prev[key] }));
    }, []);

    const hasData = messageRateData.some(d => d.count > 0);

    return (
        <ScrollView style={styles.container}>
            {/* Message Rate Chart */}
            <Text style={styles.sectionTitle}>Message Rate (Last 60 mins)</Text>
            <SkiaChart style={styles.chartContainer}>
                {(VN) => !hasData ? (
                    <Text style={styles.placeholderText}>Waiting for data...</Text>
                ) : (
                    <VN.CartesianChart
                        data={messageRateData}
                        xKey="x"
                        yKeys={["count"]}
                        domainPadding={{ left: 2, right: 2 }}
                        domain={{ y: [0, maxCount] }}
                        axisOptions={{
                            font: null,
                            tickCount: { x: 6, y: 4 },
                            formatXLabel: (val) => {
                                const idx = Math.round(val);
                                if (idx >= 0 && idx < messageRateData.length && idx % 10 === 0) {
                                    return messageRateData[idx]?.label || '';
                                }
                                return '';
                            },
                            labelColor: '#999',
                            lineColor: '#444',
                        }}
                    >
                        {({ points, chartBounds }) => (
                            <VN.Bar
                                points={points.count}
                                chartBounds={chartBounds}
                                color="#4ade80"
                                roundedCorners={{ topLeft: 2, topRight: 2 }}
                            />
                        )}
                    </VN.CartesianChart>
                )}
            </SkiaChart>

            {/* System Stats */}
            {linkStats && linkStats.system && (
                <>
                    <Text style={styles.sectionTitle}>System Stats (LinBPQ)</Text>
                    <View style={styles.systemStatsContainer}>
                        <Text style={styles.systemStatText}>
                            Uptime: {linkStats.system.uptimeDays}d {linkStats.system.uptimeHours}h {linkStats.system.uptimeMins}m
                        </Text>
                        <Text style={styles.systemStatText}>
                            Buffers: {linkStats.system.buffersCur}/{linkStats.system.buffersMax} (min: {linkStats.system.buffersMin})
                        </Text>
                        <Text style={styles.systemStatText}>
                            Nodes: {linkStats.system.knownNodes}/{linkStats.system.maxNodes}  |  L3 Relayed: {linkStats.system.l3Relayed}
                        </Text>
                        <Text style={styles.systemStatText}>
                            L4 TX/RX: {linkStats.system.l4FramesTx}/{linkStats.system.l4FramesRx}  |  Resent: {linkStats.system.l4Resent}
                        </Text>
                    </View>
                </>
            )}

            {/* L2 Link Stats Table + Expandable Charts */}
            <Text style={styles.sectionTitle}>L2 Link Statistics</Text>
            <ScrollView horizontal style={styles.tableScroll}>
                <View>
                    <View style={styles.tableRow}>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 50}]}>Port</Text>
                        <Tooltip text={L2_TOOLTIPS.rxed}><Text style={[styles.tableCell, styles.tableHeader]}>Rxed</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.sent}><Text style={[styles.tableCell, styles.tableHeader]}>Sent</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.timeout}><Text style={[styles.tableCell, styles.tableHeader]}>T/O</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.rej}><Text style={[styles.tableCell, styles.tableHeader]}>REJ</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.crc}><Text style={[styles.tableCell, styles.tableHeader]}>CRC</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.frmr}><Text style={[styles.tableCell, styles.tableHeader]}>FRMR</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.abandoned}><Text style={[styles.tableCell, styles.tableHeader]}>Aband</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.txPct}><Text style={[styles.tableCell, styles.tableHeader]}>TX%</Text></Tooltip>
                        <Tooltip text={L2_TOOLTIPS.busyPct}><Text style={[styles.tableCell, styles.tableHeader]}>Busy%</Text></Tooltip>
                    </View>
                    {linkStats && linkStats.ports ? (
                        Object.keys(linkStats.ports)
                            .sort((a, b) => parseInt(a) - parseInt(b))
                            .map(portNum => {
                                const p = linkStats.ports[portNum];
                                const isNetROM = parseInt(portNum) === 32;
                                return (
                                    <React.Fragment key={portNum}>
                                        <Pressable onPress={() => togglePort(portNum)}>
                                            <View style={styles.tableRow}>
                                                <Text style={[styles.tableCell, {width: 50}, isNetROM && styles.netromPort]}>
                                                    {expandedPorts[portNum] ? '▾ ' : '▸ '}
                                                    {isNetROM ? 'NR' : portNum}
                                                </Text>
                                                <Text style={styles.tableCell}>{p.l2Rxed}</Text>
                                                <Text style={styles.tableCell}>{p.l2Sent}</Text>
                                                <Text style={[styles.tableCell, p.l2Timeouts > 0 && styles.warnValue]}>{p.l2Timeouts}</Text>
                                                <Text style={[styles.tableCell, p.rejRxed > 0 && styles.warnValue]}>{p.rejRxed}</Text>
                                                <Text style={[styles.tableCell, p.rxCrcErrors > 0 && styles.errorValue]}>{p.rxCrcErrors}</Text>
                                                <Text style={[styles.tableCell, (p.frmrsSent + p.frmrsReceived) > 0 && styles.errorValue]}>
                                                    {p.frmrsSent + p.frmrsReceived}
                                                </Text>
                                                <Text style={[styles.tableCell, p.framesAbandoned > 0 && styles.errorValue]}>{p.framesAbandoned}</Text>
                                                <Text style={styles.tableCell}>{p.activeTxPct}</Text>
                                                <Text style={styles.tableCell}>{p.activeBusyPct}</Text>
                                            </View>
                                        </Pressable>
                                        {expandedPorts[portNum] && (
                                            <PortChart portNum={parseInt(portNum)} history={linkStatsHistory[portNum]} />
                                        )}
                                    </React.Fragment>
                                );
                            })
                    ) : (
                        <Text style={styles.emptyText}>No L2 stats received yet. Enable -stats flag on server.</Text>
                    )}
                </View>
            </ScrollView>

            {/* Neighbor Stats (from CQ broadcasts) */}
            {neighborNodes.length > 0 && (
                <>
                    <Text style={styles.sectionTitle}>Neighbor Link Stats (CQ)</Text>
                    <ScrollView horizontal style={styles.tableScroll}>
                        <View>
                            <View style={styles.tableRow}>
                                <Text style={[styles.tableCell, styles.tableHeader, {width: 80}]}>Node</Text>
                                <Text style={[styles.tableCell, styles.tableHeader, {width: 40}]}>Port</Text>
                                <Text style={[styles.tableCell, styles.tableHeader, {width: 40}]}>Rx</Text>
                                <Tooltip text={L2_TOOLTIPS.rxed}><Text style={[styles.tableCell, styles.tableHeader]}>Rxed</Text></Tooltip>
                                <Tooltip text={L2_TOOLTIPS.sent}><Text style={[styles.tableCell, styles.tableHeader]}>Sent</Text></Tooltip>
                                <Tooltip text={L2_TOOLTIPS.timeout}><Text style={[styles.tableCell, styles.tableHeader]}>T/O</Text></Tooltip>
                                <Tooltip text={L2_TOOLTIPS.rej}><Text style={[styles.tableCell, styles.tableHeader]}>REJ</Text></Tooltip>
                                <Tooltip text={L2_TOOLTIPS.txPct}><Text style={[styles.tableCell, styles.tableHeader]}>TX%</Text></Tooltip>
                                <Tooltip text={L2_TOOLTIPS.busyPct}><Text style={[styles.tableCell, styles.tableHeader]}>Busy%</Text></Tooltip>
                            </View>
                            {neighborNodes.map(node => (
                                <React.Fragment key={node.key}>
                                    <Pressable onPress={() => toggleNeighbor(node.key)}>
                                        <View style={styles.tableRow}>
                                            <Text style={[styles.tableCell, {width: 80}]}>{node.callsign}</Text>
                                            <Text style={[styles.tableCell, {width: 40}]}>{node.reportedPort}</Text>
                                            <Text style={[styles.tableCell, {width: 40}]}>{node.rxPort}</Text>
                                            <Text style={styles.tableCell}>{node.latest?.l2Rxed ?? '-'}</Text>
                                            <Text style={styles.tableCell}>{node.latest?.l2Sent ?? '-'}</Text>
                                            <Text style={[styles.tableCell, node.latest?.l2Timeouts > 0 && styles.warnValue]}>
                                                {node.latest?.l2Timeouts ?? '-'}
                                            </Text>
                                            <Text style={[styles.tableCell, node.latest?.rejRxed > 0 && styles.warnValue]}>
                                                {node.latest?.rejRxed ?? '-'}
                                            </Text>
                                            <Text style={styles.tableCell}>{node.latest?.activeTxPct ?? '-'}</Text>
                                            <Text style={styles.tableCell}>{node.latest?.activeBusyPct ?? '-'}</Text>
                                        </View>
                                    </Pressable>
                                    {expandedNeighbors[node.key] && (
                                        <NeighborChart dataPoints={node.dataPoints} />
                                    )}
                                </React.Fragment>
                            ))}
                        </View>
                    </ScrollView>
                </>
            )}

            {/* TARPN Stats */}
            <Text style={styles.sectionTitle}>Link Quality Stats (TARPN)</Text>
            <ScrollView horizontal style={styles.tableScroll}>
                <View>
                    <View style={styles.tableRow}>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 40}]}>Port</Text>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 80}]}>Node</Text>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 60}]}>Tx</Text>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 60}]}>Ret</Text>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 60}]}>Buf</Text>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 80}]}>Tx/1h</Text>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 80}]}>Ret/1h</Text>
                    </View>
                    {tarpnNodes.map(node => (
                        <View key={node.key} style={styles.tableRow}>
                             <Text style={[styles.tableCell, {width: 40}]}>{node.port}</Text>
                             <Text style={[styles.tableCell, {width: 80}]}>{node.callsign}</Text>
                             <Text style={[styles.tableCell, {width: 60}]}>{node.latest ? node.latest.tx : '-'}</Text>
                             <Text style={[styles.tableCell, {width: 60}]}>{node.latest ? node.latest.ret : '-'}</Text>
                             <Text style={[styles.tableCell, {width: 60}]}>{node.latest ? node.latest.buf : '-'}</Text>
                             <Text style={[styles.tableCell, {width: 80}]}>{node.delta1h ? node.delta1h.tx : '-'}</Text>
                             <Text style={[styles.tableCell, {width: 80}]}>{node.delta1h ? node.delta1h.ret : '-'}</Text>
                        </View>
                    ))}
                     {tarpnNodes.length === 0 && (
                        <Text style={styles.emptyText}>No TARPN stats received yet.</Text>
                    )}
                </View>
            </ScrollView>

            {/* TNC Status */}
            <Text style={styles.sectionTitle}>TNC Status by Port</Text>
            <ScrollView horizontal style={styles.tableScroll}>
                <View>
                    <View style={styles.tableRow}>
                        <Text style={[styles.tableCell, styles.tableHeader, {width: 40}]}>#</Text>
                        <Text style={[styles.tableCell, styles.tableHeader]}>State</Text>
                        <Text style={[styles.tableCell, styles.tableHeader]}>Tx Pkts</Text>
                        <Text style={[styles.tableCell, styles.tableHeader]}>Rx Bytes</Text>
                        <Text style={[styles.tableCell, styles.tableHeader]}>Tx Bytes</Text>
                        <Text style={[styles.tableCell, styles.tableHeader]}>DCD On</Text>
                    </View>
                    {Object.keys(tncData).sort((a,b)=>parseInt(a)-parseInt(b)).map(port => {
                        const d = tncData[port];
                        return (
                            <View key={port} style={styles.tableRow}>
                                <Text style={[styles.tableCell, {width: 40}]}>{port}</Text>
                                <Text style={styles.tableCell}>{d.uptime}</Text>
                                <Text style={styles.tableCell}>{d.transmitPackets}</Text>
                                <Text style={styles.tableCell}>{d.receivedDataBytes}</Text>
                                <Text style={styles.tableCell}>{d.transmitDataBytes}</Text>
                                <Text style={styles.tableCell}>{d.dcdOnTime}</Text>
                            </View>
                        )
                    })}
                    {Object.keys(tncData).length === 0 && (
                        <Text style={styles.emptyText}>No TNC Data received yet.</Text>
                    )}
                </View>
            </ScrollView>
        </ScrollView>
    );
}

// Expandable chart for a port's hourly L2 stats history
function PortChart({ portNum, history }) {
    const chartData = useMemo(() => {
        if (!history || history.length === 0) return null;
        return history.map((h, idx) => ({
            x: idx,
            rxed: h.dL2Rxed || 0,
            sent: h.dL2Sent || 0,
            timeouts: h.dL2Timeouts || 0,
            label: h.hourStart ? new Date(h.hourStart).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false }) : '',
        }));
    }, [history]);

    if (!chartData) {
        return (
            <View style={styles.expandedChart}>
                <Text style={styles.placeholderText}>No hourly history available</Text>
            </View>
        );
    }

    const maxVal = Math.max(1, ...chartData.map(d => Math.max(d.rxed, d.sent, d.timeouts)));

    return (
        <View style={styles.expandedChart}>
            <Text style={styles.chartLabel}>Packets (24h hourly)</Text>
            <SkiaChart style={styles.miniChartContainer}>
                {(VN) => (
                    <VN.CartesianChart
                        data={chartData}
                        xKey="x"
                        yKeys={["rxed", "sent", "timeouts"]}
                        domain={{ y: [0, maxVal + Math.ceil(maxVal * 0.1)] }}
                        domainPadding={{ left: 8, right: 8 }}
                        axisOptions={{
                            font: null,
                            tickCount: { x: 4, y: 4 },
                            formatXLabel: (val) => {
                                const idx = Math.round(val);
                                if (idx >= 0 && idx < chartData.length && chartData.length > 4 && idx % Math.floor(chartData.length / 4) === 0) {
                                    return chartData[idx]?.label || '';
                                }
                                return '';
                            },
                            labelColor: '#999',
                            lineColor: '#333',
                        }}
                    >
                        {({ points, chartBounds }) => (
                            <>
                                <VN.Bar points={points.rxed} chartBounds={chartBounds} color="#4ade80" roundedCorners={{ topLeft: 2, topRight: 2 }} />
                                <VN.Bar points={points.sent} chartBounds={chartBounds} color="#60a5fa" roundedCorners={{ topLeft: 2, topRight: 2 }} />
                                <VN.Bar points={points.timeouts} chartBounds={chartBounds} color="#f87171" roundedCorners={{ topLeft: 2, topRight: 2 }} />
                            </>
                        )}
                    </VN.CartesianChart>
                )}
            </SkiaChart>
            <View style={styles.legendRow}>
                <View style={[styles.legendDot, { backgroundColor: '#4ade80' }]} />
                <Text style={styles.legendText}>Received</Text>
                <View style={[styles.legendDot, { backgroundColor: '#60a5fa' }]} />
                <Text style={styles.legendText}>Sent</Text>
                <View style={[styles.legendDot, { backgroundColor: '#f87171' }]} />
                <Text style={styles.legendText}>Retries</Text>
            </View>
        </View>
    );
}

// Expandable chart for neighbor CQ stats over time
// CQ data contains absolute counters — compute deltas between consecutive readings
function NeighborChart({ dataPoints }) {
    const chartData = useMemo(() => {
        if (!dataPoints || dataPoints.length < 2) return null;
        const deltas = [];
        for (let i = 1; i < dataPoints.length; i++) {
            const prev = dataPoints[i - 1];
            const curr = dataPoints[i];
            // safeDelta: if curr < prev, counter rolled over (reboot), use curr as-is
            const safeDelta = (p, c) => c >= p ? c - p : c;
            deltas.push({
                x: i - 1,
                rxed: safeDelta(prev.l2Rxed || 0, curr.l2Rxed || 0),
                sent: safeDelta(prev.l2Sent || 0, curr.l2Sent || 0),
                timeouts: safeDelta(prev.l2Timeouts || 0, curr.l2Timeouts || 0),
                label: curr.timestamp ? new Date(curr.timestamp).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false }) : '',
            });
        }
        return deltas.length > 0 ? deltas : null;
    }, [dataPoints]);

    if (!chartData) {
        return (
            <View style={styles.expandedChart}>
                <Text style={styles.placeholderText}>Need at least 2 data points for chart</Text>
            </View>
        );
    }

    const maxVal = Math.max(1, ...chartData.map(d => Math.max(d.rxed, d.sent, d.timeouts)));

    return (
        <View style={styles.expandedChart}>
            <Text style={styles.chartLabel}>Packets per interval</Text>
            <SkiaChart style={styles.miniChartContainer}>
                {(VN) => (
                    <VN.CartesianChart
                        data={chartData}
                        xKey="x"
                        yKeys={["rxed", "sent", "timeouts"]}
                        domain={{ y: [0, maxVal + Math.ceil(maxVal * 0.1)] }}
                        domainPadding={{ left: 8, right: 8 }}
                        axisOptions={{
                            font: null,
                            tickCount: { x: 4, y: 4 },
                            formatXLabel: (val) => {
                                const idx = Math.round(val);
                                if (idx >= 0 && idx < chartData.length && chartData.length > 4 && idx % Math.floor(chartData.length / 4) === 0) {
                                    return chartData[idx]?.label || '';
                                }
                                return '';
                            },
                            labelColor: '#999',
                            lineColor: '#333',
                        }}
                    >
                        {({ points, chartBounds }) => (
                            <>
                                <VN.Bar points={points.rxed} chartBounds={chartBounds} color="#4ade80" roundedCorners={{ topLeft: 2, topRight: 2 }} />
                                <VN.Bar points={points.sent} chartBounds={chartBounds} color="#60a5fa" roundedCorners={{ topLeft: 2, topRight: 2 }} />
                                <VN.Bar points={points.timeouts} chartBounds={chartBounds} color="#f87171" roundedCorners={{ topLeft: 2, topRight: 2 }} />
                            </>
                        )}
                    </VN.CartesianChart>
                )}
            </SkiaChart>
            <View style={styles.legendRow}>
                <View style={[styles.legendDot, { backgroundColor: '#4ade80' }]} />
                <Text style={styles.legendText}>Received</Text>
                <View style={[styles.legendDot, { backgroundColor: '#60a5fa' }]} />
                <Text style={styles.legendText}>Sent</Text>
                <View style={[styles.legendDot, { backgroundColor: '#f87171' }]} />
                <Text style={styles.legendText}>Retries</Text>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#1e1e1e',
        padding: 15
    },
    sectionTitle: {
        color: '#fff',
        fontSize: 18,
        marginBottom: 10,
        fontWeight: 'bold',
        marginTop: 10
    },
    // Charts
    chartContainer: {
        height: 150,
        backgroundColor: '#222',
        marginBottom: 20,
        borderRadius: 5,
        borderWidth: 1,
        borderColor: '#333',
        padding: 8,
    },
    miniChartContainer: {
        height: 120,
        backgroundColor: '#1a1a1a',
        borderRadius: 4,
        padding: 4,
    },
    placeholderText: {
        color: '#555',
        textAlign: 'center',
        marginTop: 60,
    },
    expandedChart: {
        paddingHorizontal: 10,
        paddingVertical: 8,
        backgroundColor: '#1a1a1a',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
    },
    chartLabel: {
        color: '#999',
        fontSize: 11,
        marginBottom: 4,
    },
    legendRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: 4,
        gap: 4,
    },
    legendDot: {
        width: 8,
        height: 8,
        borderRadius: 4,
        marginLeft: 8,
    },
    legendText: {
        color: '#999',
        fontSize: 10,
    },
    // Table
    tableScroll: {
        marginBottom: 20,
    },
    tableRow: {
        flexDirection: 'row',
        borderBottomWidth: 1,
        borderBottomColor: '#333',
        paddingVertical: 8,
    },
    tableCell: {
        color: '#ddd',
        width: 80,
        textAlign: 'center',
        fontSize: 12,
    },
    tableHeader: {
        fontWeight: 'bold',
        color: '#fff',
        backgroundColor: '#252525'
    },
    emptyText: {
        color: '#777',
        fontStyle: 'italic',
        padding: 10
    },
    // System Stats
    systemStatsContainer: {
        backgroundColor: '#222',
        padding: 10,
        borderRadius: 5,
        borderWidth: 1,
        borderColor: '#333',
        marginBottom: 15,
    },
    systemStatText: {
        color: '#ccc',
        fontSize: 12,
        fontFamily: 'monospace',
        lineHeight: 20,
    },
    netromPort: {
        color: '#8b8bff',
        fontStyle: 'italic',
    },
    warnValue: {
        color: '#fbbf24',
    },
    errorValue: {
        color: '#f87171',
    },
});
