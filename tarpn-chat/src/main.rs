//! TARPN Chat - LinBPQ-compatible chat node implementation
//!
//! This implements the LinBPQ chat protocol for participation in the
//! amateur radio chat mesh network.

use anyhow::Result;
use clap::Parser;
use tarpn_chat::{config, server};
use tracing::info;
use tracing_subscriber::EnvFilter;

/// Build version string: "X.Y.Z (githash)" or "X.Y.Z (githash-dirty)"
const VERSION: &str = concat!(
    env!("CARGO_PKG_VERSION"),
    " (",
    env!("GIT_VERSION"),
    ")"
);

#[derive(Parser, Debug)]
#[command(name = "tarpn-chat")]
#[command(about = "LinBPQ-compatible chat node")]
#[command(version = VERSION)]
struct Args {
    /// Configuration file path
    #[arg(short, long, default_value = "config.toml")]
    config: String,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short, long, default_value = "info")]
    log_level: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logging
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(&args.log_level));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(true)
        .with_thread_ids(false)
        .init();

    info!("TARPN Chat v{}", VERSION);

    // Load configuration
    let config = match config::Config::load(&args.config) {
        Ok(c) => c,
        Err(e) => {
            // If config doesn't exist, print example and exit
            if !std::path::Path::new(&args.config).exists() {
                eprintln!("Configuration file '{}' not found.", args.config);
                eprintln!();
                eprintln!("Create a config.toml with the following format:");
                eprintln!();
                eprintln!(
                    r#"[node]
call = "BOT"
alias = "CHTBOT"

[netrom]
linbpq = "127.0.0.1:63119" # Connect to LinBPQ NETROMPORT
# listen = "0.0.0.0:63120" # Or listen for LinBPQ connections
"#
                );
                std::process::exit(1);
            }
            return Err(e.into());
        }
    };

    // Validate config
    if !config.is_netrom_mode() {
        eprintln!("Error: Configuration must specify [netrom] section");
        std::process::exit(1);
    }

    if let Some(ref netrom) = config.netrom {
        if let Some(ref listen_addr) = netrom.listen {
            info!(
                "Configured as {} ({}) in NetROM listen mode on {}",
                config.node.call, config.node.alias,
                listen_addr
            );
        } else if let Some(ref linbpq_addr) = netrom.linbpq {
            info!(
                "Configured as {} ({}) in NetROM connect mode to {}",
                config.node.call, config.node.alias,
                linbpq_addr
            );
        }
    }

    // Start metrics server if configured
    if let Some(ref metrics_config) = config.metrics {
        let bind = metrics_config.bind.clone();
        let port = metrics_config.port;
        tokio::spawn(async move {
            if let Err(e) = tarpn_chat::metrics::serve_metrics(&bind, port).await {
                tracing::error!("Metrics server error: {}", e);
            }
        });
    }

    // Create and run server
    let mut server = server::ChatServer::new(config);
    server.run().await?;

    Ok(())
}
