use const_oid::db::rfc4519::{COMMON_NAME, ORGANIZATION_NAME};
use const_oid::db::rfc5280::{ID_CE_BASIC_CONSTRAINTS, ID_KP_SERVER_AUTH};
use const_oid::db::rfc5912::ID_EC_PUBLIC_KEY;
use const_oid::{AssociatedOid, ObjectIdentifier};
use der::asn1::{Ia5String, PrintableStringRef, Utf8StringRef};
use der::referenced::OwnedToRef;
use der::{Any, Decode, Encode, Length, Writer};
use ecdsa::der::Signature as DerSignature;
use p256::ecdsa::SigningKey;
use p256::elliptic_curve::sec1::ToSec1Point;
use p256::elliptic_curve::Generate;
use p256::pkcs8::DecodePrivateKey;
use p256::{NistP256, SecretKey};
use sec1::{EcParameters, EcPrivateKey};
use x509_cert::attr::AttributeTypeAndValue;
use x509_cert::builder::profile::BuilderProfile;
use x509_cert::builder::{Builder, CertificateBuilder};
use x509_cert::ext::pkix::name::{GeneralName, GeneralNames};
use x509_cert::ext::pkix::{
    AuthorityKeyIdentifier, BasicConstraints, ExtendedKeyUsage, KeyUsage, KeyUsages,
    SubjectAltName, SubjectKeyIdentifier,
};
use x509_cert::ext::{Criticality, Extension};
use x509_cert::name::{Name, RdnSequence, RelativeDistinguishedName};
use x509_cert::serial_number::SerialNumber;
use x509_cert::time::{Time, Validity};
use x509_cert::Certificate;
use x509_cert::SubjectPublicKeyInfo;

use crate::pem;

pub const CA_ORGANIZATION: &str = "DITING";
pub const CA_COMMON_NAME: &str = "DITING HTTPS Inspection Root CA";
pub const CA_VALIDITY_BEFORE_SECS: i64 = 24 * 60 * 60;
pub const CA_VALIDITY_AFTER_SECS: i64 = 10 * 365 * 24 * 60 * 60;
pub const LEAF_VALIDITY_BEFORE_SECS: i64 = 60 * 60;
pub const LEAF_VALIDITY_AFTER_SECS: i64 = 24 * 60 * 60;

pub struct CertAuthority {
    ca_cert: Certificate,
    ca_cert_der: Vec<u8>,
    ca_cert_pem: String,
    ca_subject: Name,
    ca_spki: SubjectPublicKeyInfo,
    ca_signing: SigningKey,
    leaf_secret: SecretKey,
}

pub struct GeneratedCa {
    pub authority: CertAuthority,
    pub ca_key_pem: String,
}

pub struct IssuedLeaf {
    pub chain_pem: String,
    pub key_pem: String,
    pub not_after_unix: i64,
}

impl CertAuthority {
    pub fn generate(now_unix: i64) -> Result<GeneratedCa, String> {
        let ca_secret =
            SecretKey::try_generate().map_err(|err| format!("create CA cert: {err}"))?;
        let ca_signing = SigningKey::from(&ca_secret);
        let ca_spki = SubjectPublicKeyInfo::from_key(ca_signing.verifying_key())
            .map_err(|err| format!("create CA cert: {err}"))?;

        let mut builder = CertificateBuilder::new(
            ManualProfile::self_signed(CA_COMMON_NAME)?,
            random_serial()?,
            validity(
                now_unix,
                CA_VALIDITY_BEFORE_SECS,
                CA_VALIDITY_AFTER_SECS,
                "create CA cert",
            )?,
            ca_spki.clone(),
        )
        .map_err(|err| format!("create CA cert: {err}"))?;
        let subject_key_id = SubjectKeyIdentifier::try_from(ca_spki.owned_to_ref())
            .map_err(|err| format!("create CA cert: {err}"))?;
        builder
            .add_extension(&subject_key_id)
            .map_err(|err| format!("create CA cert: {err}"))?;
        builder
            .add_extension(&BasicConstraints {
                ca: true,
                path_len_constraint: Some(1),
            })
            .map_err(|err| format!("create CA cert: {err}"))?;
        builder
            .add_extension(&KeyUsage(KeyUsages::KeyCertSign | KeyUsages::CRLSign))
            .map_err(|err| format!("create CA cert: {err}"))?;
        let ca_cert = builder
            .build::<_, DerSignature<NistP256>>(&ca_signing)
            .map_err(|err| format!("create CA cert: {err}"))?;

        let ca_key_pem = sec1_pem(&ca_secret)?;
        let leaf_secret =
            SecretKey::try_generate().map_err(|err| format!("create CA cert: {err}"))?;
        let authority = CertAuthority::new(ca_cert, ca_signing, ca_spki, leaf_secret)?;
        Ok(GeneratedCa {
            authority,
            ca_key_pem,
        })
    }

