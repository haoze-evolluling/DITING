use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JObject, JString};
use jni::sys::jboolean;
use jni::{Env, EnvUnowned};

use crate::route::{ipv6_probe_needed, route_plan};
use crate::start::start_defaults;

fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

fn read(env: &mut Env<'_>, value: &JString<'_>) -> Option<String> {
    value.try_to_string(env).ok()
}

fn answer_string<'local>(env: &mut Env<'local>, value: String) -> JObject<'local> {
    match env.new_string(value) {
        Ok(text) => JObject::from(text),
        Err(_) => JObject::null(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_vpn_VpnPlanNative_routePlan<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    mode: JString<'local>,
    ipv6_mode: JString<'local>,
    ipv6_supported: jboolean,
    clat: jboolean,
    bypass_lan: jboolean,
    excluded: JString<'local>,
    self_package: JString<'local>,
    proxy_package: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let (Some(mode), Some(ipv6_mode), Some(excluded), Some(self_package), Some(proxy_package)) = (
            read(env, &mode),
            read(env, &ipv6_mode),
            read(env, &excluded),
            read(env, &self_package),
            read(env, &proxy_package),
        ) else {
            return Ok(JObject::null());
        };
        let packages: Vec<String> = excluded.split('\n').map(str::to_owned).collect();
        match route_plan(
            &mode,
            &ipv6_mode,
            ipv6_supported,
            clat,
            bypass_lan,
            &packages,
            &self_package,
            &proxy_package,
        ) {
            Some(plan) => Ok(answer_string(env, plan.to_string())),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_vpn_VpnPlanNative_ipv6ProbeNeeded<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    ipv6_mode: JString<'local>,
) -> jboolean {
    resolve(&mut env, |env| {
        let Some(ipv6_mode) = read(env, &ipv6_mode) else {
            return Ok(false);
        };
        Ok(ipv6_probe_needed(&ipv6_mode))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_vpn_VpnPlanNative_startDefaults<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        Ok(answer_string(env, start_defaults().to_string()))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::route::route_plan;

    #[test]
    fn route_plan_is_dispatched_by_mode() {
        assert!(route_plan("express", "auto", true, false, false, &[], "a", "b").is_some());
        assert!(route_plan("server", "auto", true, false, false, &[], "a", "b").is_none());
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

    use jni::errors::{Error, LogErrorAndDefault};
    use jni::objects::{JObject, JString};
    use jni::sys::{jboolean, jbyteArray, jint, jlong};
    use jni::{Env, EnvUnowned};

    use crate::watchdog::{reclaim_allowed, reconnect_decision, should_follow, Watchdog};

    fn resolve<'local, T: Default>(
        env: &mut EnvUnowned<'local>,
        run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
    ) -> T {
        env.with_env(run).resolve::<LogErrorAndDefault>()
    }

    fn read(env: &mut Env<'_>, value: &JString<'_>) -> Option<String> {
        value.try_to_string(env).ok()
    }

    unsafe fn with_handle<R>(handle: jlong, run: impl FnOnce(&mut Watchdog) -> R) -> Option<R> {
        if handle == 0 {
            return None;
        }
        Some(run(&mut *(handle as *mut Watchdog)))
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_newHandle<'local>(
        _env: EnvUnowned<'local>,
        _this: JObject<'local>,
    ) -> jlong {
        catch_unwind(AssertUnwindSafe(|| {
            Box::into_raw(Box::new(Watchdog::new())) as jlong
        }))
        .unwrap_or(0)
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_free<'local>(
        _env: EnvUnowned<'local>,
        _this: JObject<'local>,
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
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_start<'local>(
        _env: EnvUnowned<'local>,
        _this: JObject<'local>,
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
        mut env: EnvUnowned<'local>,
        _this: JObject<'local>,
        handle: jlong,
        now_ms: jlong,
        occupied: jboolean,
    ) -> jbyteArray {
        let mut array = std::ptr::null_mut();
        resolve(&mut env, |env| {
            let step = unsafe { with_handle(handle, |watchdog| watchdog.evaluate(now_ms, occupied)) };
            let Some(step) = step else {
                return Ok(());
            };
            let mut bytes = Vec::with_capacity(9);
            bytes.push(step.event as u8);
            bytes.extend_from_slice(&step.next_delay_ms.to_be_bytes());
            if let Ok(created) = env.byte_array_from_slice(&bytes) {
                array = created.into_raw();
            }
            Ok(())
        });
        array
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_stop<'local>(
        _env: EnvUnowned<'local>,
        _this: JObject<'local>,
        handle: jlong,
    ) {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
            with_handle(handle, |watchdog| watchdog.stop());
        }));
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_shouldFollow<'local>(
        mut env: EnvUnowned<'local>,
        _this: JObject<'local>,
        enabled: jboolean,
        current_mode: JString<'local>,
        expected_mode: JString<'local>,
        has_intent: jboolean,
    ) -> jboolean {
        resolve(&mut env, |env| {
            let (Some(current_mode), Some(expected_mode)) =
                (read(env, &current_mode), read(env, &expected_mode))
            else {
                return Ok(false);
            };
            Ok(should_follow(
                enabled,
                &current_mode,
                &expected_mode,
                has_intent,
            ))
        })
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_reclaimAllowed<'local>(
        mut env: EnvUnowned<'local>,
        _this: JObject<'local>,
        enabled: jboolean,
        current_mode: JString<'local>,
        expected_mode: JString<'local>,
    ) -> jboolean {
        resolve(&mut env, |env| {
            let (Some(current_mode), Some(expected_mode)) =
                (read(env, &current_mode), read(env, &expected_mode))
            else {
                return Ok(false);
            };
            Ok(reclaim_allowed(enabled, &current_mode, &expected_mode))
        })
    }

    #[no_mangle]
    pub extern "system" fn Java_com_haoze_diting_watchdog_VpnWatchdogNative_reconnectDecision<
        'local,
    >(
        mut env: EnvUnowned<'local>,
        _this: JObject<'local>,
        enabled: jboolean,
        current_mode: JString<'local>,
        expected_mode: JString<'local>,
        consent_missing: jboolean,
        has_intent: jboolean,
    ) -> jint {
        resolve(&mut env, |env| {
            let (Some(current_mode), Some(expected_mode)) =
                (read(env, &current_mode), read(env, &expected_mode))
            else {
                return Ok(-1);
            };
            Ok(reconnect_decision(
                enabled,
                &current_mode,
                &expected_mode,
                consent_missing,
                has_intent,
            )
            .code())
        })
    }
}
