//! Apple `.mobileconfig` generation, ported from `mobileconfig.go` and `plist.go`.
//!
//! The generated profile is unsigned on purpose: self-signed certificate deployments are expected
//! to be marked "unverified" by iOS/macOS and confirmed manually. Signing with an enterprise
//! certificate is not something this project holds.

mod plist;

use plist::{plist_array, plist_dict, plist_integer, plist_string, PlistEntry};

/// DNS settings payload type identifier.
pub const MOBILE_CONFIG_PAYLOAD_TYPE: &str = "com.apple.dnsSettings.managed";
/// Media type Apple assigns to configuration profiles.
pub const MOBILE_CONFIG_CONTENT_TYPE: &str = "application/x-apple-aspen-config";
/// File extension Apple devices recognise.
pub const MOBILE_CONFIG_FILE_EXT: &str = ".mobileconfig";

/// Encrypted DNS protocol value for DNS-over-HTTPS.
pub const PROTOCOL_HTTPS: &str = "HTTPS";
/// Encrypted DNS protocol value for DNS-over-TLS.
pub const PROTOCOL_TLS: &str = "TLS";

const DEFAULT_DISPLAY_NAME: &str = "DITING 加密 DNS";
const DEFAULT_DESCRIPTION: &str = "由 DITING 提供的加密 DNS 解析配置";

/// Everything needed to build a configuration profile.
#[derive(Debug, Clone, Default)]
pub struct MobileConfigOptions {
    /// Host name clients connect to; also the certificate validation target.
    pub server_name: String,
    /// Full DoH URL; required in HTTPS mode.
    pub server_url: String,
    /// See [`PROTOCOL_HTTPS`] and [`PROTOCOL_TLS`]; empty defaults to HTTPS.
    pub protocol: String,
    /// Name shown in the device's Settings.
    pub display_name: String,
    /// Profile description.
    pub description: String,
    /// Stable profile identifier; a v4 UUID is generated when empty.
    pub uuid: String,
}

/// Build an unsigned Apple configuration profile.
pub fn build_mobile_config(options: &MobileConfigOptions) -> Result<Vec<u8>, String> {
    let server_name = options.server_name.trim();
    if server_name.is_empty() {
        return Err("缺少服务器名：描述文件需要它作为证书校验基准".to_string());
    }

    let protocol = options.protocol.trim().to_uppercase();
    let protocol = if protocol.is_empty() {
        PROTOCOL_HTTPS.to_string()
    } else {
        protocol
    };
    if protocol != PROTOCOL_HTTPS && protocol != PROTOCOL_TLS {
        return Err(format!("不支持的协议 {:?}", options.protocol));
    }

    let mut dns_settings = vec![PlistEntry {
        key: "DNSProtocol".to_string(),
        value: plist_string(&protocol),
    }];
    if protocol == PROTOCOL_HTTPS {
        let url = options.server_url.trim();
        if url.is_empty() {
            return Err("DoH 模式需要提供完整地址".to_string());
        }
        // Apple silently ignores the whole payload when ServerURL is not an absolute URL.
        if !url.starts_with("https://") {
            return Err(format!("DoH 地址必须以 https:// 开头，实得 {url:?}"));
        }
        dns_settings.push(PlistEntry {
            key: "ServerURL".to_string(),
            value: plist_string(url),
        });
        // ServerName is the certificate validation host here and must match the URL's host.
        dns_settings.push(PlistEntry {
            key: "ServerName".to_string(),
            value: plist_string(server_name),
        });
    } else {
        dns_settings.push(PlistEntry {
            key: "ServerName".to_string(),
            value: plist_string(server_name),
        });
    }

    let uuid = options.uuid.trim();
    let uuid = if uuid.is_empty() {
        new_uuid()
    } else {
        uuid.to_string()
    };

    let display_name = options.display_name.trim();
    let display_name = if display_name.is_empty() {
        DEFAULT_DISPLAY_NAME
    } else {
        display_name
    };
    let description = options.description.trim();
    let description = if description.is_empty() {
        DEFAULT_DESCRIPTION
    } else {
        description
    };

    // One payload means one identifier; reusing the UUID keeps troubleshooting strings aligned.
    let payload_id = format!("com.diting.encrypted-dns.{uuid}");

    let payload = plist_dict(&[
        PlistEntry {
            key: "PayloadType".to_string(),
            value: plist_string(MOBILE_CONFIG_PAYLOAD_TYPE),
        },
        PlistEntry {
            key: "PayloadIdentifier".to_string(),
            value: plist_string(&format!("{payload_id}.dns")),
        },
        PlistEntry {
            key: "PayloadUUID".to_string(),
            value: plist_string(&uuid),
        },
        PlistEntry {
            key: "PayloadDisplayName".to_string(),
            value: plist_string(display_name),
        },
        PlistEntry {
            key: "PayloadVersion".to_string(),
            value: plist_integer(1),
        },
        PlistEntry {
            key: "DNSSettings".to_string(),
            value: plist_dict(&dns_settings),
        },
    ]);

    let root = plist_dict(&[
        PlistEntry {
            key: "PayloadContent".to_string(),
            value: plist_array(&[payload]),
        },
        PlistEntry {
            key: "PayloadType".to_string(),
            value: plist_string("Configuration"),
        },
        PlistEntry {
            key: "PayloadIdentifier".to_string(),
            value: plist_string(&payload_id),
        },
        PlistEntry {
            key: "PayloadUUID".to_string(),
            value: plist_string(&uuid),
        },
        PlistEntry {
            key: "PayloadDisplayName".to_string(),
            value: plist_string(display_name),
        },
        PlistEntry {
            key: "PayloadDescription".to_string(),
            value: plist_string(description),
        },
        PlistEntry {
            key: "PayloadVersion".to_string(),
            value: plist_integer(1),
        },
    ]);

    let mut document = String::new();
    document.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    document.push_str(
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \
         \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n",
    );
    document.push_str("<plist version=\"1.0\">\n");
    document.push_str(&root);
    document.push_str("\n</plist>\n");

    Ok(document.into_bytes())
}

