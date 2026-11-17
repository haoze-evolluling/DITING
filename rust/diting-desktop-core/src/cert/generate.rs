//! Self-signed certificate generation, ported from `cert_generate.go`.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::str::FromStr;
use std::time::{Duration, SystemTime};

use diting_desktop_api::config::security::{
    normalize_cert_config, CertConfig, DEFAULT_SERVER_NAME,
};
use rcgen::string::Ia5String;
use rcgen::{
    date_time_ymd, BasicConstraints, CertificateParams, DistinguishedName, DnType,
    ExtendedKeyUsagePurpose, IsCa, KeyPair, KeyUsagePurpose, SanType, SerialNumber,
    PKCS_ECDSA_P256_SHA256,
};
use x509_cert::builder::{Builder, CertificateBuilder, Profile};
use x509_cert::der::asn1::Ia5String as DerIa5String;
use x509_cert::der::oid::ObjectIdentifier;
use x509_cert::der::Encode;
use x509_cert::ext::pkix::name::GeneralName;
use x509_cert::ext::pkix::{
    BasicConstraints as X509BasicConstraints, ExtendedKeyUsage, KeyUsage as X509KeyUsage,
    KeyUsages, SubjectAltName,
};
use x509_cert::name::Name;
use x509_cert::serial_number::SerialNumber as X509SerialNumber;
use x509_cert::spki::SubjectPublicKeyInfoOwned;
use x509_cert::time::{Time, Validity};

use super::material::pem_encode;

/// `serverAuth` (RFC 5280 §4.2.1.12), the only EKU the former Go service embedded.
const SERVER_AUTH_OID: &str = "1.3.6.1.5.5.7.3.1";

/// A freshly generated certificate and its PKCS#8 private key, both PEM encoded.
#[derive(Debug, Clone)]
pub struct SelfSignedCert {
    pub cert_pem: String,
    pub key_pem: String,
}

const DEFAULT_VALID_DAYS: i32 = 825;

/// Generate a self-signed server certificate from `config`.
///
/// `notBefore` is one day in the past so small clock differences between host and clients cannot
/// make a freshly generated certificate look "not yet valid".
pub fn generate_self_signed(config: &CertConfig) -> Result<SelfSignedCert, String> {
    let mut config = config.clone();
    normalize_cert_config(&mut config);

    let valid_days = if config.valid_days > 0 {
        config.valid_days
    } else {
        DEFAULT_VALID_DAYS
    };
    if config.key_type == "rsa" {
        return generate_rsa_self_signed(&config, valid_days);
    }
    let key = generate_ecdsa_key()?;

    let mut params = CertificateParams::default();
    let mut distinguished_name = DistinguishedName::new();
    distinguished_name.push(DnType::CommonName, common_name(&config));
    distinguished_name.push(DnType::OrganizationName, "DITING");
    params.distinguished_name = distinguished_name;
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyEncipherment,
        KeyUsagePurpose::KeyCertSign,
    ];
    params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
    params.subject_alt_names = subject_alt_names(&config)?;

    let mut serial = rand::random::<[u8; 16]>();
    while serial.iter().all(|byte| *byte == 0) {
        serial = rand::random();
    }
    params.serial_number = Some(SerialNumber::from(serial.to_vec()));

    // `rcgen` exposes its time values only through `date_time_ymd`; start from the Unix epoch and
    // add the exact number of seconds so the validity matches Go's `now ± offset` (rather than
    // being rounded to midnight).
    let epoch = date_time_ymd(1970, 1, 1);
    let now = chrono::Utc::now().timestamp();
    let not_before = (now - 86_400).max(0) as u64;
    let not_after = (now + i64::from(valid_days) * 86_400) as u64;
    params.not_before = epoch + Duration::from_secs(not_before);
    params.not_after = epoch + Duration::from_secs(not_after);

    let certificate = params
        .self_signed(&key)
        .map_err(|error| format!("生成自签证书失败: {error}"))?;

    Ok(SelfSignedCert {
        cert_pem: certificate.pem(),
        key_pem: key.serialize_pem(),
    })
}

fn generate_ecdsa_key() -> Result<KeyPair, String> {
    KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256)
        .map_err(|error| format!("生成 ECDSA 私钥失败: {error}"))
}

