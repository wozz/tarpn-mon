import React, { useContext, useState } from 'react';
import { StyleSheet, Text, View, TextInput, Switch, TouchableOpacity, ScrollView, Modal, Alert } from 'react-native';
import { AppContext } from '../context/AppContext';
import appJson from '../../app.json';

// Helper to get status color
const getStatusColor = (state) => {
    switch (state) {
        case 'connected': return '#4ade80';
        case 'connecting': return '#fbbf24';
        case 'disconnecting': return '#fbbf24';
        case 'error': return '#ef4444';
        default: return '#666';
    }
};

// Helper to get status text
const getStatusText = (state) => {
    switch (state) {
        case 'connected': return 'Connected';
        case 'connecting': return 'Connecting...';
        case 'disconnecting': return 'Disconnecting...';
        case 'error': return 'Error';
        default: return 'Disconnected';
    }
};

export default function SettingsScreen() {
    const {
        settings, setSettings, visiblePorts, setVisiblePorts, uniquePorts, isConnected,
        featureStatus, featureSettings, connectFeature, disconnectFeature, updateFeatureSettings
    } = useContext(AppContext);

    // Connection modal state
    const [modalVisible, setModalVisible] = useState(false);
    const [modalFeature, setModalFeature] = useState(null);
    const [connectionConfig, setConnectionConfig] = useState({
        host: '',
        port: '',
        callsign: '',
        password: '',
        name: '',
        node: '',
    });

    // Open connection modal for a feature, pre-filled from backend settings
    const openConnectionModal = (feature) => {
        const fs = featureSettings[feature] || {};
        const opts = fs.options || {};

        setConnectionConfig({
            host: fs.host || settings.host || 'localhost',
            port: String(fs.port || (feature === 'chat' ? 8513 : 8010)),
            callsign: fs.callsign || '',
            password: fs.password || '',
            name: opts.name || '',
            node: opts.node || '',
        });
        setModalFeature(feature);
        setModalVisible(true);
    };

    // Build options map for the current modal feature
    const buildOptions = () => {
        const options = {};
        if (modalFeature === 'chat') {
            if (connectionConfig.name) options.name = connectionConfig.name;
            if (connectionConfig.node) options.node = connectionConfig.node;
        }
        return options;
    };

    // Handle save & connect action
    const handleSaveAndConnect = () => {
        if (!connectionConfig.callsign) {
            Alert.alert('Error', 'Callsign is required');
            return;
        }

        updateFeatureSettings(modalFeature, {
            enabled: true,
            host: connectionConfig.host,
            port: parseInt(connectionConfig.port) || 8010,
            callsign: connectionConfig.callsign,
            password: connectionConfig.password,
            options: buildOptions(),
        });

        setModalVisible(false);
    };

    // Handle save without connecting
    const handleSave = () => {
        // Get current enabled state — preserve it
        const fs = featureSettings[modalFeature] || {};
        updateFeatureSettings(modalFeature, {
            enabled: fs.enabled || false,
            host: connectionConfig.host,
            port: parseInt(connectionConfig.port) || 8010,
            callsign: connectionConfig.callsign,
            password: connectionConfig.password,
            options: buildOptions(),
        });

        setModalVisible(false);
    };

    // Check if a feature has saved settings (callsign configured)
    const hasSettings = (feature) => {
        const fs = featureSettings[feature];
        return fs && fs.callsign;
    };

    // Render feature status card
    const renderFeatureCard = (feature, label) => {
        const status = featureStatus[feature] || { state: 'disconnected' };
        const isConnectedFeature = status.state === 'connected';
        const isTransitioning = status.state === 'connecting' || status.state === 'disconnecting';

        return (
            <View key={feature} style={styles.featureCard}>
                <View style={styles.featureHeader}>
                    <Text style={styles.featureLabel}>{label}</Text>
                    <View style={[styles.statusBadge, { backgroundColor: getStatusColor(status.state) }]}>
                        <Text style={styles.statusBadgeText}>{getStatusText(status.state)}</Text>
                    </View>
                </View>

                {isConnectedFeature && (
                    <View style={styles.featureInfo}>
                        <Text style={styles.featureInfoText}>
                            {status.callsign} @ {status.host}:{status.port}
                        </Text>
                    </View>
                )}

                {!isConnectedFeature && hasSettings(feature) && (
                    <View style={styles.featureInfo}>
                        <Text style={styles.featureInfoText}>
                            {featureSettings[feature].callsign} @ {featureSettings[feature].host}:{featureSettings[feature].port}
                        </Text>
                    </View>
                )}

                {status.error && (
                    <Text style={styles.errorText}>{status.error}</Text>
                )}

                <View style={styles.featureActions}>
                    {!isConnectedFeature && !isTransitioning && hasSettings(feature) && (
                        <TouchableOpacity
                            style={styles.connectButton}
                            onPress={() => connectFeature(feature)}
                        >
                            <Text style={styles.connectButtonText}>Connect</Text>
                        </TouchableOpacity>
                    )}
                    {!isConnectedFeature && !isTransitioning && (
                        <TouchableOpacity
                            style={[styles.settingsButton, hasSettings(feature) && { marginLeft: 10 }]}
                            onPress={() => openConnectionModal(feature)}
                        >
                            <Text style={styles.settingsButtonText}>Settings</Text>
                        </TouchableOpacity>
                    )}
                    {isConnectedFeature && (
                        <>
                            <TouchableOpacity
                                style={styles.disconnectButton}
                                onPress={() => disconnectFeature(feature)}
                            >
                                <Text style={styles.disconnectButtonText}>Disconnect</Text>
                            </TouchableOpacity>
                            <TouchableOpacity
                                style={[styles.settingsButton, { marginLeft: 10 }]}
                                onPress={() => openConnectionModal(feature)}
                            >
                                <Text style={styles.settingsButtonText}>Settings</Text>
                            </TouchableOpacity>
                        </>
                    )}
                    {isTransitioning && (
                        <Text style={styles.transitioningText}>
                            {status.state === 'connecting' ? 'Connecting...' : 'Disconnecting...'}
                        </Text>
                    )}
                </View>
            </View>
        );
    };

    return (
        <ScrollView style={styles.container}>
            {/* Connection Settings Modal */}
            <Modal
                animationType="slide"
                transparent={true}
                visible={modalVisible}
                onRequestClose={() => setModalVisible(false)}
            >
                <View style={styles.modalOverlay}>
                    <View style={styles.modalContent}>
                        <Text style={styles.modalTitle}>
                            {modalFeature?.toUpperCase()} Settings
                        </Text>

                        <Text style={styles.inputLabel}>Host</Text>
                        <TextInput
                            style={styles.textInput}
                            value={connectionConfig.host}
                            onChangeText={(text) => setConnectionConfig({ ...connectionConfig, host: text })}
                            autoCapitalize="none"
                            placeholder="192.168.1.100"
                            placeholderTextColor="#555"
                        />

                        <Text style={styles.inputLabel}>Port</Text>
                        <TextInput
                            style={styles.textInput}
                            value={connectionConfig.port}
                            onChangeText={(text) => setConnectionConfig({ ...connectionConfig, port: text })}
                            keyboardType="numeric"
                            placeholder="8513"
                            placeholderTextColor="#555"
                        />

                        <Text style={styles.inputLabel}>Callsign</Text>
                        <TextInput
                            style={styles.textInput}
                            value={connectionConfig.callsign}
                            onChangeText={(text) => setConnectionConfig({ ...connectionConfig, callsign: text })}
                            autoCapitalize="none"
                            placeholder="N0CALL"
                            placeholderTextColor="#555"
                        />

                        <Text style={styles.inputLabel}>Password</Text>
                        <TextInput
                            style={styles.textInput}
                            value={connectionConfig.password}
                            onChangeText={(text) => setConnectionConfig({ ...connectionConfig, password: text })}
                            secureTextEntry
                            placeholder="Password"
                            placeholderTextColor="#555"
                        />

                        {modalFeature === 'chat' && (
                            <>
                                <Text style={styles.inputLabel}>Display Name (optional)</Text>
                                <TextInput
                                    style={styles.textInput}
                                    value={connectionConfig.name}
                                    onChangeText={(text) => setConnectionConfig({ ...connectionConfig, name: text })}
                                    placeholder="Your Name"
                                    placeholderTextColor="#555"
                                />

                                <Text style={styles.inputLabel}>Node Identifier (optional)</Text>
                                <TextInput
                                    style={styles.textInput}
                                    value={connectionConfig.node}
                                    onChangeText={(text) => setConnectionConfig({ ...connectionConfig, node: text })}
                                    placeholder="e.g., BOT or leave blank for callsign"
                                    placeholderTextColor="#555"
                                    autoCapitalize="characters"
                                />
                            </>
                        )}

                        <View style={styles.modalButtons}>
                            <TouchableOpacity
                                style={styles.cancelButton}
                                onPress={() => setModalVisible(false)}
                            >
                                <Text style={styles.cancelButtonText}>Cancel</Text>
                            </TouchableOpacity>
                            <TouchableOpacity
                                style={styles.saveButton}
                                onPress={handleSave}
                            >
                                <Text style={styles.saveButtonText}>Save</Text>
                            </TouchableOpacity>
                            <TouchableOpacity
                                style={styles.modalConnectButton}
                                onPress={handleSaveAndConnect}
                            >
                                <Text style={styles.connectButtonText}>Save & Connect</Text>
                            </TouchableOpacity>
                        </View>
                    </View>
                </View>
            </Modal>

            <View style={styles.section}>
                <Text style={styles.sectionHeader}>Server Connection ({isConnected ? "Connected" : "Disconnected"})</Text>

                <Text style={styles.inputLabel}>Host IP / Domain</Text>
                <TextInput
                    style={styles.textInput}
                    value={settings.host}
                    onChangeText={(text) => setSettings({...settings, host: text})}
                    autoCapitalize="none"
                    placeholder="10.0.2.2 or 192.168.x.x"
                    placeholderTextColor="#555"
                />

                <Text style={styles.inputLabel}>Port</Text>
                <TextInput
                    style={styles.textInput}
                    value={settings.port}
                    onChangeText={(text) => setSettings({...settings, port: text})}
                    keyboardType="numeric"
                    placeholder="8212"
                    placeholderTextColor="#555"
                />
            </View>

            <View style={styles.section}>
                <Text style={styles.sectionHeader}>Feature Connections</Text>
                <Text style={styles.sectionHint}>
                    Connection settings are stored on the backend. All clients share the same configuration.
                </Text>
                {renderFeatureCard('chat', 'Chat')}
                {renderFeatureCard('bbs', 'BBS / Mail')}
                {renderFeatureCard('node', 'Node Console')}
            </View>

            <View style={styles.section}>
                <Text style={styles.sectionHeader}>Preferences</Text>

                <View style={styles.settingRow}>
                    <Text style={styles.settingLabel}>Auto-scroll Logs</Text>
                    <Switch
                        trackColor={{ false: "#767577", true: "#4ade80" }}
                        thumbColor={settings.autoScroll ? "#fff" : "#f4f3f4"}
                        onValueChange={(val) => setSettings({...settings, autoScroll: !!val})}
                        value={!!settings.autoScroll}
                    />
                </View>

                <View style={styles.settingRow}>
                    <Text style={styles.settingLabel}>Hide TNC{'>'}USB Packets</Text>
                    <Switch
                        trackColor={{ false: "#767577", true: "#4ade80" }}
                        thumbColor={settings.hideUSBRoutes ? "#fff" : "#f4f3f4"}
                        onValueChange={(val) => setSettings({...settings, hideUSBRoutes: !!val})}
                        value={!!settings.hideUSBRoutes}
                    />
                </View>

                <View style={styles.settingRow}>
                    <View style={styles.settingLabelContainer}>
                        <Text style={styles.settingLabel}>Compact Screen Layout</Text>
                        <Text style={styles.settingHint}>Shorter port labels (e.g., Tx1 instead of Tx Port=1)</Text>
                    </View>
                    <Switch
                        trackColor={{ false: "#767577", true: "#4ade80" }}
                        thumbColor={settings.compactLayout ? "#fff" : "#f4f3f4"}
                        onValueChange={(val) => setSettings({...settings, compactLayout: !!val})}
                        value={!!settings.compactLayout}
                    />
                </View>
            </View>

            <View style={styles.section}>
                <Text style={styles.sectionHeader}>Port Filters (Show/Hide)</Text>
                <View style={styles.portFilters}>
                    {Array.from(uniquePorts).sort((a,b)=>parseInt(a)-parseInt(b)).map(port => (
                        <TouchableOpacity
                            key={port}
                            style={[styles.portTag, visiblePorts.includes(port) && styles.portTagSelected]}
                            onPress={() => {
                                setVisiblePorts(prev =>
                                    prev.includes(port) ? prev.filter(p => p !== port) : [...prev, port]
                                )
                            }}
                        >
                            <Text style={[styles.portTagText, visiblePorts.includes(port) && styles.portTagTextSelected]}>
                                {port}
                            </Text>
                        </TouchableOpacity>
                    ))}
                    {uniquePorts.size === 0 && (
                        <Text style={styles.emptyText}>No ports detected yet. Connect to a backend to populate list.</Text>
                    )}
                </View>
            </View>

            <View style={styles.footer}>
                <Text style={styles.versionText}>TARPN Terminal v{appJson.expo.version}</Text>
            </View>
        </ScrollView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#1e1e1e',
        padding: 20
    },
    section: {
        marginBottom: 30
    },
    sectionHeader: {
        color: '#4ade80',
        fontSize: 16,
        fontWeight: 'bold',
        marginBottom: 15,
        borderBottomWidth: 1,
        borderBottomColor: '#333',
        paddingBottom: 5
    },
    sectionHint: {
        color: '#888',
        fontSize: 12,
        marginBottom: 15,
    },
    inputLabel: {
        color: '#aaa',
        fontSize: 12,
        marginBottom: 5,
        marginTop: 10
    },
    textInput: {
        backgroundColor: '#252525',
        color: '#fff',
        padding: 12,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: '#444'
    },
    settingRow: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginTop: 15,
        paddingVertical: 5,
    },
    settingLabel: {
        color: '#ddd',
        fontSize: 16
    },
    settingLabelContainer: {
        flex: 1,
        marginRight: 10
    },
    settingHint: {
        color: '#888',
        fontSize: 12,
        marginTop: 2
    },
    portFilters: {
        flexDirection: 'row',
        flexWrap: 'wrap'
    },
    portTag: {
        paddingHorizontal: 12,
        paddingVertical: 8,
        borderRadius: 20,
        borderWidth: 1,
        borderColor: '#555',
        marginRight: 10,
        marginBottom: 10,
        backgroundColor: '#252525'
    },
    portTagSelected: {
        backgroundColor: '#4ade80',
        borderColor: '#4ade80'
    },
    portTagText: {
        color: '#888',
        fontSize: 14
    },
    portTagTextSelected: {
        color: '#000',
        fontWeight: 'bold'
    },
    emptyText: {
        color: '#666',
        fontStyle: 'italic'
    },
    footer: {
        alignItems: 'center',
        paddingBottom: 40
    },
    versionText: {
        color: '#444'
    },
    // Feature card styles
    featureCard: {
        backgroundColor: '#252525',
        borderRadius: 8,
        padding: 15,
        marginBottom: 12,
        borderWidth: 1,
        borderColor: '#333',
    },
    featureHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 8,
    },
    featureLabel: {
        color: '#fff',
        fontSize: 16,
        fontWeight: '600',
    },
    statusBadge: {
        paddingHorizontal: 10,
        paddingVertical: 4,
        borderRadius: 12,
    },
    statusBadgeText: {
        color: '#000',
        fontSize: 12,
        fontWeight: 'bold',
    },
    featureInfo: {
        marginBottom: 8,
    },
    featureInfoText: {
        color: '#888',
        fontSize: 13,
    },
    featureActions: {
        flexDirection: 'row',
        justifyContent: 'flex-end',
    },
    connectButton: {
        backgroundColor: '#4ade80',
        paddingHorizontal: 20,
        paddingVertical: 8,
        borderRadius: 6,
        alignItems: 'center',
    },
    connectButtonText: {
        color: '#000',
        fontWeight: 'bold',
        fontSize: 14,
    },
    settingsButton: {
        backgroundColor: '#444',
        paddingHorizontal: 20,
        paddingVertical: 8,
        borderRadius: 6,
        alignItems: 'center',
    },
    settingsButtonText: {
        color: '#fff',
        fontWeight: 'bold',
        fontSize: 14,
    },
    saveButton: {
        backgroundColor: '#444',
        paddingHorizontal: 20,
        paddingVertical: 12,
        borderRadius: 6,
        marginRight: 10,
        alignItems: 'center',
    },
    saveButtonText: {
        color: '#fff',
        fontWeight: 'bold',
        fontSize: 14,
    },
    modalConnectButton: {
        backgroundColor: '#4ade80',
        paddingHorizontal: 20,
        paddingVertical: 12,
        borderRadius: 6,
        flex: 1,
        alignItems: 'center',
    },
    disconnectButton: {
        backgroundColor: '#ef4444',
        paddingHorizontal: 20,
        paddingVertical: 8,
        borderRadius: 6,
    },
    disconnectButtonText: {
        color: '#fff',
        fontWeight: 'bold',
        fontSize: 14,
    },
    transitioningText: {
        color: '#fbbf24',
        fontSize: 14,
        fontStyle: 'italic',
    },
    errorText: {
        color: '#ef4444',
        fontSize: 12,
        marginBottom: 8,
    },
    // Modal styles
    modalOverlay: {
        flex: 1,
        backgroundColor: 'rgba(0, 0, 0, 0.7)',
        justifyContent: 'center',
        alignItems: 'center',
        padding: 20,
    },
    modalContent: {
        backgroundColor: '#1e1e1e',
        borderRadius: 12,
        padding: 20,
        width: '100%',
        maxWidth: 400,
        borderWidth: 1,
        borderColor: '#333',
    },
    modalTitle: {
        color: '#4ade80',
        fontSize: 18,
        fontWeight: 'bold',
        marginBottom: 15,
        textAlign: 'center',
    },
    modalButtons: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        marginTop: 20,
    },
    cancelButton: {
        backgroundColor: '#333',
        paddingHorizontal: 20,
        paddingVertical: 12,
        borderRadius: 6,
        marginRight: 10,
        alignItems: 'center',
    },
    cancelButtonText: {
        color: '#fff',
        fontWeight: 'bold',
        fontSize: 14,
    },
});
