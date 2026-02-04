package main

import (
	"fmt"
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metric labels
const (
	labelPort     = "port"
	labelCallsign = "callsign"
	labelFeature  = "feature"
	labelState    = "state"
)

var (
	// TNC metrics - per port gauges/counters
	tncUptimeSeconds = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_uptime_seconds",
			Help: "TNC uptime in seconds",
		},
		[]string{labelPort},
	)

	tncAX25ReceivedPackets = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_ax25_received_packets_total",
			Help: "Total AX.25 packets received by TNC",
		},
		[]string{labelPort},
	)

	tncIL2PCorrectablePackets = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_il2p_correctable_packets_total",
			Help: "Total IL2P packets with correctable errors",
		},
		[]string{labelPort},
	)

	tncIL2PUncorrectablePackets = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_il2p_uncorrectable_packets_total",
			Help: "Total IL2P packets with uncorrectable errors",
		},
		[]string{labelPort},
	)

	tncTransmitPackets = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_transmit_packets_total",
			Help: "Total packets transmitted by TNC",
		},
		[]string{labelPort},
	)

	tncPTTOnTimeSeconds = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_ptt_on_time_seconds",
			Help: "Total PTT (Push-To-Talk) on time in seconds",
		},
		[]string{labelPort},
	)

	tncDCDOnTimeSeconds = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_dcd_on_time_seconds",
			Help: "Total DCD (Data Carrier Detect) on time in seconds",
		},
		[]string{labelPort},
	)

	tncReceivedDataBytes = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_received_data_bytes_total",
			Help: "Total data bytes received by TNC",
		},
		[]string{labelPort},
	)

	tncTransmitDataBytes = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_transmit_data_bytes_total",
			Help: "Total data bytes transmitted by TNC",
		},
		[]string{labelPort},
	)

	tncFECBytesCorrected = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_fec_bytes_corrected_total",
			Help: "Total FEC bytes corrected by TNC",
		},
		[]string{labelPort},
	)

	tncMainLoopCycles = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_main_loop_cycles_total",
			Help: "Total main loop cycles executed by TNC",
		},
		[]string{labelPort},
	)

	tncPreambleWordCount = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_tnc_preamble_word_count",
			Help: "TNC preamble word count setting",
		},
		[]string{labelPort},
	)

	// TARPNstat metrics - per port and callsign
	tarpnStatTx = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_stat_tx_total",
			Help: "TARPNstat transmitted packet count",
		},
		[]string{labelPort, labelCallsign},
	)

	tarpnStatRetries = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_stat_retries_total",
			Help: "TARPNstat retry count",
		},
		[]string{labelPort, labelCallsign},
	)

	tarpnStatBuffer = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_stat_buffer",
			Help: "TARPNstat buffer level",
		},
		[]string{labelPort, labelCallsign},
	)

	// Application metrics - WebSocket clients
	websocketClientsTotal = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_websocket_clients",
			Help: "Number of connected WebSocket clients (monitor)",
		},
	)

	websocketChatClientsTotal = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_websocket_chat_clients",
			Help: "Number of connected WebSocket clients (chat)",
		},
	)

	websocketBBSClientsTotal = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_websocket_bbs_clients",
			Help: "Number of connected WebSocket clients (BBS)",
		},
	)

	websocketNodeClientsTotal = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_websocket_node_clients",
			Help: "Number of connected WebSocket clients (node)",
		},
	)

	// Buffer metrics
	monitorBufferMessages = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_monitor_buffer_messages",
			Help: "Number of messages in the monitor buffer",
		},
	)

	monitorBufferCapacity = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_monitor_buffer_capacity",
			Help: "Capacity of the monitor buffer",
		},
	)

	// Message counters
	monitorMessagesTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "tarpn_monitor_messages_total",
			Help: "Total monitor messages received",
		},
	)

	tncDataMessagesTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "tarpn_tnc_data_messages_total",
			Help: "Total TNC data messages received",
		},
		[]string{labelPort},
	)

	tarpnStatMessagesTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "tarpn_stat_messages_total",
			Help: "Total TARPNstat messages received",
		},
		[]string{labelPort},
	)

	// Feature connection state (1 = current state)
	featureState = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_feature_state",
			Help: "Feature connection state (1 = current state)",
		},
		[]string{labelFeature, labelState},
	)

	// Connection metrics
	monitorConnectionState = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_monitor_connection_state",
			Help: "Monitor connection state (0=disconnected, 1=connecting, 2=connected, 3=error)",
		},
	)

	monitorReconnectsTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "tarpn_monitor_reconnects_total",
			Help: "Total monitor reconnection attempts",
		},
	)

	// L2 link stats - per port gauges from LinBPQ S command
	l2FramesRxed = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_frames_rxed",
			Help: "L2 frames received per port",
		},
		[]string{labelPort},
	)

	l2FramesSent = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_frames_sent",
			Help: "L2 frames sent per port",
		},
		[]string{labelPort},
	)

	l2Timeouts = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_timeouts",
			Help: "L2 timeouts per port",
		},
		[]string{labelPort},
	)

	l2REJRxed = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_rej_rxed",
			Help: "REJ frames received per port",
		},
		[]string{labelPort},
	)

	l2RXOutOfSeq = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_rx_out_of_seq",
			Help: "RX out of sequence frames per port",
		},
		[]string{labelPort},
	)

	l2RXCRCErrors = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_rx_crc_errors",
			Help: "RX CRC errors per port",
		},
		[]string{labelPort},
	)

	l2FRMRsSent = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_frmrs_sent",
			Help: "FRMRs sent per port",
		},
		[]string{labelPort},
	)

	l2FRMRsReceived = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_frmrs_received",
			Help: "FRMRs received per port",
		},
		[]string{labelPort},
	)

	l2FramesAbandoned = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_frames_abandoned",
			Help: "Frames abandoned per port",
		},
		[]string{labelPort},
	)

	l2ActiveTxPct = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_active_tx_pct",
			Help: "Active TX percentage per port",
		},
		[]string{labelPort},
	)

	l2ActiveBusyPct = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_l2_active_busy_pct",
			Help: "Active busy percentage per port",
		},
		[]string{labelPort},
	)

	// System-wide BPQ stats
	bpqBuffersCurrent = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_bpq_buffers_current",
			Help: "Current BPQ buffer count",
		},
	)

	bpqKnownNodes = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_bpq_known_nodes",
			Help: "Number of known nodes",
		},
	)

	bpqL3Relayed = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_bpq_l3_relayed",
			Help: "L3 frames relayed",
		},
	)

	// Stats collector health
	statsConnectionState = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "tarpn_stats_connection_state",
			Help: "Stats collector connection state (0=disconnected, 1=connected)",
		},
	)

	statsPollsTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "tarpn_stats_polls_total",
			Help: "Total successful stats polls",
		},
	)

	statsPollErrorsTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "tarpn_stats_poll_errors_total",
			Help: "Total stats poll errors",
		},
	)

	// Build info
	buildInfo = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tarpn_build_info",
			Help: "Build information",
		},
		[]string{"version"},
	)
)

