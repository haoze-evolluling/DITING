//! `/api/v1/clients*`.

use hyper::http::Method;

use diting_desktop_app::controller::clients::{
    ConfigureClientAliasRequest, ConfigureClientGroupsRequest,
};

use crate::handlers::{internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;

pub fn handle_clients(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().clients())
}

pub fn handle_alias(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: ConfigureClientAliasRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_client_alias(request) {
        Ok(()) => ok_message("客户端别名已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_groups(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().client_groups()),
        Method::POST => {
            let request: ConfigureClientGroupsRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            match server.runtime().configure_client_groups(request) {
                Ok(()) => ok_message("客户端分组已更新并生效"),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}
