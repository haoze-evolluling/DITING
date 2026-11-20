package com.haoze.diting.automation

object AutomationContract {
    const val PERMISSION_CONTROL: String = "com.haoze.diting.permission.CONTROL"

    const val PERMISSION_RECEIVE_EVENTS: String = "com.haoze.diting.permission.RECEIVE_EVENTS"

    const val ACTION_START: String = "com.haoze.diting.automation.START"
    const val ACTION_STOP: String = "com.haoze.diting.automation.STOP"
    const val ACTION_TOGGLE: String = "com.haoze.diting.automation.TOGGLE"
    const val ACTION_PAUSE: String = "com.haoze.diting.automation.PAUSE"
    const val ACTION_CANCEL_PAUSE: String = "com.haoze.diting.automation.CANCEL_PAUSE"

    const val ACTION_RESULT: String = "com.haoze.diting.automation.RESULT"

    const val ACTION_STATE_CHANGED: String = "com.haoze.diting.action.STATE_CHANGED"

    const val ACTION_SCHEDULE_TICK: String = "com.haoze.diting.action.SCHEDULE_TICK"

    const val EXTRA_EVENT_JSON: String = "event_json"
    const val EXTRA_SCHEMA: String = "schema"
    const val SCHEMA_VERSION: String = "diting.event/1"

    const val EXTRA_OK: String = "ok"
    const val EXTRA_MESSAGE: String = "message"
    const val EXTRA_REQUEST_ACTION: String = "request_action"

    const val EXTRA_PAUSE_MINUTES: String = "pause_minutes"
    const val DEFAULT_PAUSE_MINUTES: Int = 60

    const val PREFS_NAME: String = "automation_prefs"
    const val KEY_PAUSED_UNTIL_MS: String = "paused_until_ms"

    const val KEY_ALLOWLIST_ONLY: String = "allowlist_only"
    const val KEY_NEXT_DUE_AT_MS: String = "next_due_at_ms"
    const val KEY_LAST_TICK_AT_MS: String = "last_tick_at_ms"

    const val KEY_ACTIVE_PROFILE: String = "active_profile_id"
    const val KEY_ACTIVE_UPSTREAM: String = "active_upstream"
    const val KEY_ACTIVE_RULE_GROUP: String = "active_rule_group"
    const val KEY_BLOCKED_SERVICES: String = "blocked_services"

    const val ACTION_RUN_RULES: String = "com.haoze.diting.automation.RUN_RULES"
    const val EXTRA_EVENT_TYPE: String = "event_type"
}
