use std::io::{Read, Write};
use std::sync::Arc;

use anyhow::{Context, Result};
use cc_switch::{Database, Provider, ProxyService};
use serde::Deserialize;
use serde_json::json;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeProvider {
    app_type: String,
    provider: Provider,
    current: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StartupSnapshot {
    #[serde(default)]
    listen_port: u16,
    #[serde(default)]
    enable_logging: bool,
    providers: Vec<RuntimeProvider>,
}

#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        let _ = writeln!(
            std::io::stdout(),
            "{}",
            json!({ "status": "error", "message": error.to_string() })
        );
        std::process::exit(1);
    }
}

async fn run() -> Result<()> {
    install_crypto_provider()?;

    let mut payload = String::new();
    std::io::stdin()
        .read_to_string(&mut payload)
        .context("读取 OneBoard 启动快照失败")?;
    let snapshot: StartupSnapshot =
        serde_json::from_str(&payload).context("解析 OneBoard 启动快照失败")?;

    let database = Arc::new(Database::memory().context("创建内存数据库失败")?);
    for runtime_provider in snapshot.providers {
        validate_app_type(&runtime_provider.app_type)?;
        database
            .save_provider(&runtime_provider.app_type, &runtime_provider.provider)
            .with_context(|| format!("载入 {} 供应商失败", runtime_provider.app_type))?;
        if runtime_provider.current {
            database
                .set_current_provider(&runtime_provider.app_type, &runtime_provider.provider.id)
                .with_context(|| format!("设置 {} 当前供应商失败", runtime_provider.app_type))?;
        }
    }

    let mut proxy_config = database
        .get_global_proxy_config()
        .await
        .context("读取内存代理配置失败")?;
    proxy_config.listen_address = "127.0.0.1".to_string();
    proxy_config.listen_port = snapshot.listen_port;
    proxy_config.enable_logging = snapshot.enable_logging;
    database
        .update_global_proxy_config(proxy_config)
        .await
        .context("更新内存代理配置失败")?;

    let service = ProxyService::new(database);
    let info = service.start().await.map_err(anyhow::Error::msg)?;
    writeln!(
        std::io::stdout(),
        "{}",
        json!({
            "status": "ready",
            "address": info.address,
            "port": info.port,
            "startedAt": info.started_at
        })
    )?;
    std::io::stdout().flush()?;

    wait_for_shutdown().await?;
    service.stop().await.map_err(anyhow::Error::msg)?;
    Ok(())
}

fn install_crypto_provider() -> Result<()> {
    if rustls::crypto::CryptoProvider::get_default().is_some() {
        return Ok(());
    }
    rustls::crypto::ring::default_provider()
        .install_default()
        .map_err(|_| anyhow::anyhow!("安装 Rustls 进程级加密提供者失败"))
}

fn validate_app_type(app_type: &str) -> Result<()> {
    anyhow::ensure!(
        matches!(app_type, "claude" | "codex"),
        "OneBoard 内置代理只允许 claude 或 codex"
    );
    Ok(())
}

#[cfg(unix)]
async fn wait_for_shutdown() -> Result<()> {
    use tokio::signal::unix::{signal, SignalKind};

    let mut terminate = signal(SignalKind::terminate()).context("监听 SIGTERM 失败")?;
    tokio::select! {
        result = tokio::signal::ctrl_c() => result.context("监听 Ctrl-C 失败")?,
        _ = terminate.recv() => {}
    }
    Ok(())
}

#[cfg(not(unix))]
async fn wait_for_shutdown() -> Result<()> {
    tokio::signal::ctrl_c().await.context("监听 Ctrl-C 失败")
}

#[cfg(test)]
mod tests {
    use super::{install_crypto_provider, validate_app_type};

    #[test]
    fn accepts_only_oneboard_supported_apps() {
        assert!(validate_app_type("claude").is_ok());
        assert!(validate_app_type("codex").is_ok());
        assert!(validate_app_type("gemini").is_err());
    }

    #[test]
    fn has_process_level_crypto_provider_for_https_upstreams() {
        install_crypto_provider().expect("应能安装 Rustls 加密提供者");
        assert!(rustls::crypto::CryptoProvider::get_default().is_some());
    }
}
