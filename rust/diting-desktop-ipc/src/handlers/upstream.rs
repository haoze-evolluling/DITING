//! Upstream configuration, connectivity test, bootstrap and `sdns://` stamps.

use hyper::http::Method;
use serde_json::json;

use diting_desktop_app::controller::upstream::{
    ConfigureBootstrapRequest, ConfigureUpstreamRequest, TestUpstreamRequest,
};

use crate::handlers::{bad_request, internal_error, ok, ok_message, Ctx, Resp};
use crate::response::ApiResponse;
use crate::server::Server;
use crate::types::{ParseStampRequest, ParseStampResponse, StampProps};
use crate::ws::Event;

pub fn handle_upstream(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().upstream_config()),
        Method::POST => {
            let request: ConfigureUpstreamRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            match server.runtime().configure_upstream(request) {
                Ok(()) => {
                    server
                        .hub()
                        .broadcast(Event::new("upstream", json!("configured")));
                    ok_message("上游配置已成功更新")
                }
                Err(error) => bad_request(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}

pub async fn handle_test(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: TestUpstreamRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    let result = server.runtime().test_upstream(request).await;
    if result.success {
        ok(result)
    } else {
        let error = result.error.clone();
        crate::handlers::json_response(
            hyper::http::StatusCode::OK,
            &ApiResponse::failure_with(error, result),
        )
    }
}

pub fn handle_bootstrap(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ConfigureBootstrapRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_bootstrap(request) {
        Ok(()) => {
            server
                .hub()
                .broadcast(Event::new("upstream", json!("bootstrap_configured")));
            ok_message("Bootstrap DNS 配置已成功更新")
        }
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_stamp(ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ParseStampRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    let stamp = match diting_stamp_core::parse(&request.stamp) {
        Ok(stamp) => stamp,
        Err(error) => return bad_request(error),
    };

    let props = StampProps {
        dnssec: stamp.props & 1 != 0,
        no_log: stamp.props & 2 != 0,
        no_filter: stamp.props & 4 != 0,
    };
    let pin = stamp
        .hashes
        .first()
        .map(|hash| {
            hash.iter()
                .map(|byte| format!("{byte:02X}"))
                .collect::<Vec<_>>()
                .join(":")
        })
        .unwrap_or_default();

    ok(ParseStampResponse {
        protocol: stamp.proto.protocol().to_string(),
        server: stamp.server(),
        url: stamp.url(),
        provider_name: stamp.provider_name,
        path: stamp.path,
        server_addr: stamp.server_addr,
        bootstrap_ips: stamp.bootstrap_ips,
        pin,
        props,
        proto_name: stamp.proto.name().to_string(),
    })
}
