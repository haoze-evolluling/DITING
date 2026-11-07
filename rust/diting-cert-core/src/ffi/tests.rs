//! The C ABI: statuses, payload shapes and the handle lifecycle.

use super::*;

struct Payload {
    pointer: *mut u8,
    length: usize,
}

impl Payload {
    fn take(&mut self) -> Vec<u8> {
        if self.pointer.is_null() {
            return Vec::new();
        }
        let bytes = unsafe { slice::from_raw_parts(self.pointer, self.length).to_vec() };
        unsafe { diting_cert_free_bytes(self.pointer, self.length) };
        self.pointer = std::ptr::null_mut();
        self.length = 0;
        bytes
    }

    fn texts(&mut self) -> Vec<String> {
        let mut body = self.take();
        let mut texts = Vec::new();
        while body.len() >= 4 {
            let length = u32::from_le_bytes(body[..4].try_into().unwrap()) as usize;
            body.drain(..4);
            let text: Vec<u8> = body.drain(..length).collect();
            texts.push(String::from_utf8(text).unwrap());
        }
        assert!(body.is_empty(), "{body:?} left over");
        texts
    }
}

fn generate(now_unix: i64) -> (*mut CertAuthority, Vec<String>) {
    let mut handle: *mut CertAuthority = std::ptr::null_mut();
    let mut payload = Payload {
        pointer: std::ptr::null_mut(),
        length: 0,
    };
    let status = unsafe {
        diting_cert_generate(
            now_unix,
            &mut handle,
            &mut payload.pointer,
            &mut payload.length,
        )
    };
    assert_eq!(status, STATUS_OK);
    assert!(!handle.is_null());
    (handle, payload.texts())
}

#[test]
fn abi_version_is_published() {
    assert_eq!(diting_cert_abi_version(), ABI_VERSION);
}

#[test]
fn generate_returns_the_ca_and_key_pem() {
    let (handle, texts) = generate(1_794_052_800);
    assert_eq!(texts.len(), 2);
    assert!(texts[0].starts_with("-----BEGIN CERTIFICATE-----"));
    assert!(texts[1].starts_with("-----BEGIN EC PRIVATE KEY-----"));
    unsafe { diting_cert_free(handle) };
}

#[test]
fn ca_pem_round_trips_through_a_handle() {
    let (handle, texts) = generate(1_794_052_800);
    let mut payload = Payload {
        pointer: std::ptr::null_mut(),
        length: 0,
    };
    let status = unsafe { diting_cert_ca_pem(handle, &mut payload.pointer, &mut payload.length) };
    assert_eq!(status, STATUS_OK);
    assert_eq!(payload.texts(), vec![texts[0].clone()]);
    unsafe { diting_cert_free(handle) };
}

#[test]
fn issue_returns_the_chain_key_and_expiry() {
    let (handle, _) = generate(1_794_052_800);
    let host = "www.example.com";
    let mut payload = Payload {
        pointer: std::ptr::null_mut(),
        length: 0,
    };
    let status = unsafe {
        diting_cert_issue(
            handle,
            host.as_ptr(),
            host.len(),
            1_794_052_800,
            &mut payload.pointer,
            &mut payload.length,
        )
    };
    assert_eq!(status, STATUS_OK);
    let mut body = payload.take();
    let mut texts = Vec::new();
    for _ in 0..2 {
        let length = u32::from_le_bytes(body[..4].try_into().unwrap()) as usize;
        body.drain(..4);
        let text: Vec<u8> = body.drain(..length).collect();
        texts.push(String::from_utf8(text).unwrap());
    }
    let not_after = i64::from_le_bytes(body[..8].try_into().unwrap());
    body.drain(..8);
    assert!(body.is_empty());
    assert!(texts[0].starts_with("-----BEGIN CERTIFICATE-----"));
    assert!(texts[1].starts_with("-----BEGIN EC PRIVATE KEY-----"));
    assert_eq!(
        not_after,
        1_794_052_800 + crate::ca::LEAF_VALIDITY_AFTER_SECS
    );
}

