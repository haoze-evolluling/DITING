package com.haoze.diting.automation

/// 自动化平台层（A5/A7）的固定契约：权限、动作、extra 与本地偏好键集中在这里，
/// 供广播接收器、状态广播、定时控制器和通知动作共用，避免各处字符串各自为政而漂移。
object AutomationContract {
    /// 签名级控制权限：只有持有该权限的同签名应用才能向 AutomationReceiver 发送控制指令。
    const val PERMISSION_CONTROL: String = "com.haoze.diting.permission.CONTROL"

    /// 签名级事件接收权限：只有持有该权限的同签名应用才能收到状态/定时广播。
    const val PERMISSION_RECEIVE_EVENTS: String = "com.haoze.diting.permission.RECEIVE_EVENTS"

    /// 控制动作（AutomationReceiver 的 intent-filter 与通知动作共用）。
    const val ACTION_START: String = "com.haoze.diting.automation.START"
    const val ACTION_STOP: String = "com.haoze.diting.automation.STOP"
    const val ACTION_TOGGLE: String = "com.haoze.diting.automation.TOGGLE"
    const val ACTION_PAUSE: String = "com.haoze.diting.automation.PAUSE"
    const val ACTION_CANCEL_PAUSE: String = "com.haoze.diting.automation.CANCEL_PAUSE"

    /// 控制执行结果广播：仅持 RECEIVE_EVENTS 权限的应用可收。
    const val ACTION_RESULT: String = "com.haoze.diting.automation.RESULT"

    /// 状态变更事件广播：携带 EventNative 生成的冻结 JSON。
    const val ACTION_STATE_CHANGED: String = "com.haoze.diting.action.STATE_CHANGED"

    /// 定时到点广播：Alarm / WorkManager / 心跳触发后发出，供上层评估自动化规则。
    const val ACTION_SCHEDULE_TICK: String = "com.haoze.diting.action.SCHEDULE_TICK"

    /// 事件 JSON 与其 schema 版本。
    const val EXTRA_EVENT_JSON: String = "event_json"
    const val EXTRA_SCHEMA: String = "schema"
    const val SCHEMA_VERSION: String = "diting.event/1"

    /// 控制结果载荷。
    const val EXTRA_OK: String = "ok"
    const val EXTRA_MESSAGE: String = "message"
    const val EXTRA_REQUEST_ACTION: String = "request_action"

    /// 暂停时长（分钟）；缺省 60 分钟。
    const val EXTRA_PAUSE_MINUTES: String = "pause_minutes"
    const val DEFAULT_PAUSE_MINUTES: Int = 60

    /// 自动化平台层的本地偏好（不参与 Dart/legacy 设置同步）。
    const val PREFS_NAME: String = "automation_prefs"
    const val KEY_PAUSED_UNTIL_MS: String = "paused_until_ms"

    /// R4：仅白名单模式（只放行显式 allow，其余一律拦截）。
    const val KEY_ALLOWLIST_ONLY: String = "allowlist_only"
    const val KEY_NEXT_DUE_AT_MS: String = "next_due_at_ms"
    const val KEY_LAST_TICK_AT_MS: String = "last_tick_at_ms"

    /// A1 场景引擎的动作落点：各动作把结果写进这些偏好键，由服务在启动/下一次读取时生效。
    const val KEY_ACTIVE_PROFILE: String = "active_profile_id"
    const val KEY_ACTIVE_UPSTREAM: String = "active_upstream"
    const val KEY_ACTIVE_RULE_GROUP: String = "active_rule_group"
    const val KEY_BLOCKED_SERVICES: String = "blocked_services"

    /// 手动/外部触发一次自动化求值（签名权限保护）；事件类型见 EXTRA_EVENT_TYPE。
    const val ACTION_RUN_RULES: String = "com.haoze.diting.automation.RUN_RULES"
    const val EXTRA_EVENT_TYPE: String = "event_type"
}
