use chrono::Local;
use hyper::http::Method;
use serde::Deserialize;

use diting_desktop_api::config::backup;

use crate::handlers::{attachment, bad_request, internal_error, ok_data_message, Ctx, Resp};
use crate::server::Server;

#[derive(Debug, Default, Deserialize)]
pub struct ImportRequest {
    #[serde(default)]
    pub content: String,
}

pub fn handle_export(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    let content = match server.runtime().export_config_backup() {
        Ok(content) => content,
        Err(error) => return internal_error(error.message),
    };
    let stamp = Local::now().format("%Y%m%d-%H%M%S").to_string();
    attachment(
        content.into_bytes(),
        "application/json; charset=utf-8",
        &format!("DITING-config-{stamp}.json"),
    )
}

pub async fn handle_import(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: ImportRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    if request.content.trim().is_empty() {
        return bad_request("请提供备份文件内容");
    }
    let document = match backup::parse(&request.content) {
        Ok(document) => document,
        Err(error) => return bad_request(error.message()),
    };
    match server.runtime().import_config_backup(&document).await {
        Ok(outcome) => {
            let message = match &outcome.restart_warning {
                Some(warning) => format!("配置已导入，共恢复 {} 项；{warning}", outcome.sections),
                None => format!("配置已导入并生效，共恢复 {} 项", outcome.sections),
            };
            ok_data_message(
                serde_json::json!({
                    "sections": outcome.sections,
                    "restartWarning": outcome.restart_warning,
                }),
                &message,
            )
        }
        Err(error) => internal_error(error.message),
    }
}
