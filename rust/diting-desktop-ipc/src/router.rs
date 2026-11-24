use crate::handlers::{self, Ctx, Resp};
use crate::server::Server;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Auth {
    Public,
    Required,
    SelfHandled,
}

pub fn auth_requirement(path: &str) -> Auth {
    match path {
        "/api/v1/health"
        | "/api/v1/meta"
        | "/api/v1/auth/status"
        | "/api/v1/auth/login"
        | "/api/v1/auth/setup"
        | "/api/v1/auth/reset-password"
        | "/api/v1/auth/background/image" => Auth::Public,
        "/api/v1/events" | "/api/v1/encrypted/mobileconfig" | "/api/v1/auth/background" => {
            Auth::SelfHandled
        }
        path if path.starts_with("/api/") && known(path) => Auth::Required,
        _ => Auth::Public,
    }
}

fn known(path: &str) -> bool {
    matches!(
        path,
        "/api/v1/dns/start"
            | "/api/v1/dns/stop"
            | "/api/v1/status"
            | "/api/v1/takeover/enable"
            | "/api/v1/takeover/disable"
            | "/api/v1/adapters"
            | "/api/v1/takeover/adapter"
            | "/api/v1/takeover/emergency-restore"
            | "/api/v1/upstream"
            | "/api/v1/upstream/configure"
            | "/api/v1/upstream/test"
            | "/api/v1/upstream/stamp"
            | "/api/v1/bootstrap/configure"
            | "/api/v1/cache/stats"
            | "/api/v1/cache/entries"
            | "/api/v1/cache/top"
            | "/api/v1/cache/clear"
            | "/api/v1/cache/config"
            | "/api/v1/cache/persist"
            | "/api/v1/cache/dump"
            | "/api/v1/cache/load"
            | "/api/v1/querylog/search"
            | "/api/v1/querylog/export"
            | "/api/v1/querylog/stats"
            | "/api/v1/querylog/clear"
            | "/api/v1/querylog/config"
            | "/api/v1/filter/stats"
            | "/api/v1/filter/config"
            | "/api/v1/filter/lists"
            | "/api/v1/filter/lists/add"
            | "/api/v1/filter/lists/update"
            | "/api/v1/filter/lists/delete"
            | "/api/v1/filter/lists/refresh"
            | "/api/v1/filter/rules"
            | "/api/v1/filter/check"
            | "/api/v1/filter/schedule"
            | "/api/v1/filter/pause"
            | "/api/v1/filter/services"
            | "/api/v1/dns/lan"
            | "/api/v1/dns/lan/configure"
            | "/api/v1/dns/lan/firewall"
            | "/api/v1/dns/access/configure"
            | "/api/v1/dns/ratelimit/configure"
            | "/api/v1/dns/dns64/configure"
            | "/api/v1/dns/unqualified/configure"
            | "/api/v1/dns/privacy/configure"
            | "/api/v1/dns/rebind/configure"
            | "/api/v1/dns/hosts/configure"
            | "/api/v1/dns/rewrite/rules"
            | "/api/v1/dns/rewrite/configure"
            | "/api/v1/dns/zone/config"
            | "/api/v1/dns/zone/test"
            | "/api/v1/safesearch/config"
            | "/api/v1/filter/safebrowsing"
            | "/api/v1/encrypted/dns/status"
            | "/api/v1/encrypted/dns/configure"
            | "/api/v1/encrypted/dns/cert/generate"
            | "/api/v1/encrypted/dns/cert/import"
            | "/api/v1/encrypted/dns/acl"
            | "/api/v1/clients"
            | "/api/v1/clients/alias"
            | "/api/v1/clients/groups"
            | "/api/v1/dns/ecs/configure"
            | "/api/v1/portcheck"
            | "/api/v1/portcheck/autofix"
            | "/api/v1/diagnostics/query"
            | "/api/v1/diagnostics/upstreams"
            | "/api/v1/diagnostics/ping"
            | "/api/v1/diagnostics/traceroute"
            | "/api/v1/service/status"
            | "/api/v1/auth/logout"
            | "/api/v1/auth/password"
            | "/api/v1/web/status"
            | "/api/v1/web/configure"
            | "/api/v1/web/firewall"
            | "/api/v1/openwrt/status"
            | "/api/v1/openwrt/configure"
    )
}