func init() {
	// Register all metrics
	prometheus.MustRegister(
		// TNC metrics
		tncUptimeSeconds,
		tncAX25ReceivedPackets,
		tncIL2PCorrectablePackets,
		tncIL2PUncorrectablePackets,
		tncTransmitPackets,
		tncPTTOnTimeSeconds,
		tncDCDOnTimeSeconds,
		tncReceivedDataBytes,
		tncTransmitDataBytes,
		tncFECBytesCorrected,
		tncMainLoopCycles,
		tncPreambleWordCount,

		// TARPNstat metrics
		tarpnStatTx,
		tarpnStatRetries,
		tarpnStatBuffer,

		// WebSocket client metrics
		websocketClientsTotal,
		websocketChatClientsTotal,
		websocketBBSClientsTotal,
		websocketNodeClientsTotal,

		// Buffer metrics
		monitorBufferMessages,
		monitorBufferCapacity,

		// Message counters
		monitorMessagesTotal,
		tncDataMessagesTotal,
		tarpnStatMessagesTotal,

		// Feature state
		featureState,

		// Connection metrics
		monitorConnectionState,
		monitorReconnectsTotal,

		// L2 link stats
		l2FramesRxed,
		l2FramesSent,
		l2Timeouts,
		l2REJRxed,
		l2RXOutOfSeq,
		l2RXCRCErrors,
		l2FRMRsSent,
		l2FRMRsReceived,
		l2FramesAbandoned,
		l2ActiveTxPct,
		l2ActiveBusyPct,

		// System BPQ stats
		bpqBuffersCurrent,
		bpqKnownNodes,
		bpqL3Relayed,

		// Stats collector health
		statsConnectionState,
		statsPollsTotal,
		statsPollErrorsTotal,

		// Build info
		buildInfo,
	)

	// Set build info
	buildInfo.WithLabelValues(Version).Set(1)
}

