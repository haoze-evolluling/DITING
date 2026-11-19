//! One-line JSON control protocol shared with the Android bridge.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    #[serde(default)]
    pub id: Value,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Response {
    pub id: Value,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ControlError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ControlError {
    pub code: String,
    pub message: String,
}

impl Response {
    pub fn ok(id: Value, result: Value) -> Self {
        Self {
            id,
            ok: true,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Value, code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            id,
            ok: false,
            result: None,
            error: Some(ControlError {
                code: code.into(),
                message: message.into(),
            }),
        }
    }
}

pub fn parse_request(line: &str) -> Result<Request, ControlError> {
    serde_json::from_str::<Request>(line.trim()).map_err(|error| ControlError {
        code: "invalid_request".to_string(),
        message: error.to_string(),
    })
}

pub fn encode_response(response: &Response) -> Result<String, ControlError> {
    serde_json::to_string(response).map_err(|error| ControlError {
        code: "encode_failed".to_string(),
        message: error.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_documented_request_shape() {
        let request = parse_request(r#"{"id":1,"method":"status","params":{}}"#).unwrap();
        assert_eq!(request.id, Value::from(1));
        assert_eq!(request.method, "status");
    }

    #[test]
    fn malformed_json_is_an_invalid_request() {
        let error = parse_request("status").unwrap_err();
        assert_eq!(error.code, "invalid_request");
    }

    #[test]
    fn success_and_error_responses_round_trip() {
        let ok = encode_response(&Response::ok(Value::from(7), Value::from(true))).unwrap();
        assert_eq!(ok, r#"{"id":7,"ok":true,"result":true}"#);
        let err = encode_response(&Response::error(
            Value::from(8),
            "bad_params",
            "missing domain",
        ))
        .unwrap();
        assert!(err.contains("\"ok\":false"));
        assert!(err.contains("\"code\":\"bad_params\""));
    }
}