/// RSA-3072 self-signed certificate, matching Go's `rsa.GenerateKey(rand.Reader, 3072)`.
///
/// `rcgen`'s ring backend cannot generate or sign with RSA, so this path builds the X.509
/// structure with `x509-cert` and signs it through the pure-Rust `rsa` crate. The profile is
/// deliberately `Manual`: Go's template used DS + KeyEncipherment + KeyCertSign, which neither
/// the Root nor the Leaf preset reproduces.
fn generate_rsa_self_signed(
    config: &CertConfig,
    valid_days: i32,
) -> Result<SelfSignedCert, String> {
    use rsa::pkcs1v15::SigningKey;
    use rsa::pkcs8::{EncodePrivateKey, LineEnding};
    use rsa::rand_core::OsRng;
    use rsa::signature::Keypair;
    use rsa::RsaPrivateKey;
    use sha2::Sha256;

    let private_key = RsaPrivateKey::new(&mut OsRng, 3072)
        .map_err(|error| format!("生成 RSA 私钥失败: {error}"))?;
    let key_pem = private_key
        .to_pkcs8_pem(LineEnding::LF)
        .map_err(|error| format!("编码 RSA 私钥失败: {error}"))?;

    let signing_key = SigningKey::<Sha256>::new(private_key.clone());
    let subject = Name::from_str(&format!("O=DITING,CN={}", common_name(config)))
        .map_err(|error| format!("构建证书主题失败: {error}"))?;
    let public_key = SubjectPublicKeyInfoOwned::from_key(signing_key.verifying_key())
        .map_err(|error| format!("编码 RSA 公钥失败: {error}"))?;

    let mut serial = rand::random::<[u8; 16]>();
    while serial.iter().all(|byte| *byte == 0) {
        serial = rand::random();
    }
    let serial =
        X509SerialNumber::new(&serial).map_err(|error| format!("生成证书序列号失败: {error}"))?;

    let now = SystemTime::now();
    let validity = Validity {
        not_before: Time::try_from(now - Duration::from_secs(86_400))
            .map_err(|error| format!("设置证书生效时间失败: {error}"))?,
        not_after: Time::try_from(now + Duration::from_secs(valid_days as u64 * 86_400))
            .map_err(|error| format!("设置证书过期时间失败: {error}"))?,
    };

    let mut builder = CertificateBuilder::new(
        Profile::Manual { issuer: None },
        serial,
        validity,
        subject,
        public_key,
        &signing_key,
    )
    .map_err(|error| format!("生成自签证书失败: {error}"))?;
    builder
        .add_extension(&X509BasicConstraints {
            ca: true,
            path_len_constraint: None,
        })
        .map_err(|error| format!("写入证书扩展失败: {error}"))?;
    builder
        .add_extension(&X509KeyUsage(
            KeyUsages::DigitalSignature | KeyUsages::KeyEncipherment | KeyUsages::KeyCertSign,
        ))
        .map_err(|error| format!("写入证书扩展失败: {error}"))?;
    builder
        .add_extension(&ExtendedKeyUsage(vec![ObjectIdentifier::new_unwrap(
            SERVER_AUTH_OID,
        )]))
        .map_err(|error| format!("写入证书扩展失败: {error}"))?;
    builder
        .add_extension(&SubjectAltName(x509_subject_alt_names(config)?))
        .map_err(|error| format!("写入证书扩展失败: {error}"))?;

    let certificate = builder
        .build::<rsa::pkcs1v15::Signature>()
        .map_err(|error| format!("生成自签证书失败: {error}"))?;
    let der = certificate
        .to_der()
        .map_err(|error| format!("编码证书失败: {error}"))?;

    Ok(SelfSignedCert {
        cert_pem: String::from_utf8(pem_encode("CERTIFICATE", &der))
            .expect("PEM is ASCII by construction"),
        key_pem: String::from_utf8(key_pem.as_bytes().to_vec())
            .map_err(|error| format!("编码 RSA 私钥失败: {error}"))?,
    })
}