// UpdateTNCMetrics updates TNC metrics from parsed TNC data
func UpdateTNCMetrics(port string, data *tncData) {
	tncUptimeSeconds.WithLabelValues(port).Set(float64(data.UptimeMillis) / 1000.0)
	tncAX25ReceivedPackets.WithLabelValues(port).Set(float64(data.AX25ReceivedPackets))
	tncIL2PCorrectablePackets.WithLabelValues(port).Set(float64(data.IL2PCorrectablePackets))
	tncIL2PUncorrectablePackets.WithLabelValues(port).Set(float64(data.IL2PUncorrectablePackets))
	tncTransmitPackets.WithLabelValues(port).Set(float64(data.TransmitPackets))
	tncPTTOnTimeSeconds.WithLabelValues(port).Set(float64(data.PTTOnTimeMillis) / 1000.0)
	tncDCDOnTimeSeconds.WithLabelValues(port).Set(float64(data.DCDOnTimeMillis) / 1000.0)
	tncReceivedDataBytes.WithLabelValues(port).Set(float64(data.ReceivedDataBytes))
	tncTransmitDataBytes.WithLabelValues(port).Set(float64(data.TransmitDataBytes))
	tncFECBytesCorrected.WithLabelValues(port).Set(float64(data.FECBytesCorrected))
	tncMainLoopCycles.WithLabelValues(port).Set(float64(data.MainLoopCycleCount))
	tncPreambleWordCount.WithLabelValues(port).Set(float64(data.PreambleWordCount))
}

// UpdateTARPNStatMetrics updates TARPNstat metrics from parsed data
func UpdateTARPNStatMetrics(port string, stat *TARPNStat) {
	tarpnStatTx.WithLabelValues(port, stat.Callsign).Set(float64(stat.Tx))
	tarpnStatRetries.WithLabelValues(port, stat.Callsign).Set(float64(stat.Ret))
	tarpnStatBuffer.WithLabelValues(port, stat.Callsign).Set(float64(stat.Buf))
}

// UpdateFeatureStateMetrics updates the feature state metric
func UpdateFeatureStateMetrics(feature string, currentState FeatureState) {
	// Reset all states for this feature
	states := []FeatureState{StateDisconnected, StateConnecting, StateConnected, StateDisconnecting, StateError}
	for _, s := range states {
		if s == currentState {
			featureState.WithLabelValues(feature, string(s)).Set(1)
		} else {
			featureState.WithLabelValues(feature, string(s)).Set(0)
		}
	}
}

// UpdateWebSocketClientCount updates the WebSocket client count metric
func UpdateWebSocketClientCount() {
	clientsMu.RLock()
	count := len(clients)
	clientsMu.RUnlock()
	websocketClientsTotal.Set(float64(count))
}

