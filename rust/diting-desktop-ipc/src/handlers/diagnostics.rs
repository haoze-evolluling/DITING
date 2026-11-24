use hyper::http::Method;

use diting_desktop_app::controller::diagnostics::{
    PingRequest, QueryRequest, TraceRequest, UpstreamsRequest,
};

use crate::handlers::{controller_error, ok, Ctx, Resp};
use crate::server::Server;

pub async fn handle_query(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: QueryRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().diagnose_query(request).await {
        Ok(result) => ok(result),
        Err(error) => controller_error(error),
    }
}

pub async fn handle_upstreams(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: UpstreamsRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().diagnose_upstreams(request).await {
        Ok(result) => ok(result),
        Err(error) => controller_error(error),
    }
}

pub async fn handle_ping(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: PingRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().diagnose_ping(request).await {
        Ok(result) => ok(result),
        Err(error) => controller_error(error),
    }
}

pub async fn handle_trace(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: TraceRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().diagnose_trace(request).await {
        Ok(result) => ok(result),
        Err(error) => controller_error(error),
    }
}