/// SAN list for the `x509-cert` RSA path, mirroring [`subject_alt_names`].
fn x509_subject_alt_names(config: &CertConfig) -> Result<Vec<GeneralName>, String> {
    let mut names = Vec::new();
    for name in &config.dns_names {
        let value =
            DerIa5String::new(name).map_err(|_| format!("证书 SAN 中的域名无效: {name:?}"))?;
        names.push(GeneralName::DnsName(value));
    }
    for raw in &config.ip_addresses {
        let ip: IpAddr = raw
            .parse()
            .map_err(|_| format!("证书 SAN 中的 IP 地址无效: {raw:?}"))?;
        names.push(GeneralName::from(ip));
    }
    if names.is_empty() {
        names.push(GeneralName::from(IpAddr::V4(Ipv4Addr::LOCALHOST)));
        names.push(GeneralName::from(IpAddr::V6(Ipv6Addr::LOCALHOST)));
    }
    Ok(names)
}

/// Common name resolution, matching `certCommonName`.
fn common_name(config: &CertConfig) -> String {
    if !config.common_name.is_empty() {
        return config.common_name.clone();
    }
    if let Some(name) = config.dns_names.first() {
        return name.clone();
    }
    if let Some(address) = config.ip_addresses.first() {
        return address.clone();
    }
    DEFAULT_SERVER_NAME.to_string()
}

