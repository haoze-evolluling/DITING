//! 桌面管理端的网络诊断：DNS 查询、上游延迟、系统 Ping 与路由追踪。

mod dns;
mod host;
mod ping;
mod process;
mod trace;

use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use super::effective_listen_addresses;
use super::upstream::TestUpstreamRequest;
use super::ControllerError;
use crate::AppRuntime;

const DEFAULT_QUERY_DOMAIN: &str = "dns.alidns.com";

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryRequest {
    #[serde(default)]
    pub domain: String,
    #[serde(default)]
    pub qtype: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryAnswer {
    pub name: String,
    pub record_type: String,
    pub ttl: u32,
    pub value: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryResponse {
    pub domain: String,
    pub qtype: String,
    pub success: bool,
    pub rcode: u8,
    pub rcode_name: String,
    pub elapsed_ms: f64,
    /// `local` 表示经由本机 DNS 监听（含规则与缓存），`upstream` 表示直连上游。
    pub source: String,
    pub answers: Vec<QueryAnswer>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub message: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpstreamsRequest {
    #[serde(default)]
    pub domain: String,
    #[serde(default)]
    pub attempts: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpstreamDiagnostic {
    pub id: String,
    pub protocol: String,
    pub server: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub url: String,
    pub success: bool,
    pub latency_ms: f64,
    pub attempts: u32,
    pub success_count: u32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub message: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PingRequest {
    #[serde(default)]
    pub target: String,
    #[serde(default)]
    pub count: Option<u32>,
    #[serde(default)]
    pub timeout_seconds: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PingReply {
    pub sequence: i32,
    pub elapsed_ms: Option<f64>,
    pub ttl: Option<i32>,
    pub timeout: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PingResponse {
    pub target: String,
    pub resolved_address: String,
    pub address_family: String,
    pub transmitted: u32,
    pub received: u32,
    pub loss_percent: f64,
    pub min_ms: Option<f64>,
    pub avg_ms: Option<f64>,
    pub max_ms: Option<f64>,
    pub jitter_ms: Option<f64>,
    pub success: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub message: String,
    pub replies: Vec<PingReply>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TraceRequest {
    #[serde(default)]
    pub target: String,
    #[serde(default)]
    pub max_hops: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TraceHop {
    pub hop: i32,
    pub address: Option<String>,
    pub elapsed_ms: Option<f64>,
    pub timeout: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TraceResponse {
    pub target: String,
    pub resolved_address: String,
    pub hops: Vec<TraceHop>,
    pub reached: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub message: String,
}

impl AppRuntime {
    pub async fn diagnose_query(
        &self,
        request: QueryRequest,
    ) -> Result<QueryResponse, ControllerError> {
        let domain = host::validate_domain(&request.domain)?;
        let (qtype, qtype_name) = dns::parse_qtype(&request.qtype)?;
        let query = dns::build_query(&domain, qtype)?;

        let started = Instant::now();
        let mut source = "upstream".to_string();
        let mut message = String::new();
        let mut wire = None;

        if self.is_dns_running() {
            let config = self.config();
            let endpoint = effective_listen_addresses(&config.dns)
                .0
                .iter()
                .find_map(|address| dns::local_endpoint(address));
            match endpoint {
                Some(endpoint) => {
                    match dns::query_udp(endpoint, &query, Duration::from_secs(3)).await {
                        Ok(response) => {
                            source = "local".to_string();
                            wire = Some(response);
                        }
                        Err(error) => {
                            message = format!("本机 DNS 未响应，已改为直连上游：{error}");
                        }
                    }
                }
                None => message = "未找到可用的本机监听地址，已改为直连上游".to_string(),
            }
        }

        if wire.is_none() {
            match tokio::time::timeout(Duration::from_secs(5), self.resolver.resolve(&query, ""))
                .await
            {
                Ok(Ok(response)) => wire = Some(response),
                Ok(Err(error)) => {
                    return Ok(query_failure(
                        &domain,
                        &qtype_name,
                        started,
                        &source,
                        format!("解析失败：{error}"),
                    ));
                }
                Err(_) => {
                    return Ok(query_failure(
                        &domain,
                        &qtype_name,
                        started,
                        &source,
                        "解析超时，上游在 5 秒内没有返回".to_string(),
                    ));
                }
            }
        }

        let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
        let Some(wire) = wire else {
            return Ok(query_failure(
                &domain,
                &qtype_name,
                started,
                &source,
                "没有获得 DNS 响应".to_string(),
            ));
        };
        let Some(reply) = dns::parse_reply(&wire) else {
            return Ok(query_failure(
                &domain,
                &qtype_name,
                started,
                &source,
                "无法解析 DNS 响应报文".to_string(),
            ));
        };

        if reply.truncated {
            message = join_message(&message, "响应被截断（TC=1），结果可能不完整");
        }

        Ok(QueryResponse {
            domain,
            qtype: qtype_name,
            success: reply.rcode == 0,
            rcode: reply.rcode,
            rcode_name: dns::rcode_name(reply.rcode),
            elapsed_ms,
            source,
            answers: reply
                .answers
                .into_iter()
                .map(|answer| QueryAnswer {
                    name: answer.name,
                    record_type: answer.record_type,
                    ttl: answer.ttl,
                    value: answer.value,
                })
                .collect(),
            message,
        })
    }

    /// 依次测试配置里的每个上游，返回平均延迟与失败原因。
    pub async fn diagnose_upstreams(
        &self,
        request: UpstreamsRequest,
    ) -> Result<Vec<UpstreamDiagnostic>, ControllerError> {
        let domain = if request.domain.trim().is_empty() {
            DEFAULT_QUERY_DOMAIN.to_string()
        } else {
            host::validate_domain(&request.domain)?
        };
        let attempts = request.attempts.unwrap_or(3).clamp(1, 5);
        let config = self.config();
        let mut results = Vec::with_capacity(config.upstream.providers.len());

        for provider in &config.upstream.providers {
            let mut latencies = Vec::new();
            let mut message = String::new();
            for _ in 0..attempts {
                let result = self
                    .test_upstream(TestUpstreamRequest {
                        protocol: provider.protocol.clone(),
                        server: provider.server.clone(),
                        url: provider.url.clone(),
                        domain: domain.clone(),
                    })
                    .await;
                if result.success {
                    latencies.push(result.latency_ms);
                } else if message.is_empty() {
                    message = result.error;
                }
            }
            let success_count = latencies.len() as u32;
            let latency_ms = if latencies.is_empty() {
                0.0
            } else {
                latencies.iter().sum::<f64>() / latencies.len() as f64
            };
            results.push(UpstreamDiagnostic {
                id: provider.id.clone(),
                protocol: provider.protocol.to_ascii_uppercase(),
                server: provider.server.clone(),
                url: provider.url.clone(),
                success: success_count > 0,
                latency_ms,
                attempts,
                success_count,
                message,
            });
        }
        Ok(results)
    }

    pub async fn diagnose_ping(
        &self,
        request: PingRequest,
    ) -> Result<PingResponse, ControllerError> {
        ping::ping(&request).await.map_err(ControllerError::new)
    }

    pub async fn diagnose_trace(
        &self,
        request: TraceRequest,
    ) -> Result<TraceResponse, ControllerError> {
        trace::trace(&request).await.map_err(ControllerError::new)
    }
}

fn query_failure(
    domain: &str,
    qtype: &str,
    started: Instant,
    source: &str,
    message: String,
) -> QueryResponse {
    QueryResponse {
        domain: domain.to_string(),
        qtype: qtype.to_string(),
        success: false,
        rcode: 255,
        rcode_name: "ERROR".to_string(),
        elapsed_ms: started.elapsed().as_secs_f64() * 1000.0,
        source: source.to_string(),
        answers: Vec::new(),
        message,
    }
}

fn join_message(existing: &str, next: &str) -> String {
    if existing.is_empty() {
        next.to_string()
    } else {
        format!("{existing}；{next}")
    }
}
