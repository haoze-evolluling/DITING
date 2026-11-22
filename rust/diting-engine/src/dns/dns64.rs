use std::net::{IpAddr, Ipv6Addr};
use std::sync::Arc;

use diting_dns_core::message::{extract, TYPE_A, TYPE_AAAA};
use diting_dns_core::reply;

use crate::engine::Engine;

pub async fn maybe_synthesize(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    qtype: u16,
    aaaa_ips: &[String],
) -> Option<(Vec<u8>, String)> {
    if qtype != TYPE_AAAA {
        return None;
    }
    let dns64 = engine.dns64()?;
    if !dns64.is_enabled() || has_valid_aaaa(&dns64, aaaa_ips) {
        return None;
    }

    let a_query = crate::resolver::build_query(domain, TYPE_A);
    let (a_response, _shared) = crate::dns::flight::resolve(engine, &a_query).await.ok()?;
    let a_extract = extract(&a_response)?;
    let v4 = first_ipv4(&a_extract.ips)?;
    let synthesized = Ipv6Addr::from(dns64.map(v4)).to_string();

    let wire =
        reply::rewrite_ip(query, &synthesized).and_then(|plan| reply::render(query, &plan))?;
    Some((wire, synthesized))
}

fn has_valid_aaaa(dns64: &diting_dns64_core::Engine, ips: &[String]) -> bool {
    let parsed: Vec<Vec<u8>> = ips.iter().filter_map(|text| ip_bytes(text)).collect();
    let refs: Vec<&[u8]> = parsed.iter().map(Vec::as_slice).collect();
    dns64.has_valid_aaaa(&refs)
}

fn ip_bytes(text: &str) -> Option<Vec<u8>> {
    match text.trim().parse::<IpAddr>() {
        Ok(IpAddr::V4(v4)) => Some(v4.octets().to_vec()),
        Ok(IpAddr::V6(v6)) => Some(v6.octets().to_vec()),
        Err(_) => None,
    }
}

fn first_ipv4(ips: &[String]) -> Option<[u8; 4]> {
    ips.iter()
        .find_map(|text| match text.trim().parse::<IpAddr>() {
            Ok(IpAddr::V4(v4)) => Some(v4.octets()),
            _ => None,
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kernel() -> diting_dns64_core::Engine {
        diting_dns64_core::Engine::new(true, &[]).expect("well-known prefix")
    }

    #[test]
    fn a_real_aaaa_blocks_synthesis() {
        let kernel = kernel();
        assert!(has_valid_aaaa(&kernel, &["2606:4700::1111".to_string()]));
        assert!(!has_valid_aaaa(&kernel, &[]));
        assert!(!has_valid_aaaa(&kernel, &["fe80::1".to_string()]));
    }

    #[test]
    fn first_ipv4_skips_ipv6_and_junk() {
        let ips = [
            "2606:4700::1".to_string(),
            "not-an-ip".to_string(),
            "192.0.2.33".to_string(),
        ];
        assert_eq!(first_ipv4(&ips), Some([192, 0, 2, 33]));
        assert_eq!(first_ipv4(&[]), None);
    }

    #[test]
    fn synthesized_aaaa_is_rendered_for_the_query() {
        let kernel = kernel();
        let query = crate::resolver::build_query("v4only.example", TYPE_AAAA);
        let synthesized = Ipv6Addr::from(kernel.map([192, 0, 2, 33])).to_string();
        let plan = reply::rewrite_ip(&query, &synthesized).expect("plan");
        let wire = reply::render(&query, &plan).expect("wire");
        let extracted = extract(&wire).expect("extract");
        assert!(
            extracted.ips.iter().any(|ip| ip == &synthesized),
            "answer carries the synthesized address: {:?}",
            extracted.ips
        );
    }
}