/// SAN list, matching `GenerateSelfSignedCert`: invalid IP literals are rejected and an empty SAN
/// list defaults to the two loopback addresses.
fn subject_alt_names(config: &CertConfig) -> Result<Vec<SanType>, String> {
    let mut names = Vec::new();

    for name in &config.dns_names {
        let name = Ia5String::try_from(name.as_str())
            .map_err(|_| format!("证书 SAN 中的域名无效: {name:?}"))?;
        names.push(SanType::DnsName(name));
    }

    for raw in &config.ip_addresses {
        let ip: IpAddr = raw
            .parse()
            .map_err(|_| format!("证书 SAN 中的 IP 地址无效: {raw:?}"))?;
        names.push(SanType::IpAddress(ip));
    }

    if names.is_empty() {
        names.push(SanType::IpAddress(IpAddr::V4(Ipv4Addr::LOCALHOST)));
        names.push(SanType::IpAddress(IpAddr::V6(Ipv6Addr::LOCALHOST)));
    }

    Ok(names)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::BufReader;

    use x509_cert::der::Decode;
    use x509_cert::ext::pkix::name::GeneralName;
    use x509_cert::ext::pkix::SubjectAltName;
    use x509_cert::Certificate;

    fn config() -> CertConfig {
        CertConfig {
            key_type: "ecdsa".to_string(),
            common_name: "dns.lan".to_string(),
            dns_names: vec!["dns.lan".to_string(), "alt.lan".to_string()],
            ip_addresses: vec!["127.0.0.1".to_string(), "::1".to_string()],
            valid_days: 30,
            ..CertConfig::default()
        }
    }

    fn parse_certificate(pem: &str) -> Certificate {
        let der = rustls_pemfile::certs(&mut BufReader::new(pem.as_bytes()))
            .next()
            .expect("one certificate")
            .expect("valid DER");
        Certificate::from_der(der.as_ref()).expect("parse certificate")
    }

    fn sans(certificate: &Certificate) -> (Vec<String>, Vec<String>) {
        let mut dns = Vec::new();
        let mut ips = Vec::new();
        for extension in certificate
            .tbs_certificate
            .extensions
            .as_deref()
            .unwrap_or(&[])
        {
            if extension.extn_id.to_string() != "2.5.29.17" {
                continue;
            }
            let san = SubjectAltName::from_der(extension.extn_value.as_bytes()).unwrap();
            for name in san.0 {
                match name {
                    GeneralName::DnsName(name) => dns.push(name.as_str().to_string()),
                    GeneralName::IpAddress(bytes) => ips.push(match bytes.as_bytes().len() {
                        4 => {
                            let raw = bytes.as_bytes();
                            Ipv4Addr::new(raw[0], raw[1], raw[2], raw[3]).to_string()
                        }
                        16 => {
                            let mut raw = [0u8; 16];
                            raw.copy_from_slice(bytes.as_bytes());
                            Ipv6Addr::from(raw).to_string()
                        }
                        _ => continue,
                    }),
                    _ => {}
                }
            }
        }
        (dns, ips)
    }

    #[test]
    fn generates_sans_ca_and_pkcs8_key() {
        let generated = generate_self_signed(&config()).expect("generate");
        assert!(generated
            .cert_pem
            .starts_with("-----BEGIN CERTIFICATE-----"));
        assert!(generated.key_pem.starts_with("-----BEGIN PRIVATE KEY-----"));

        let key = rustls_pemfile::private_key(&mut BufReader::new(generated.key_pem.as_bytes()))
            .expect("read key")
            .expect("one key");
        assert!(matches!(key, rustls::pki_types::PrivateKeyDer::Pkcs8(_)));

        let certificate = parse_certificate(&generated.cert_pem);
        let (dns, ips) = sans(&certificate);
        assert_eq!(dns, vec!["dns.lan", "alt.lan"]);
        assert_eq!(ips, vec!["127.0.0.1", "::1"]);
        assert_eq!(
            certificate.tbs_certificate.subject.to_string(),
            "O=DITING,CN=dns.lan"
        );

        let validity = &certificate.tbs_certificate.validity;
        let not_before = validity.not_before.to_unix_duration().as_secs() as i64;
        let not_after = validity.not_after.to_unix_duration().as_secs() as i64;
        let now = chrono::Utc::now().timestamp();
        assert!((not_before - (now - 86_400)).abs() <= 5);
        assert!((not_after - (now + 30 * 86_400)).abs() <= 5);
    }

    #[test]
    fn empty_sans_default_to_loopback() {
        let mut config = config();
        config.dns_names.clear();
        config.ip_addresses.clear();
        let certificate = parse_certificate(&generate_self_signed(&config).unwrap().cert_pem);
        let (dns, ips) = sans(&certificate);
        assert!(dns.is_empty());
        assert_eq!(ips, vec!["127.0.0.1", "::1"]);
        assert_eq!(
            certificate.tbs_certificate.subject.to_string(),
            format!("O=DITING,CN={DEFAULT_SERVER_NAME}")
        );
    }

    #[test]
    fn invalid_ip_san_is_rejected() {
        let mut config = config();
        config.ip_addresses = vec!["not-an-ip".to_string()];
        let error = generate_self_signed(&config).expect_err("invalid IP");
        assert!(error.contains("IP 地址无效"), "{error}");
    }

    #[test]
    fn rsa_generates_a_3072_bit_pkcs8_pair() {
        use rsa::pkcs8::DecodePrivateKey;
        use rsa::traits::PublicKeyParts;

        let mut config = config();
        config.key_type = "rsa".to_string();
        let generated = generate_self_signed(&config).expect("generate RSA");
        assert!(generated
            .cert_pem
            .starts_with("-----BEGIN CERTIFICATE-----"));
        assert!(generated.key_pem.starts_with("-----BEGIN PRIVATE KEY-----"));

        let key = rsa::RsaPrivateKey::from_pkcs8_pem(&generated.key_pem).expect("PKCS#8 key");
        assert_eq!(key.n().bits(), 3072);
        super::super::material::parse_pair(
            generated.cert_pem.as_bytes(),
            generated.key_pem.as_bytes(),
        )
        .expect("certificate matches key");

        let certificate = parse_certificate(&generated.cert_pem);
        assert_eq!(
            certificate.tbs_certificate.subject.to_string(),
            "O=DITING,CN=dns.lan"
        );
        let (dns, ips) = sans(&certificate);
        assert_eq!(dns, vec!["dns.lan", "alt.lan"]);
        assert_eq!(ips, vec!["127.0.0.1", "::1"]);

        let extensions = certificate
            .tbs_certificate
            .extensions
            .as_deref()
            .unwrap_or(&[]);
        let key_usage = extensions
            .iter()
            .find(|extension| extension.extn_id.to_string() == "2.5.29.15")
            .expect("key usage");
        let usage = x509_cert::ext::pkix::KeyUsage::from_der(key_usage.extn_value.as_bytes())
            .expect("parse key usage");
        assert!(usage
            .0
            .contains(x509_cert::ext::pkix::KeyUsages::DigitalSignature));
        assert!(usage
            .0
            .contains(x509_cert::ext::pkix::KeyUsages::KeyEncipherment));
        assert!(usage
            .0
            .contains(x509_cert::ext::pkix::KeyUsages::KeyCertSign));
    }
}
