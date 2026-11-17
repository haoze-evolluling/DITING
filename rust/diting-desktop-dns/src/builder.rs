//! Assembles the fixed pipeline from the engines the service owns.
//!
//! The order is not arbitrary (`PIPELINE_ORDER`): grouping must precede the cache, local authority
//! must precede filtering, the response recheck must wrap the cache, and ECH/EDE must wrap every
//! answer including cached ones. Stages whose engine is absent are simply not registered.

use std::sync::Arc;

use diting_desktop_core::access::AccessControl;
use diting_desktop_core::cache::DesktopCache;
use diting_desktop_core::clients::ClientDirectory;
use diting_desktop_core::filter::RuleEngine;
use diting_desktop_core::hosts::HostsResolver;
use diting_desktop_core::metrics::MetricsTracker;
use diting_desktop_core::ratelimit::RateLimiter;
use diting_desktop_core::resolver::DesktopResolver;
use diting_desktop_core::rewrite::RewriteEngine;
use diting_desktop_core::safesearch::SafeSearchEngine;
use diting_desktop_core::zone::ZoneEngine;

use crate::pipeline::{Pipeline, Stage};
use crate::stages::{
    access::AccessStage,
    any::AnyStage,
    bogus::BogusNxDomainStage,
    cache::CacheStage,
    client::ClientStage,
    dns64::Dns64Stage,
    ech::EchStage,
    ecs::EcsStage,
    ede::EdeStage,
    filter::FilterStage,
    filter_response::FilterResponseStage,
    forward::ForwardStage,
    hosts::HostsStage,
    ipv6::Ipv6Stage,
    metrics::{MetricsStage, QueryObserver},
    private_ptr::PrivatePtrStage,
    ratelimit::RateLimitStage,
    rebind::RebindStage,
    rewrite::RewriteStage,
    safesearch::SafeSearchStage,
    sudn::SudnStage,
    unqualified::UnqualifiedStage,
    zone::ZoneStage,
    ConfigHandle,
};

pub struct PipelineParts {
    pub config: ConfigHandle,
    pub resolver: Arc<DesktopResolver>,
    pub cache: Arc<DesktopCache>,
    pub filter: RuleEngine,
    pub hosts: Arc<HostsResolver>,
    pub rewrite: Arc<RewriteEngine>,
    pub zone: Arc<ZoneEngine>,
    pub safesearch: Arc<SafeSearchEngine>,
    pub clients: Arc<ClientDirectory>,
    pub access: Arc<AccessControl>,
    pub ratelimit: Arc<RateLimiter>,
    pub metrics: Arc<MetricsTracker>,
    pub observer: Option<Arc<dyn QueryObserver>>,
}

impl PipelineParts {
    pub fn build(self) -> Arc<Pipeline> {
        let mut stages: Vec<Arc<dyn Stage>> = Vec::new();
        stages.push(Arc::new(MetricsStage::new(
            self.metrics,
            self.observer.clone(),
        )));
        stages.push(Arc::new(EdeStage::new(self.config.clone())));
        stages.push(Arc::new(EchStage::new(self.config.clone())));
        stages.push(Arc::new(ClientStage::new(self.clients)));
        stages.push(Arc::new(AccessStage::new(self.access)));
        stages.push(Arc::new(RateLimitStage::new(self.ratelimit)));
        stages.push(Arc::new(SudnStage));
        stages.push(Arc::new(ZoneStage::new(self.zone)));
        stages.push(Arc::new(HostsStage::new(self.hosts)));
        stages.push(Arc::new(RewriteStage::new(self.rewrite)));
        stages.push(Arc::new(SafeSearchStage::new(self.safesearch)));
        stages.push(Arc::new(Ipv6Stage::new(self.config.clone())));
        stages.push(Arc::new(PrivatePtrStage::new(self.config.clone())));
        stages.push(Arc::new(UnqualifiedStage::new(self.config.clone())));
        stages.push(Arc::new(AnyStage::new(self.config.clone())));
        stages.push(Arc::new(FilterStage::new(self.filter.clone())));
        stages.push(Arc::new(
            RebindStage::new(self.config.clone()).with_cache(self.cache.clone()),
        ));
        stages.push(Arc::new(
            FilterResponseStage::new(self.filter.clone()).with_cache(self.cache.clone()),
        ));
        stages.push(Arc::new(Dns64Stage::new(
            self.config.clone(),
            self.resolver.clone(),
        )));
        stages.push(Arc::new(EcsStage::new(self.config.clone())));
        stages.push(Arc::new(CacheStage::new(self.cache)));
        stages.push(Arc::new(BogusNxDomainStage::new(self.filter)));
        stages.push(Arc::new(ForwardStage::new(self.resolver)));
        Arc::new(Pipeline::new(stages))
    }
}
