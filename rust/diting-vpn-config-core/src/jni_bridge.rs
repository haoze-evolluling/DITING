use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jstring, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;

use crate::route::{ipv6_probe_needed, route_plan};
use crate::start::start_defaults;

fn read(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    Some(env.get_string(value).ok()?.into())
}

fn to_jstring(env: &JNIEnv<'_>, value: String) -> jstring {
    match env.new_string(value) {
        Ok(text) => text.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_vpn_VpnPlanNative_routePlan<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    mode: JString<'local>,
    ipv6_mode: JString<'local>,
    ipv6_supported: jboolean,
    bypass_lan: jboolean,
    excluded: JString<'local>,
    self_package: JString<'local>,
    proxy_package: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let mode = read(&mut env, &mode)?;
        let ipv6_mode = read(&mut env, &ipv6_mode)?;
        let excluded = read(&mut env, &excluded)?;
        let self_package = read(&mut env, &self_package)?;
        let proxy_package = read(&mut env, &proxy_package)?;
        let packages: Vec<String> = excluded.split('\n').map(str::to_owned).collect();
        let plan = route_plan(
            &mode,
            &ipv6_mode,
            ipv6_supported != JNI_FALSE,
            bypass_lan != JNI_FALSE,
            &packages,
            &self_package,
            &proxy_package,
        )?;
        Some(plan.to_string())
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_vpn_VpnPlanNative_ipv6ProbeNeeded<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    ipv6_mode: JString<'local>,
) -> jboolean {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let ipv6_mode = read(&mut env, &ipv6_mode)?;
        Some(ipv6_probe_needed(&ipv6_mode))
    }));
    match answer {
        Ok(Some(true)) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_vpn_VpnPlanNative_startDefaults<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
) -> jstring {
    to_jstring(&env, start_defaults().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::route::route_plan;

    #[test]
    fn route_plan_is_dispatched_by_mode() {
        assert!(route_plan("express", "auto", true, false, &[], "a", "b").is_some());
        assert!(route_plan("server", "auto", true, false, &[], "a", "b").is_none());
    }

    #[test]
    fn defaults_have_the_restore_fields() {
        let defaults = start_defaults();
        assert_eq!(defaults["ipv6Mode"], "auto");
        assert!(defaults["outboundProxy"]
            .as_str()
            .unwrap()
            .contains("SOCKS5"));
    }
}


mod watchdog_jni {
    use std::panic::{catch_unwind, AssertUnwindSafe};

    use jni::objects::{JObject, JString};
    use jni::sys::{jboolean, jbyteArray, jint, jlong, JNI_FALSE, JNI_TRUE};
    use jni::JNIEnv;

    use crate::watchdog::{reclaim_allowed, reconnect_decision, should_follow, Watchdog};

    fn read(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
        Some(env.get_string(value).ok()?.into())
    }

    unsafe fn with_handle<R>(handle: jlong, run: impl FnOnce(&mut Watchdog) -> R) -> Option<R> {
        if handle == 0 {
            return None;
        }
        Some(run(&mut *(handle as *mut Watchdog)))
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_newHandle(
        _env: JNIEnv<'_>,
        _this: JObject<'_>,
    ) -> jlong {
        catch_unwind(AssertUnwindSafe(|| {
            Box::into_raw(Box::new(Watchdog::new())) as jlong
        }))
        .unwrap_or(0)
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_free(
        _env: JNIEnv<'_>,
        _this: JObject<'_>,
        handle: jlong,
    ) {
        if handle == 0 {
            return;
        }
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            drop(Box::from_raw(handle as *mut Watchdog));
        }));
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_start(
        _env: JNIEnv<'_>,
        _this: JObject<'_>,
        handle: jlong,
        now_ms: jlong,
    ) -> jlong {
        catch_unwind(AssertUnwindSafe(|| {
            unsafe { with_handle(handle, |watchdog| watchdog.start(now_ms)) }.unwrap_or(-1)
        }))
        .unwrap_or(-1)
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_evaluate<'local>(
        env: JNIEnv<'local>,
        _this: JObject<'local>,
        handle: jlong,
        now_ms: jlong,
        occupied: jboolean,
    ) -> jbyteArray {
        let answer = catch_unwind(AssertUnwindSafe(|| {
            let step = unsafe {
                with_handle(handle, |watchdog| {
                    watchdog.evaluate(now_ms, occupied != JNI_FALSE)
                })?
            };
            let mut bytes = Vec::with_capacity(9);
            bytes.push(step.event as u8);
            bytes.extend_from_slice(&step.next_delay_ms.to_be_bytes());
            env.byte_array_from_slice(&bytes).ok()
        }));
        match answer {
            Ok(Some(value)) => value.into_raw(),
            _ => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_stop(
        _env: JNIEnv<'_>,
        _this: JObject<'_>,
        handle: jlong,
    ) {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            with_handle(handle, |watchdog| watchdog.stop());
        }));
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_shouldFollow<'local>(
        mut env: JNIEnv<'local>,
        _this: JObject<'local>,
        enabled: jboolean,
        current_mode: JString<'local>,
        expected_mode: JString<'local>,
        has_intent: jboolean,
    ) -> jboolean {
        let answer = catch_unwind(AssertUnwindSafe(|| {
            let current_mode = read(&mut env, &current_mode)?;
            let expected_mode = read(&mut env, &expected_mode)?;
            Some(should_follow(
                enabled != JNI_FALSE,
                &current_mode,
                &expected_mode,
                has_intent != JNI_FALSE,
            ))
        }));
        match answer {
            Ok(Some(true)) => JNI_TRUE,
            _ => JNI_FALSE,
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_reclaimAllowed<
        'local,
    >(
        mut env: JNIEnv<'local>,
        _this: JObject<'local>,
        enabled: jboolean,
        current_mode: JString<'local>,
        expected_mode: JString<'local>,
    ) -> jboolean {
        let answer = catch_unwind(AssertUnwindSafe(|| {
            let current_mode = read(&mut env, &current_mode)?;
            let expected_mode = read(&mut env, &expected_mode)?;
            Some(reclaim_allowed(
                enabled != JNI_FALSE,
                &current_mode,
                &expected_mode,
            ))
        }));
        match answer {
            Ok(Some(true)) => JNI_TRUE,
            _ => JNI_FALSE,
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_reconnectDecision<
        'local,
    >(
        mut env: JNIEnv<'local>,
        _this: JObject<'local>,
        enabled: jboolean,
        current_mode: JString<'local>,
        expected_mode: JString<'local>,
        consent_missing: jboolean,
        has_intent: jboolean,
    ) -> jint {
        catch_unwind(AssertUnwindSafe(|| {
            let Some(current_mode) = read(&mut env, &current_mode) else {
                return -1;
            };
            let Some(expected_mode) = read(&mut env, &expected_mode) else {
                return -1;
            };
            reconnect_decision(
                enabled != JNI_FALSE,
                &current_mode,
                &expected_mode,
                consent_missing != JNI_FALSE,
                has_intent != JNI_FALSE,
            )
            .code()
        }))
        .unwrap_or(-1)
    }
}
