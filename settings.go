package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// FeatureSettings contains connection settings for a single feature (chat/bbs/node).
type FeatureSettings struct {
	Enabled  bool              `json:"enabled"`
	Host     string            `json:"host"`
	Port     int               `json:"port"`
	Callsign string            `json:"callsign"`
	Password string            `json:"password"`
	Options  map[string]string `json:"options,omitempty"`
}

// ToFeatureConfig converts FeatureSettings to the existing FeatureConfig type
// used by the connect functions.
func (fs *FeatureSettings) ToFeatureConfig() FeatureConfig {
	opts := make(map[string]string)
	for k, v := range fs.Options {
		opts[k] = v
	}
	return FeatureConfig{
		Host:     fs.Host,
		Port:     fs.Port,
		Callsign: fs.Callsign,
		Password: fs.Password,
		Options:  opts,
	}
}

// AppSettings manages persistent application settings stored in a JSON file.
type AppSettings struct {
	Features map[string]*FeatureSettings `json:"features"`

	mu       sync.RWMutex
	filePath string
}

// NewAppSettings creates AppSettings with empty feature defaults.
func NewAppSettings(filePath string) *AppSettings {
	return &AppSettings{
		Features: map[string]*FeatureSettings{
			"chat": {Host: "localhost", Port: 8513, Options: map[string]string{}},
			"bbs":  {Host: "localhost", Port: 8010, Options: map[string]string{}},
			"node": {Host: "localhost", Port: 8010, Options: map[string]string{}},
		},
		filePath: filePath,
	}
}

// Load reads settings from the JSON file. Missing file is not an error —
// the in-memory defaults are kept.
func (s *AppSettings) Load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // first run, no config file yet
		}
		return fmt.Errorf("read settings file: %w", err)
	}

	var loaded AppSettings
	if err := json.Unmarshal(data, &loaded); err != nil {
		return fmt.Errorf("parse settings file: %w", err)
	}

	// Merge loaded features into current (preserves defaults for missing features)
	for name, fs := range loaded.Features {
		if fs != nil {
			if fs.Options == nil {
				fs.Options = map[string]string{}
			}
			s.Features[name] = fs
		}
	}

	return nil
}

// Save writes settings to the JSON file using atomic write (temp + rename).
func (s *AppSettings) Save() error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	return s.saveLocked()
}

// saveLocked writes to disk without acquiring the lock (caller must hold it).
func (s *AppSettings) saveLocked() error {
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal settings: %w", err)
	}
	data = append(data, '\n')

	dir := filepath.Dir(s.filePath)
	tmp, err := os.CreateTemp(dir, "tarpn-mon-settings-*.tmp")
	if err != nil {
		return fmt.Errorf("create temp file: %w", err)
	}
	tmpPath := tmp.Name()

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmpPath)
		return fmt.Errorf("write temp file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("close temp file: %w", err)
	}

	if err := os.Rename(tmpPath, s.filePath); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("rename settings file: %w", err)
	}

	return nil
}

// GetFeature returns a copy of settings for a feature.
func (s *AppSettings) GetFeature(name string) *FeatureSettings {
	s.mu.RLock()
	defer s.mu.RUnlock()

	fs, ok := s.Features[name]
	if !ok {
		return nil
	}

	// Return a copy
	opts := make(map[string]string)
	for k, v := range fs.Options {
		opts[k] = v
	}
	return &FeatureSettings{
		Enabled:  fs.Enabled,
		Host:     fs.Host,
		Port:     fs.Port,
		Callsign: fs.Callsign,
		Password: fs.Password,
		Options:  opts,
	}
}

// SetFeature updates settings for a feature and saves to disk.
func (s *AppSettings) SetFeature(name string, fs *FeatureSettings) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if fs.Options == nil {
		fs.Options = map[string]string{}
	}
	s.Features[name] = fs

	return s.saveLocked()
}

// GetAllFeatures returns a copy of all feature settings.
func (s *AppSettings) GetAllFeatures() map[string]*FeatureSettings {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make(map[string]*FeatureSettings)
	for name, fs := range s.Features {
		opts := make(map[string]string)
		for k, v := range fs.Options {
			opts[k] = v
		}
		result[name] = &FeatureSettings{
			Enabled:  fs.Enabled,
			Host:     fs.Host,
			Port:     fs.Port,
			Callsign: fs.Callsign,
			Password: fs.Password,
			Options:  opts,
		}
	}
	return result
}

// package-level settings instance
var appSettings *AppSettings
