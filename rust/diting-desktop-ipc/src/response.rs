use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub conflict: Option<serde_json::Value>,
}

impl<T> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            message: String::new(),
            data: Some(data),
            error: String::new(),
            conflict: None,
        }
    }

    pub fn ok_empty() -> Self {
        Self {
            success: true,
            message: String::new(),
            data: None,
            error: String::new(),
            conflict: None,
        }
    }

    pub fn message(message: impl Into<String>) -> Self {
        Self {
            success: true,
            message: message.into(),
            data: None,
            error: String::new(),
            conflict: None,
        }
    }

    pub fn ok_message(data: T, message: impl Into<String>) -> Self {
        Self {
            success: true,
            message: message.into(),
            data: Some(data),
            error: String::new(),
            conflict: None,
        }
    }

    pub fn error(error: impl Into<String>) -> Self {
        Self {
            success: false,
            message: String::new(),
            data: None,
            error: error.into(),
            conflict: None,
        }
    }

    pub fn failure_with(error: impl Into<String>, data: T) -> Self {
        Self {
            success: false,
            message: String::new(),
            data: Some(data),
            error: error.into(),
            conflict: None,
        }
    }

    pub fn conflict(error: impl Into<String>, conflict: serde_json::Value) -> Self {
        Self {
            success: false,
            message: String::new(),
            data: None,
            error: error.into(),
            conflict: Some(conflict),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn success_envelope_omits_empty_fields() {
        let payload = ApiResponse::ok("value");
        let json = serde_json::to_value(&payload).unwrap();
        assert_eq!(json["success"], true);
        assert_eq!(json["data"], "value");
        assert!(json.get("message").is_none());
        assert!(json.get("error").is_none());
    }

    #[test]
    fn error_envelope_keeps_data_and_conflict() {
        let payload = ApiResponse::<i32>::error("boom");
        let json = serde_json::to_value(&payload).unwrap();
        assert_eq!(json["success"], false);
        assert_eq!(json["error"], "boom");
        assert!(json.get("data").is_none());

        let payload = ApiResponse::<i32>::conflict("busy", serde_json::json!({"available": false}));
        let json = serde_json::to_value(&payload).unwrap();
        assert_eq!(json["conflict"]["available"], false);
    }
}