    pub fn load(cert_pem: &str, key_pem: &str, now_unix: i64) -> Result<Self, String> {
        let cert_block = pem::decode(cert_pem)
            .ok_or_else(|| "decode CA cert PEM: no PEM block found".to_string())?;
        let ca_cert = Certificate::from_der(&cert_block.der)
            .map_err(|err| format!("parse CA cert: {err}"))?;

        if !is_ca(&ca_cert) {
            return Err("loaded certificate is not a CA (IsCA=false)".to_string());
        }
        let (common_name, organizations) = subject(&ca_cert);
        if common_name.as_deref() != Some(CA_COMMON_NAME)
            || organizations != [CA_ORGANIZATION.to_string()]
        {
            return Err("loaded certificate has an outdated subject".to_string());
        }
        let validity = ca_cert.tbs_certificate().validity();
        let not_before = time_to_unix(validity.not_before);
        let not_after = time_to_unix(validity.not_after);
        if now_unix < not_before || now_unix > not_after {
            return Err(format!(
                "CA certificate expired or not yet valid (NotBefore={}, NotAfter={})",
                ymd(not_before),
                ymd(not_after)
            ));
        }

        let key_block = pem::decode(key_pem)
            .ok_or_else(|| "decode CA key PEM: no PEM block found".to_string())?;
        let ca_secret = SecretKey::from_sec1_der(&key_block.der)
            .or_else(|_| SecretKey::from_pkcs8_der(&key_block.der))
            .map_err(|err| format!("parse CA key: {err}"))?;
        let subject_public_key_info = ca_cert.tbs_certificate().subject_public_key_info();
        if subject_public_key_info.algorithm.oid != ID_EC_PUBLIC_KEY {
            return Err("CA certificate public key is not ECDSA".to_string());
        }
        let derived = ca_secret.public_key().to_sec1_point(false);
        if subject_public_key_info.subject_public_key.raw_bytes() != derived.as_bytes() {
            return Err("CA private key does not match certificate public key".to_string());
        }

        let ca_signing = SigningKey::from(&ca_secret);
        let ca_spki = subject_public_key_info.clone();
        let leaf_secret =
            SecretKey::try_generate().map_err(|err| format!("parse CA key: {err}"))?;
        CertAuthority::new(ca_cert, ca_signing, ca_spki, leaf_secret)
    }

