import React, { useState, useRef, useEffect } from 'react';
import { StyleSheet, Text, View, TextInput, TouchableOpacity, ScrollView, Switch } from 'react-native';

const FRAME_TYPES = ['I', 'UI', 'SABM', 'DISC', 'UA', 'RR', 'REJ', 'Other'];
const DIRECTIONS = [
  { label: 'All', value: 'both' },
  { label: 'Tx', value: 'tx' },
  { label: 'Rx', value: 'rx' },
];

export const DEFAULT_FILTER_STATE = {
  callsign: '',
  frameTypes: [],
  direction: 'both',
  sessionId: null,
  hideRetries: false,
};

export default function FilterBar({ filterState, setFilterState, visible }) {
  const [localCallsign, setLocalCallsign] = useState(filterState.callsign || '');
  const debounceTimer = useRef(null);

  // Sync local callsign when filterState changes externally (e.g. clear)
  useEffect(() => {
    setLocalCallsign(filterState.callsign || '');
  }, [filterState.callsign]);

  // Cleanup debounce timer on unmount
  useEffect(() => {
    return () => {
      if (debounceTimer.current) {
        clearTimeout(debounceTimer.current);
      }
    };
  }, []);

  if (!visible) return null;

  const handleCallsignChange = (text) => {
    setLocalCallsign(text);
    if (debounceTimer.current) {
      clearTimeout(debounceTimer.current);
    }
    debounceTimer.current = setTimeout(() => {
      setFilterState(prev => ({ ...prev, callsign: text.trim().toUpperCase() }));
    }, 300);
  };

  const toggleFrameType = (type) => {
    setFilterState(prev => {
      const types = prev.frameTypes.includes(type)
        ? prev.frameTypes.filter(t => t !== type)
        : [...prev.frameTypes, type];
      return { ...prev, frameTypes: types };
    });
  };

  const setDirection = (dir) => {
    setFilterState(prev => ({ ...prev, direction: dir }));
  };

  const toggleHideRetries = (value) => {
    setFilterState(prev => ({ ...prev, hideRetries: value }));
  };

  const clearAll = () => {
    setFilterState({ ...DEFAULT_FILTER_STATE });
  };

  return (
    <View style={styles.container}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
      >
        {/* Callsign Filter */}
        <TextInput
          style={styles.callsignInput}
          value={localCallsign}
          onChangeText={handleCallsignChange}
          placeholder="Callsign..."
          placeholderTextColor="#666"
          autoCapitalize="characters"
          autoCorrect={false}
        />

        {/* Separator */}
        <View style={styles.separator} />

        {/* Frame Type Chips */}
        {FRAME_TYPES.map(type => {
          const active = filterState.frameTypes.includes(type);
          return (
            <TouchableOpacity
              key={type}
              style={[styles.chip, active && styles.chipActiveGreen]}
              onPress={() => toggleFrameType(type)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {type}
              </Text>
            </TouchableOpacity>
          );
        })}

        {/* Separator */}
        <View style={styles.separator} />

        {/* Direction Toggle */}
        {DIRECTIONS.map(dir => {
          const active = filterState.direction === dir.value;
          return (
            <TouchableOpacity
              key={dir.value}
              style={[styles.chip, active && styles.chipActiveBlue]}
              onPress={() => setDirection(dir.value)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {dir.label}
              </Text>
            </TouchableOpacity>
          );
        })}

        {/* Separator */}
        <View style={styles.separator} />

        {/* Hide Retries */}
        <View style={styles.switchContainer}>
          <Text style={styles.switchLabel}>Hide Retries</Text>
          <Switch
            value={filterState.hideRetries}
            onValueChange={toggleHideRetries}
            trackColor={{ false: '#555', true: '#4ade80' }}
            thumbColor={filterState.hideRetries ? '#fff' : '#aaa'}
            style={styles.switch}
          />
        </View>

        {/* Separator */}
        <View style={styles.separator} />

        {/* Clear All */}
        <TouchableOpacity onPress={clearAll} style={styles.clearButton}>
          <Text style={styles.clearText}>Clear</Text>
        </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#2a2a2a',
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#333',
  },
  scrollContent: {
    alignItems: 'center',
  },
  callsignInput: {
    backgroundColor: '#333',
    color: '#fff',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    fontSize: 11,
    fontFamily: '"Courier New", Courier, monospace',
    width: 100,
  },
  separator: {
    width: 1,
    height: 18,
    backgroundColor: '#444',
    marginHorizontal: 8,
  },
  chip: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#555',
    marginRight: 4,
  },
  chipActiveGreen: {
    backgroundColor: '#4ade80',
    borderColor: '#4ade80',
  },
  chipActiveBlue: {
    backgroundColor: '#3b82f6',
    borderColor: '#3b82f6',
  },
  chipText: {
    fontSize: 11,
    fontFamily: '"Courier New", Courier, monospace',
    color: '#aaa',
  },
  chipTextActive: {
    color: '#fff',
  },
  switchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  switchLabel: {
    fontSize: 11,
    fontFamily: '"Courier New", Courier, monospace',
    color: '#aaa',
    marginRight: 4,
  },
  switch: {
    transform: [{ scaleX: 0.7 }, { scaleY: 0.7 }],
  },
  clearButton: {
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  clearText: {
    fontSize: 11,
    fontFamily: '"Courier New", Courier, monospace',
    color: '#888',
  },
});