// UpdateChatClientCount updates the chat WebSocket client count metric
func UpdateChatClientCount() {
	chatClientsMu.RLock()
	count := len(chatClients)
	chatClientsMu.RUnlock()
	websocketChatClientsTotal.Set(float64(count))
}

// UpdateBBSClientCount updates the BBS WebSocket client count metric
func UpdateBBSClientCount() {
	bbsClientsMu.RLock()
	count := len(bbsClients)
	bbsClientsMu.RUnlock()
	websocketBBSClientsTotal.Set(float64(count))
}

// UpdateNodeClientCount updates the node WebSocket client count metric
func UpdateNodeClientCount() {
	nodeClientsMu.RLock()
	count := len(nodeClients)
	nodeClientsMu.RUnlock()
	websocketNodeClientsTotal.Set(float64(count))
}

// UpdateBufferMetrics updates the buffer metrics
func UpdateBufferMetrics() {
	if dataBuffer != nil {
		_, _, count := dataBuffer.getInfo()
		monitorBufferMessages.Set(float64(count))
	}
	monitorBufferCapacity.Set(float64(bufferSize))
}

// SetMonitorConnectionState sets the monitor connection state metric
func SetMonitorConnectionState(s connState) {
	monitorConnectionState.Set(float64(s))
}

// IncrementMonitorReconnects increments the reconnection counter
func IncrementMonitorReconnects() {
	monitorReconnectsTotal.Inc()
}

// IncrementMonitorMessages increments the monitor message counter
func IncrementMonitorMessages() {
	monitorMessagesTotal.Inc()
}

// IncrementTNCDataMessages increments the TNC data message counter for a port
func IncrementTNCDataMessages(port string) {
	tncDataMessagesTotal.WithLabelValues(port).Inc()
}

// IncrementTARPNStatMessages increments the TARPNstat message counter for a port
func IncrementTARPNStatMessages(port string) {
	tarpnStatMessagesTotal.WithLabelValues(port).Inc()
}

// UpdateLinkStatsMetrics updates L2 link stats Prometheus metrics from a snapshot
func UpdateLinkStatsMetrics(snap *LinkStatsSnapshot) {
	portLabel := func(pn int) string {
		return fmt.Sprintf("%d", pn)
	}

	for pn, ps := range snap.Ports {
		p := portLabel(pn)
		l2FramesRxed.WithLabelValues(p).Set(float64(ps.L2Rxed))
		l2FramesSent.WithLabelValues(p).Set(float64(ps.L2Sent))
		l2Timeouts.WithLabelValues(p).Set(float64(ps.L2Timeouts))
		l2REJRxed.WithLabelValues(p).Set(float64(ps.REJRxed))
		l2RXOutOfSeq.WithLabelValues(p).Set(float64(ps.RXOutOfSeq))
		l2RXCRCErrors.WithLabelValues(p).Set(float64(ps.RXCRCErrors))
		l2FRMRsSent.WithLabelValues(p).Set(float64(ps.FRMRsSent))
		l2FRMRsReceived.WithLabelValues(p).Set(float64(ps.FRMRsReceived))
		l2FramesAbandoned.WithLabelValues(p).Set(float64(ps.FramesAbandoned))
		l2ActiveTxPct.WithLabelValues(p).Set(float64(ps.ActiveTxPct))
		l2ActiveBusyPct.WithLabelValues(p).Set(float64(ps.ActiveBusyPct))
	}

	bpqBuffersCurrent.Set(float64(snap.System.BuffersCur))
	bpqKnownNodes.Set(float64(snap.System.KnownNodes))
	bpqL3Relayed.Set(float64(snap.System.L3Relayed))

	statsPollsTotal.Inc()
}

// SetupMetricsHandler registers the /metrics endpoint
func SetupMetricsHandler() {
	http.Handle("/metrics", promhttp.Handler())
}
