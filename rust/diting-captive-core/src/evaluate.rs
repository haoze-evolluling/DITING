#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PortalState {
    Open,
    Portal,
    Unknown,
}

impl PortalState {
    pub fn as_str(self) -> &'static str {
        match self {
            PortalState::Open => "open",
            PortalState::Portal => "portal",
            PortalState::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Probe {
    pub status_code: Option<u16>,
    pub redirect_url: Option<String>,
    pub body_matches_expected: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PortalVerdict {
    pub state: PortalState,
    pub portal_url: Option<String>,
    pub suspend_blocking: bool,
}

pub fn parse_portal_url(option: &str) -> Option<String> {
    let value = option.trim();
    if value.is_empty() {
        return None;
    }
    let lower = value.to_ascii_lowercase();
    if !(lower.starts_with("http://") || lower.starts_with("https://")) {
        return None;
    }
    if value.len() < 8 || value.contains(char::is_whitespace) {
        return None;
    }
    Some(value.to_string())
}

pub fn evaluate(probe: &Probe) -> PortalVerdict {
    let portal_url = probe.redirect_url.as_deref().and_then(parse_portal_url);

    match probe.status_code {
        Some(204) if probe.body_matches_expected != Some(false) => PortalVerdict {
            state: PortalState::Open,
            portal_url: None,
            suspend_blocking: false,
        },
        Some(status) if (300..400).contains(&status) || status == 511 => PortalVerdict {
            state: PortalState::Portal,
            portal_url,
            suspend_blocking: true,
        },
        Some(204) => PortalVerdict {
            state: PortalState::Portal,
            portal_url,
            suspend_blocking: true,
        },
        _ => PortalVerdict {
            state: PortalState::Unknown,
            portal_url,
            suspend_blocking: false,
        },
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GateDecision {
    pub suspend_blocking: bool,
    pub portal_url: Option<String>,
    pub reason: String,
}

pub fn gate(
    network_validated: bool,
    captive_capability: bool,
    verdict: &PortalVerdict,
) -> GateDecision {
    if verdict.state == PortalState::Portal || captive_capability {
        return GateDecision {
            suspend_blocking: true,
            portal_url: verdict.portal_url.clone(),
            reason: "captive_portal".to_string(),
        };
    }
    if network_validated || verdict.state == PortalState::Open {
        return GateDecision {
            suspend_blocking: false,
            portal_url: None,
            reason: "validated_open".to_string(),
        };
    }
    GateDecision {
        suspend_blocking: false,
        portal_url: None,
        reason: "unknown".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn probe(status: u16, redirect: Option<&str>, body_ok: Option<bool>) -> Probe {
        Probe {
            status_code: Some(status),
            redirect_url: redirect.map(str::to_string),
            body_matches_expected: body_ok,
        }
    }

    #[test]
    fn clean_204_is_open() {
        let verdict = evaluate(&probe(204, None, Some(true)));
        assert_eq!(verdict.state, PortalState::Open);
        assert!(!verdict.suspend_blocking);
    }

    #[test]
    fn redirect_is_portal() {
        let verdict = evaluate(&probe(302, Some("http://wifi.portal/login"), None));
        assert_eq!(verdict.state, PortalState::Portal);
        assert!(verdict.suspend_blocking);
        assert_eq!(
            verdict.portal_url.as_deref(),
            Some("http://wifi.portal/login")
        );
    }

    #[test]
    fn network_auth_required_is_portal() {
        let verdict = evaluate(&probe(511, None, None));
        assert_eq!(verdict.state, PortalState::Portal);
        assert!(verdict.suspend_blocking);
    }

    #[test]
    fn wrong_body_on_204_is_portal() {
        let verdict = evaluate(&probe(204, None, Some(false)));
        assert_eq!(verdict.state, PortalState::Portal);
        assert!(verdict.suspend_blocking);
    }

    #[test]
    fn missing_status_is_unknown() {
        assert_eq!(evaluate(&Probe::default()).state, PortalState::Unknown);
    }

    #[test]
    fn portal_url_requires_http_scheme() {
        assert!(parse_portal_url("http://portal").is_some());
        assert!(parse_portal_url("https://portal.example/login").is_some());
        assert!(parse_portal_url("portal.example").is_none());
        assert!(parse_portal_url("javascript:alert(1)").is_none());
        assert!(parse_portal_url("   ").is_none());
    }

    #[test]
    fn gate_suspends_on_portal_or_capability() {
        let open = evaluate(&probe(204, None, Some(true)));
        assert!(!gate(true, false, &open).suspend_blocking);
        assert!(gate(false, true, &open).suspend_blocking);
        let portal = evaluate(&probe(302, Some("http://p"), None));
        assert!(gate(true, false, &portal).suspend_blocking);
        assert_eq!(
            gate(true, false, &portal).portal_url.as_deref(),
            Some("http://p")
        );
    }

    #[test]
    fn state_strings_are_stable() {
        assert_eq!(PortalState::Open.as_str(), "open");
        assert_eq!(PortalState::Portal.as_str(), "portal");
        assert_eq!(PortalState::Unknown.as_str(), "unknown");
    }
}