    pub fn issue(&self, host: &str, now_unix: i64) -> Result<IssuedLeaf, String> {
        let not_after_unix = now_unix
            .checked_add(LEAF_VALIDITY_AFTER_SECS)
            .ok_or_else(|| format!("sign leaf cert for {host}: time overflows"))?;
        let leaf_spki =
            SubjectPublicKeyInfo::from_key(SigningKey::from(&self.leaf_secret).verifying_key())
                .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        let dns_names =
            dns_names(host).map_err(|err| format!("sign leaf cert for {host}: {err}"))?;

        let mut builder = CertificateBuilder::new(
            ManualProfile {
                subject: name(host)?,
                issuer: self.ca_subject.clone(),
            },
            random_serial().map_err(|err| format!("generate serial for {host}: {err}"))?,
            validity(
                now_unix,
                LEAF_VALIDITY_BEFORE_SECS,
                LEAF_VALIDITY_AFTER_SECS,
                "sign leaf cert",
            )?,
            leaf_spki,
        )
        .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;

        let key_identifier = SubjectKeyIdentifier::try_from(self.ca_spki.owned_to_ref())
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&AuthorityKeyIdentifier {
                key_identifier: Some(key_identifier.0),
                ..Default::default()
            })
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&BasicConstraints {
                ca: false,
                path_len_constraint: None,
            })
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&KeyUsage(KeyUsages::DigitalSignature.into()))
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&NonCriticalExtendedKeyUsage(ExtendedKeyUsage(vec![
                ID_KP_SERVER_AUTH,
            ])))
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        builder
            .add_extension(&SubjectAltName(dns_names))
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;

        let leaf = builder
            .build::<_, DerSignature<NistP256>>(&self.ca_signing)
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        let leaf_der = leaf
            .to_der()
            .map_err(|err| format!("sign leaf cert for {host}: {err}"))?;
        let mut chain_pem = pem::encode("CERTIFICATE", &leaf_der);
        chain_pem.push_str(&self.ca_cert_pem);
        Ok(IssuedLeaf {
            chain_pem,
            key_pem: sec1_pem(&self.leaf_secret)?,
            not_after_unix,
        })
    }

    pub fn ca_pem(&self) -> &str {
        &self.ca_cert_pem
    }

    pub fn ca_der(&self) -> &[u8] {
        &self.ca_cert_der
    }

    pub fn ca_certificate(&self) -> &Certificate {
        &self.ca_cert
    }

    fn new(
        ca_cert: Certificate,
        ca_signing: SigningKey,
        ca_spki: SubjectPublicKeyInfo,
        leaf_secret: SecretKey,
    ) -> Result<Self, String> {
        let ca_cert_der = ca_cert
            .to_der()
            .map_err(|err| format!("encode CA cert: {err}"))?;
        let ca_cert_pem = pem::encode("CERTIFICATE", &ca_cert_der);
        let ca_subject = ca_cert.tbs_certificate().subject().clone();
        Ok(CertAuthority {
            ca_cert,
            ca_cert_der,
            ca_cert_pem,
            ca_subject,
            ca_spki,
            ca_signing,
            leaf_secret,
        })
    }
}

pub fn dns_names(host: &str) -> Result<GeneralNames, String> {
    let mut names = Vec::with_capacity(2);
    names.push(GeneralName::DnsName(Ia5String::new(host).map_err(
        |_| format!("{host:?} cannot be encoded as an IA5String"),
    )?));
    if let Some((_, rest)) = host.split_once('.') {
        if rest.contains('.') {
            let wildcard = format!("*.{rest}");
            names.push(GeneralName::DnsName(Ia5String::new(&wildcard).map_err(
                |_| format!("{wildcard:?} cannot be encoded as an IA5String"),
            )?));
        }
    }
    Ok(names)
}

struct NonCriticalExtendedKeyUsage(ExtendedKeyUsage);

impl AssociatedOid for NonCriticalExtendedKeyUsage {
    const OID: ObjectIdentifier = ExtendedKeyUsage::OID;
}

impl Criticality for NonCriticalExtendedKeyUsage {
    fn criticality(&self, _subject: &Name, _extensions: &[Extension]) -> bool {
        false
    }
}

impl Encode for NonCriticalExtendedKeyUsage {
    fn encoded_len(&self) -> der::Result<Length> {
        self.0.encoded_len()
    }

    fn encode(&self, writer: &mut impl Writer) -> der::Result<()> {
        self.0.encode(writer)
    }
}

fn random_serial() -> Result<SerialNumber, String> {
    let mut bytes = rand::random::<[u8; 16]>();
    bytes[0] = (bytes[0] & 0x7f) | 0x01;
    SerialNumber::new(&bytes).map_err(|err| format!("generate serial: {err}"))
}

fn validity(
    now_unix: i64,
    before_secs: i64,
    after_secs: i64,
    context: &str,
) -> Result<Validity, String> {
    Ok(Validity::new(
        unix_to_time(now_unix - before_secs).map_err(|err| format!("{context}: {err}"))?,
        unix_to_time(now_unix + after_secs).map_err(|err| format!("{context}: {err}"))?,
    ))
}

fn unix_to_time(unix: i64) -> Result<Time, String> {
    let seconds = u64::try_from(unix).map_err(|_| "validity before the unix epoch".to_string())?;
    Time::try_from(std::time::UNIX_EPOCH + std::time::Duration::from_secs(seconds))
        .map_err(|err| format!("encode validity time: {err}"))
}

fn name(common_name: &str) -> Result<Name, String> {
    let mut sequence = RdnSequence::default();
    sequence.push(rdn(ORGANIZATION_NAME, CA_ORGANIZATION)?);
    sequence.push(rdn(COMMON_NAME, common_name)?);
    Ok(Name::hazmat_from_rdn_sequence(sequence))
}