/// Random RFC 4122 version 4 UUID, lowercase with hyphens.
fn new_uuid() -> String {
    let mut bytes = rand::random::<[u8; 16]>();
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    let hex: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn https_options() -> MobileConfigOptions {
        MobileConfigOptions {
            server_name: "dns.lan".to_string(),
            server_url: "https://dns.lan/dns-query".to_string(),
            protocol: "https".to_string(),
            uuid: "11111111-2222-4333-8444-555555555555".to_string(),
            ..Default::default()
        }
    }

    fn document(options: &MobileConfigOptions) -> String {
        String::from_utf8(build_mobile_config(options).expect("build")).expect("utf-8")
    }

    #[test]
    fn https_profile_contains_the_dns_payload() {
        let output = document(&https_options());
        assert!(output.starts_with(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \
             \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
             <plist version=\"1.0\">\n"
        ));
        assert!(output.ends_with("</plist>\n"));
        assert!(output.contains("<key>PayloadType</key>\n<string>Configuration</string>"));
        assert!(output.contains("<string>com.apple.dnsSettings.managed</string>"));
        assert!(output.contains("<key>DNSProtocol</key>\n<string>HTTPS</string>"));
        assert!(output.contains("<key>ServerURL</key>\n<string>https://dns.lan/dns-query</string>"));
        assert!(output.contains("<key>ServerName</key>\n<string>dns.lan</string>"));
        assert!(output.contains("<key>PayloadVersion</key>\n<integer>1</integer>"));
        assert!(output.contains(
            "<string>com.diting.encrypted-dns.11111111-2222-4333-8444-555555555555</string>"
        ));
        assert!(output.contains(
            "<string>com.diting.encrypted-dns.11111111-2222-4333-8444-555555555555.dns</string>"
        ));
        assert!(output.contains(DEFAULT_DISPLAY_NAME));
        assert!(output.contains(DEFAULT_DESCRIPTION));
    }

    #[test]
    fn tls_profile_ignores_the_url() {
        let mut options = https_options();
        options.protocol = "tls".to_string();
        options.server_url = "https://ignored.example/dns-query".to_string();
        options.display_name = "My DNS".to_string();
        options.description = "Desc".to_string();
        let output = document(&options);

        assert!(output.contains("<key>DNSProtocol</key>\n<string>TLS</string>"));
        assert!(output.contains("<key>ServerName</key>\n<string>dns.lan</string>"));
        assert!(!output.contains("ServerURL"));
        assert!(!output.contains("ignored.example"));
        assert!(output.contains("<string>My DNS</string>"));
        assert!(output.contains("<string>Desc</string>"));
    }

    #[test]
    fn missing_server_name_is_rejected() {
        let mut options = https_options();
        options.server_name = "   ".to_string();
        let error = build_mobile_config(&options).expect_err("no server name");
        assert!(error.contains("缺少服务器名"), "{error}");
    }

    #[test]
    fn invalid_protocol_is_rejected() {
        let mut options = https_options();
        options.protocol = "cleartext".to_string();
        let error = build_mobile_config(&options).expect_err("bad protocol");
        assert!(error.contains("不支持的协议"), "{error}");
        assert!(error.contains("cleartext"), "{error}");
    }

    #[test]
    fn https_requires_an_absolute_url() {
        let mut options = https_options();
        options.server_url.clear();
        assert!(build_mobile_config(&options).is_err());

        options.server_url = "http://dns.lan/dns-query".to_string();
        let error = build_mobile_config(&options).expect_err("http is not DoH");
        assert!(error.contains("https://"), "{error}");
    }

    #[test]
    fn xml_special_characters_are_escaped_and_controls_dropped() {
        let mut options = https_options();
        options.protocol = PROTOCOL_TLS.to_string();
        options.server_name = "a&b<c>\"d'e".to_string();
        options.display_name = "name\u{1}with\tcontrol".to_string();
        let output = document(&options);

        assert!(output.contains("a&amp;b&lt;c&gt;&quot;d&apos;e"));
        assert!(output.contains("namewith\tcontrol"));
        assert!(!output.contains('\u{1}'));
    }

    #[test]
    fn provided_uuid_is_stable_across_builds() {
        let options = https_options();
        assert_eq!(document(&options), document(&options));
    }

    #[test]
    fn generated_uuid_is_lowercase_v4() {
        let mut options = https_options();
        options.uuid.clear();
        let output = document(&options);

        let marker = "<key>PayloadUUID</key>\n<string>";
        let start = output.find(marker).expect("payload uuid") + marker.len();
        let uuid = &output[start..start + 36];

        assert_eq!(uuid.len(), 36);
        for (index, character) in uuid.chars().enumerate() {
            match index {
                8 | 13 | 18 | 23 => assert_eq!(character, '-'),
                _ => assert!(
                    character.is_ascii_hexdigit() && !character.is_ascii_uppercase(),
                    "{uuid}"
                ),
            }
        }
        assert_eq!(&uuid[14..15], "4");
        assert!(matches!(&uuid[19..20], "8" | "9" | "a" | "b"), "{uuid}");
    }
}