pub async fn dispatch(server: &Server, ctx: &Ctx<'_>, path: &str) -> Resp {
    match path {
        "/api/v1/health" => handlers::status::handle_health(ctx),
        "/api/v1/meta" => handlers::status::handle_meta(server, ctx),
        "/api/v1/status" => handlers::status::handle_status(server, ctx).await,
        "/api/v1/dns/start" => handlers::status::handle_dns_start(server, ctx).await,
        "/api/v1/dns/stop" => handlers::status::handle_dns_stop(server, ctx).await,
        "/api/v1/takeover/enable" => handlers::status::handle_takeover_enable(server, ctx).await,
        "/api/v1/takeover/disable" => handlers::status::handle_takeover_disable(server, ctx).await,
        "/api/v1/adapters" => handlers::status::handle_adapters(server, ctx).await,
        "/api/v1/takeover/adapter" => handlers::status::handle_adapter_takeover(server, ctx).await,
        "/api/v1/takeover/emergency-restore" => {
            handlers::status::handle_emergency_restore(server, ctx).await
        }
        "/api/v1/portcheck" => handlers::status::handle_port_check(server, ctx).await,
        "/api/v1/portcheck/autofix" => handlers::status::handle_port_autofix(server, ctx).await,

        "/api/v1/diagnostics/query" => handlers::diagnostics::handle_query(server, ctx).await,
        "/api/v1/diagnostics/upstreams" => {
            handlers::diagnostics::handle_upstreams(server, ctx).await
        }
        "/api/v1/diagnostics/ping" => handlers::diagnostics::handle_ping(server, ctx).await,
        "/api/v1/diagnostics/traceroute" => handlers::diagnostics::handle_trace(server, ctx).await,
        "/api/v1/service/status" => handlers::status::handle_service_status(server, ctx).await,

        "/api/v1/upstream" | "/api/v1/upstream/configure" => {
            handlers::upstream::handle_upstream(server, ctx)
        }
        "/api/v1/upstream/test" => handlers::upstream::handle_test(server, ctx).await,
        "/api/v1/upstream/stamp" => handlers::upstream::handle_stamp(ctx),
        "/api/v1/bootstrap/configure" => handlers::upstream::handle_bootstrap(server, ctx),

        "/api/v1/cache/stats" => handlers::cache::handle_stats(server, ctx),
        "/api/v1/cache/entries" => handlers::cache::handle_entries(server, ctx),
        "/api/v1/cache/top" => handlers::cache::handle_top(server, ctx),
        "/api/v1/cache/clear" => handlers::cache::handle_clear(server, ctx),
        "/api/v1/cache/config" => handlers::cache::handle_config(server, ctx),
        "/api/v1/cache/persist" => handlers::cache::handle_persist(server, ctx),
        "/api/v1/cache/dump" => handlers::cache::handle_dump(server, ctx),
        "/api/v1/cache/load" => handlers::cache::handle_load(server, ctx),

        "/api/v1/querylog/search" => handlers::querylog::handle_search(server, ctx).await,
        "/api/v1/querylog/export" => handlers::querylog::handle_export(server, ctx).await,
        "/api/v1/querylog/stats" => handlers::querylog::handle_stats(server, ctx),
        "/api/v1/querylog/clear" => handlers::querylog::handle_clear(server, ctx).await,
        "/api/v1/querylog/config" => handlers::querylog::handle_config(server, ctx).await,

        "/api/v1/filter/stats" => handlers::filter::handle_stats(server, ctx),
        "/api/v1/filter/config" => handlers::filter::handle_config(server, ctx).await,
        "/api/v1/filter/lists" => handlers::filter::handle_lists(server, ctx),
        "/api/v1/filter/lists/add" => handlers::filter::handle_list_add(server, ctx).await,
        "/api/v1/filter/lists/update" => handlers::filter::handle_list_update(server, ctx).await,
        "/api/v1/filter/lists/delete" => handlers::filter::handle_list_delete(server, ctx).await,
        "/api/v1/filter/lists/refresh" => handlers::filter::handle_list_refresh(server, ctx).await,
        "/api/v1/filter/rules" => handlers::filter::handle_rules(server, ctx).await,
        "/api/v1/filter/check" => handlers::filter::handle_check(server, ctx),
        "/api/v1/filter/schedule" => handlers::filter::handle_schedule(server, ctx).await,
        "/api/v1/filter/pause" => handlers::filter::handle_pause(server, ctx),
        "/api/v1/filter/services" => handlers::filter::handle_services(server, ctx).await,

        "/api/v1/dns/lan" => handlers::lan::handle_status(server, ctx).await,
        "/api/v1/dns/lan/configure" => handlers::lan::handle_configure(server, ctx).await,
        "/api/v1/dns/lan/firewall" => handlers::lan::handle_firewall(server, ctx).await,
        "/api/v1/dns/access/configure" => handlers::security::handle_access(server, ctx),
        "/api/v1/dns/ratelimit/configure" => handlers::security::handle_rate_limit(server, ctx),
        "/api/v1/dns/dns64/configure" => handlers::security::handle_dns64(server, ctx),
        "/api/v1/dns/unqualified/configure" => handlers::security::handle_unqualified(server, ctx),
        "/api/v1/dns/privacy/configure" => handlers::security::handle_privacy(server, ctx),
        "/api/v1/dns/rebind/configure" => handlers::security::handle_rebind(server, ctx),
        "/api/v1/dns/hosts/configure" => handlers::security::handle_hosts(server, ctx),
        "/api/v1/dns/ecs/configure" => handlers::security::handle_ecs(server, ctx),

        "/api/v1/dns/rewrite/rules" => handlers::rewrite::handle_rules(server, ctx),
        "/api/v1/dns/rewrite/configure" => handlers::rewrite::handle_configure(server, ctx),
        "/api/v1/dns/zone/config" => handlers::rewrite::handle_zone_config(server, ctx),
        "/api/v1/dns/zone/test" => handlers::rewrite::handle_zone_test(server, ctx),

        "/api/v1/safesearch/config" => handlers::safesearch::handle_safesearch(server, ctx),
        "/api/v1/filter/safebrowsing" => handlers::safesearch::handle_safebrowsing(server, ctx),

        "/api/v1/encrypted/dns/status" => handlers::encrypted::handle_status(server, ctx),
        "/api/v1/encrypted/dns/configure" => {
            handlers::encrypted::handle_configure(server, ctx).await
        }
        "/api/v1/encrypted/dns/cert/generate" => {
            handlers::encrypted::handle_cert_generate(server, ctx).await
        }
        "/api/v1/encrypted/dns/cert/import" => {
            handlers::encrypted::handle_cert_import(server, ctx).await
        }
        "/api/v1/encrypted/dns/acl" => handlers::encrypted::handle_acl(server, ctx).await,
        "/api/v1/encrypted/mobileconfig" => handlers::encrypted::handle_mobileconfig(server, ctx),

        "/api/v1/clients" => handlers::clients::handle_clients(server, ctx),
        "/api/v1/clients/alias" => handlers::clients::handle_alias(server, ctx),
        "/api/v1/clients/groups" => handlers::clients::handle_groups(server, ctx),

        "/api/v1/auth/status" => handlers::auth::handle_status(server, ctx),
        "/api/v1/auth/login" => handlers::auth::handle_login(server, ctx),
        "/api/v1/auth/logout" => handlers::auth::handle_logout(server, ctx),
        "/api/v1/auth/setup" => handlers::auth::handle_setup(server, ctx),
        "/api/v1/auth/reset-password" => handlers::auth::handle_reset_password(server, ctx),
        "/api/v1/auth/password" => handlers::auth::handle_password(server, ctx),
        "/api/v1/auth/background" => handlers::auth::handle_background(server, ctx),
        "/api/v1/auth/background/image" => handlers::auth::handle_background_image(server, ctx),

        "/api/v1/web/status" => handlers::web::handle_status(server, ctx).await,
        "/api/v1/web/configure" => handlers::web::handle_configure(server, ctx).await,
        "/api/v1/web/firewall" => handlers::web::handle_firewall(server, ctx).await,
        "/api/v1/openwrt/status" => handlers::openwrt::handle_status(server, ctx).await,
        "/api/v1/openwrt/configure" => handlers::openwrt::handle_configure(server, ctx).await,
        _ => handlers::not_found("api endpoint not found"),
    }
}
