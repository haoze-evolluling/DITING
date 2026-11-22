use hyper::http::Method;

use diting_desktop_app::controller::safebrowsing::ConfigureSafeBrowsingRequest;
use diting_desktop_app::controller::safesearch::ConfigureSafeSearchRequest;

use crate::handlers::{internal_error, ok, ok_data_message, ok_message, Ctx, Resp};
use crate::server::Server;

pub fn handle_safesearch(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().safe_search_config()),
        Method::POST => {
            let request: ConfigureSafeSearchRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            match server.runtime().configure_safe_search(request) {
                Ok(()) => ok_message("强制安全搜索配置已更新"),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}

pub fn handle_safebrowsing(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().safe_browsing_status()),
        Method::POST => {
            let request: ConfigureSafeBrowsingRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            match server.runtime().configure_safe_browsing(request) {
                Ok(status) => ok_data_message(status, "声誉查询配置已更新"),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET, POST 请求"),
    }
}