struct ManualProfile {
    subject: Name,
    issuer: Name,
}

impl ManualProfile {
    fn self_signed(common_name: &str) -> Result<Self, String> {
        let subject = name(common_name)?;
        Ok(Self {
            subject: subject.clone(),
            issuer: subject,
        })
    }
}

impl BuilderProfile for ManualProfile {
    fn get_issuer(&self, _subject: &Name) -> Name {
        self.issuer.clone()
    }

    fn get_subject(&self) -> Name {
        self.subject.clone()
    }

    fn build_extensions(
        &self,
        _spk: x509_cert::spki::SubjectPublicKeyInfoRef<'_>,
        _issuer_spk: x509_cert::spki::SubjectPublicKeyInfoRef<'_>,
        _tbs: &x509_cert::certificate::TbsCertificate,
    ) -> x509_cert::builder::Result<Vec<Extension>> {
        Ok(Vec::new())
    }
}

fn rdn(oid: ObjectIdentifier, value: &str) -> Result<RelativeDistinguishedName, String> {
    let any = match PrintableStringRef::new(value) {
        Ok(printable) => Any::from(printable),
        Err(_) => Any::from(
            Utf8StringRef::new(value)
                .map_err(|_| format!("{value:?} cannot be encoded as a name"))?,
        ),
    };
    RelativeDistinguishedName::try_from(vec![AttributeTypeAndValue { oid, value: any }])
        .map_err(|err| format!("build name for {value:?}: {err}"))
}

fn sec1_pem(secret: &SecretKey) -> Result<String, String> {
    let private_key = secret.to_bytes();
    let public_key = secret.public_key().to_sec1_point(false);
    let key = EcPrivateKey {
        private_key: &private_key,
        parameters: Some(EcParameters::NamedCurve(NistP256::OID)),
        public_key: Some(public_key.as_bytes()),
    };
    let der = key
        .to_der()
        .map_err(|err| format!("encode private key: {err}"))?;
    Ok(pem::encode("EC PRIVATE KEY", &der))
}

fn is_ca(cert: &Certificate) -> bool {
    let Some(extensions) = cert.tbs_certificate().extensions() else {
        return false;
    };
    extensions
        .iter()
        .find(|extension| extension.extn_id == ID_CE_BASIC_CONSTRAINTS)
        .and_then(|extension| BasicConstraints::from_der(extension.extn_value.as_bytes()).ok())
        .map(|constraints| constraints.ca)
        .unwrap_or(false)
}

pub fn subject(cert: &Certificate) -> (Option<String>, Vec<String>) {
    let mut common_name = None;
    let mut organizations = Vec::new();
    for rdn in cert.tbs_certificate().subject().iter_rdn() {
        for attribute in rdn.iter() {
            let text = String::from_utf8_lossy(attribute.value.value()).into_owned();
            if attribute.oid == COMMON_NAME {
                common_name = Some(text);
            } else if attribute.oid == ORGANIZATION_NAME {
                organizations.push(text);
            }
        }
    }
    (common_name, organizations)
}

pub fn time_to_unix(time: Time) -> i64 {
    let date = time.to_date_time();
    let days = days_from_civil(date.year().into(), date.month(), date.day());
    days * 86_400
        + i64::from(date.hour()) * 3_600
        + i64::from(date.minutes()) * 60
        + i64::from(date.seconds())
}

fn days_from_civil(year: i64, month: u8, day: u8) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let month = i64::from(month);
    let month_shifted = if month > 2 { month - 3 } else { month + 9 };
    let day_of_year = (153 * month_shifted + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

pub fn ymd(unix: i64) -> String {
    let days = unix.div_euclid(86_400);
    let shifted = days + 719_468;
    let era = if shifted >= 0 {
        shifted
    } else {
        shifted - 146_096
    } / 146_097;
    let day_of_era = shifted - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_position = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_position + 2) / 5 + 1;
    let month = if month_position < 10 {
        month_position + 3
    } else {
        month_position - 9
    };
    if month <= 2 {
        year += 1;
    }
    format!("{year:04}-{month:02}-{day:02}")
}

#[cfg(test)]
mod tests;
