package main

import (
	"os"

	prettyconsole "github.com/thessem/zap-prettyconsole"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var (
	// atomicLevel allows runtime log level changes
	atomicLevel zap.AtomicLevel

	// baseLogger is the root logger
	baseLogger *zap.Logger

	// Pre-created sugared loggers for each feature/component
	chatLog      *zap.SugaredLogger
	bbsLog       *zap.SugaredLogger
	nodeLog      *zap.SugaredLogger
	tarpnStatLog *zap.SugaredLogger
	wsLog        *zap.SugaredLogger
	mainLog      *zap.SugaredLogger
	storageLog   *zap.SugaredLogger
	statsLog     *zap.SugaredLogger
	neighborLog  *zap.SugaredLogger
)

func init() {
	// Start with Info level, can be changed to Debug with SetDebugLogging
	atomicLevel = zap.NewAtomicLevelAt(zapcore.InfoLevel)

	// Use prettyconsole encoder for colorized, human-readable output
	encoderConfig := prettyconsole.NewEncoderConfig()
	encoderConfig.EncodeTime = zapcore.TimeEncoderOfLayout("3:04:05PM")

	core := zapcore.NewCore(
		prettyconsole.NewEncoder(encoderConfig),
		zapcore.AddSync(os.Stderr),
		atomicLevel,
	)

	baseLogger = zap.New(core)

	// Create named loggers for each component
	chatLog = baseLogger.Named("CHAT").Sugar()
	bbsLog = baseLogger.Named("BBS").Sugar()
	nodeLog = baseLogger.Named("NODE").Sugar()
	tarpnStatLog = baseLogger.Named("TARPNSTAT").Sugar()
	wsLog = baseLogger.Named("WS").Sugar()
	mainLog = baseLogger.Named("MAIN").Sugar()
	storageLog = baseLogger.Named("STORAGE").Sugar()
	statsLog = baseLogger.Named("STATS").Sugar()
	neighborLog = baseLogger.Named("NEIGHBOR").Sugar()
}

// SetDebugLogging enables or disables debug logging globally
func SetDebugLogging(enabled bool) {
	if enabled {
		atomicLevel.SetLevel(zapcore.DebugLevel)
	} else {
		atomicLevel.SetLevel(zapcore.InfoLevel)
	}
}

// IsDebugLogging returns whether debug logging is enabled
func IsDebugLogging() bool {
	return atomicLevel.Level() == zapcore.DebugLevel
}

// SyncLoggers flushes any buffered log entries
func SyncLoggers() {
	_ = baseLogger.Sync()
}