#[test]
fn load_adopts_a_persisted_pair() {
    let (handle, texts) = generate(1_794_052_800);
    unsafe { diting_cert_free(handle) };

    let mut loaded: *mut CertAuthority = std::ptr::null_mut();
    let mut payload = Payload {
        pointer: std::ptr::null_mut(),
        length: 0,
    };
    let status = unsafe {
        diting_cert_load(
            texts[0].as_ptr(),
            texts[0].len(),
            texts[1].as_ptr(),
            texts[1].len(),
            1_794_052_800,
            &mut loaded,
            &mut payload.pointer,
            &mut payload.length,
        )
    };
    assert_eq!(status, STATUS_OK);
    assert!(!loaded.is_null());
    assert!(payload.take().is_empty(), "load has no success payload");
    unsafe { diting_cert_free(loaded) };
}

#[test]
fn operation_errors_are_status_three_with_a_message() {
    let (handle, texts) = generate(1_794_052_800);
    // Expired for the second handle's clock, but the same CA: force the key-mismatch path.
    let mut loaded: *mut CertAuthority = std::ptr::null_mut();
    let mut payload = Payload {
        pointer: std::ptr::null_mut(),
        length: 0,
    };
    let status = unsafe {
        diting_cert_load(
            texts[0].as_ptr(),
            texts[0].len(),
            texts[1].as_ptr(),
            texts[1].len(),
            1_794_052_800 + crate::ca::CA_VALIDITY_AFTER_SECS + 1,
            &mut loaded,
            &mut payload.pointer,
            &mut payload.length,
        )
    };
    assert_eq!(status, STATUS_OPERATION);
    assert!(loaded.is_null());
    let messages = payload.texts();
    assert_eq!(messages.len(), 1);
    assert!(messages[0].starts_with("CA certificate expired or not yet valid"));
    unsafe { diting_cert_free(handle) };
}

#[test]
fn bad_arguments_and_bad_payloads() {
    let mut payload = Payload {
        pointer: std::ptr::null_mut(),
        length: 0,
    };
    assert_eq!(
        unsafe {
            diting_cert_generate(
                0,
                std::ptr::null_mut(),
                &mut payload.pointer,
                &mut payload.length,
            )
        },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_cert_ca_pem(std::ptr::null(), &mut payload.pointer, &mut payload.length) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe {
            diting_cert_issue(
                std::ptr::null(),
                b"h".as_ptr(),
                1,
                0,
                &mut payload.pointer,
                &mut payload.length,
            )
        },
        STATUS_BAD_ARGUMENT
    );

    let (handle, _) = generate(1_794_052_800);
    let mut reloaded: *mut CertAuthority = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            diting_cert_issue(
                handle,
                [0xffu8, 0xfe].as_ptr(),
                2,
                0,
                &mut payload.pointer,
                &mut payload.length,
            )
        },
        STATUS_BAD_PAYLOAD
    );
    assert_eq!(
        unsafe {
            diting_cert_load(
                [0xffu8].as_ptr(),
                1,
                std::ptr::null(),
                0,
                0,
                &mut reloaded,
                &mut payload.pointer,
                &mut payload.length,
            )
        },
        STATUS_BAD_PAYLOAD
    );
}

#[test]
fn ev_check_is_a_single_integer() {
    assert_eq!(unsafe { diting_cert_is_ev(std::ptr::null(), 0) }, 0);
    let ev = "2.23.140.1.1";
    assert_eq!(unsafe { diting_cert_is_ev(ev.as_ptr(), ev.len()) }, 1);
    let dv = "2.23.140.1.2.1";
    assert_eq!(unsafe { diting_cert_is_ev(dv.as_ptr(), dv.len()) }, 0);
    assert_eq!(unsafe { diting_cert_is_ev([0xffu8].as_ptr(), 1) }, 0);
}
