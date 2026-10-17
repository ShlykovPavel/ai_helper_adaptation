// Typed Telegram Bot API client for Coucou on Windows and Linux.
// Tokens and bot credentials are NEVER included in errors, debug output, or logs.

use serde::{Deserialize, Serialize};

// ── Models ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TelegramBotIdentity {
    pub id: i64,
    pub is_bot: bool,
    pub first_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TelegramUser {
    pub id: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_bot: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TelegramChat {
    pub id: i64,
    #[serde(rename = "type")]
    pub chat_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TelegramMessage {
    pub message_id: i64,
    pub chat: TelegramChat,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<TelegramUser>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TelegramCallbackQuery {
    pub id: String,
    pub from: TelegramUser,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<TelegramMessage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TelegramUpdate {
    pub update_id: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<TelegramMessage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub callback_query: Option<TelegramCallbackQuery>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InlineKeyboardButton {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub callback_data: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InlineKeyboardMarkup {
    pub inline_keyboard: Vec<Vec<InlineKeyboardButton>>,
}

// ── Bot API Response Wrapper ────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct TelegramApiResponse<T> {
    ok: bool,
    result: Option<T>,
    error_code: Option<i64>,
    description: Option<String>,
    parameters: Option<TelegramParameters>,
}

#[derive(Debug, Deserialize)]
struct TelegramParameters {
    retry_after: Option<u64>,
}

// ── Errors & Redaction ──────────────────────────────────────────────────────

#[derive(Clone, PartialEq, Eq)]
pub enum TelegramApiError {
    Unauthorized,
    Forbidden(String),
    Conflict(String),
    RateLimited { retry_after: u64 },
    BadResponse { status: u16, description: String },
    Network(String),
    InvalidResponse(String),
}

impl std::fmt::Display for TelegramApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TelegramApiError::Unauthorized => write!(f, "TelegramApiError: unauthorized (401)"),
            TelegramApiError::Forbidden(desc) => write!(f, "TelegramApiError: forbidden (403): {}", sanitize(desc, None)),
            TelegramApiError::Conflict(desc) => write!(f, "TelegramApiError: conflict (409): {}", sanitize(desc, None)),
            TelegramApiError::RateLimited { retry_after } => {
                write!(f, "TelegramApiError: rate limited (429): retry after {retry_after}s")
            }
            TelegramApiError::BadResponse { status, description } => {
                write!(f, "TelegramApiError: bad response ({status}): {}", sanitize(description, None))
            }
            TelegramApiError::Network(desc) => write!(f, "TelegramApiError: network error: {}", sanitize(desc, None)),
            TelegramApiError::InvalidResponse(desc) => {
                write!(f, "TelegramApiError: invalid response: {}", sanitize(desc, None))
            }
        }
    }
}

impl std::fmt::Debug for TelegramApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self)
    }
}

impl std::error::Error for TelegramApiError {}

/// Redact the exact token if provided, and redact any `bot\d+:[A-Za-z0-9_-]+` pattern.
pub fn sanitize(text: &str, token: Option<&str>) -> String {
    let mut s = text.to_string();
    if let Some(tok) = token {
        if !tok.is_empty() {
            s = s.replace(tok, "<redacted-token>");
        }
    }
    redact_bot_tokens(&s)
}

fn redact_bot_tokens(text: &str) -> String {
    let mut result = String::with_capacity(text.len());
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if i + 3 <= bytes.len() && &bytes[i..i + 3] == b"bot" {
            let mut j = i + 3;
            let mut has_digits = false;
            while j < bytes.len() && bytes[j].is_ascii_digit() {
                has_digits = true;
                j += 1;
            }
            if has_digits && j < bytes.len() && bytes[j] == b':' {
                j += 1;
                let token_start = j;
                while j < bytes.len()
                    && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_' || bytes[j] == b'-')
                {
                    j += 1;
                }
                if j > token_start {
                    result.push_str("bot<redacted-token>");
                    i = j;
                    continue;
                }
            }
        }
        let ch = text[i..].chars().next().unwrap();
        result.push(ch);
        i += ch.len_utf8();
    }
    result
}

// ── HTTP Client ─────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct TelegramApi {
    token: String,
    base_url: String,
    client: reqwest::Client,
}

impl std::fmt::Debug for TelegramApi {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TelegramApi")
            .field("base_url", &self.base_url)
            .field("token", &"<redacted>")
            .finish()
    }
}

impl TelegramApi {
    pub fn new(token: &str) -> Self {
        Self::with_base_url(token, "https://api.telegram.org")
    }

    pub fn with_base_url(token: &str, base_url: &str) -> Self {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .unwrap_or_default();
        Self {
            token: token.trim().to_string(),
            base_url: base_url.trim_end_matches('/').to_string(),
            client,
        }
    }

    pub fn sanitize(&self, text: &str) -> String {
        sanitize(text, Some(&self.token))
    }

    pub async fn get_me(&self) -> Result<TelegramBotIdentity, TelegramApiError> {
        self.request("getMe", &serde_json::json!({}), std::time::Duration::from_secs(10)).await
    }

    pub async fn get_updates(
        &self,
        offset: Option<i64>,
        timeout_secs: u32,
        allowed_updates: &[&str],
    ) -> Result<Vec<TelegramUpdate>, TelegramApiError> {
        let mut body = serde_json::json!({
            "timeout": timeout_secs,
            "allowed_updates": allowed_updates,
        });
        if let Some(off) = offset {
            body["offset"] = serde_json::json!(off);
        }
        let req_timeout = std::time::Duration::from_secs((timeout_secs as u64) + 5);
        self.request("getUpdates", &body, req_timeout).await
    }

    pub async fn send_message(
        &self,
        chat_id: i64,
        text: &str,
        keyboard: Option<&InlineKeyboardMarkup>,
    ) -> Result<i64, TelegramApiError> {
        let safe_text: String = text.chars().take(3500).collect();
        let mut body = serde_json::json!({
            "chat_id": chat_id,
            "text": safe_text,
        });
        if let Some(kb) = keyboard {
            body["reply_markup"] = serde_json::to_value(kb).unwrap_or(serde_json::Value::Null);
        }
        let res: TelegramMessage = self.request("sendMessage", &body, std::time::Duration::from_secs(10)).await?;
        Ok(res.message_id)
    }

    pub async fn answer_callback_query(
        &self,
        callback_query_id: &str,
        text: Option<&str>,
        show_alert: bool,
    ) -> Result<(), TelegramApiError> {
        let mut body = serde_json::json!({
            "callback_query_id": callback_query_id,
            "show_alert": show_alert,
        });
        if let Some(t) = text {
            let safe_text: String = t.chars().take(3500).collect();
            body["text"] = serde_json::json!(safe_text);
        }
        let _: serde_json::Value = self.request("answerCallbackQuery", &body, std::time::Duration::from_secs(10)).await?;
        Ok(())
    }

    pub async fn edit_message(
        &self,
        chat_id: i64,
        message_id: i64,
        text: Option<&str>,
        keyboard: Option<&InlineKeyboardMarkup>,
    ) -> Result<(), TelegramApiError> {
        let mut body = serde_json::json!({
            "chat_id": chat_id,
            "message_id": message_id,
        });
        if let Some(kb) = keyboard {
            body["reply_markup"] = serde_json::to_value(kb).unwrap_or(serde_json::Value::Null);
        }
        let method = if let Some(t) = text {
            let safe_text: String = t.chars().take(3500).collect();
            body["text"] = serde_json::json!(safe_text);
            "editMessageText"
        } else {
            "editMessageReplyMarkup"
        };
        let _: serde_json::Value = self.request(method, &body, std::time::Duration::from_secs(10)).await?;
        Ok(())
    }

    pub async fn delete_webhook(&self, drop_pending_updates: bool) -> Result<(), TelegramApiError> {
        let body = serde_json::json!({
            "drop_pending_updates": drop_pending_updates,
        });
        let _: serde_json::Value = self.request("deleteWebhook", &body, std::time::Duration::from_secs(10)).await?;
        Ok(())
    }

    async fn request<R: for<'de> Deserialize<'de>>(
        &self,
        method: &str,
        body: &serde_json::Value,
        timeout: std::time::Duration,
    ) -> Result<R, TelegramApiError> {
        let url = format!("{}/bot{}/{}", self.base_url, self.token, method);
        let resp = self
            .client
            .post(&url)
            .json(body)
            .timeout(timeout)
            .send()
            .await
            .map_err(|e| TelegramApiError::Network(self.sanitize(&e.to_string())))?;

        let status = resp.status();
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| TelegramApiError::Network(self.sanitize(&e.to_string())))?;

        let raw_str = String::from_utf8_lossy(&bytes);

        let parsed: Result<TelegramApiResponse<R>, _> = serde_json::from_slice(&bytes);
        match parsed {
            Ok(api_resp) => {
                if api_resp.ok {
                    if let Some(result) = api_resp.result {
                        return Ok(result);
                    }
                }
                let err_code = api_resp.error_code.unwrap_or(status.as_u16() as i64);
                let desc = api_resp
                    .description
                    .unwrap_or_else(|| "Telegram API request failed".into());
                let clean_desc = self.sanitize(&desc);
                let retry_after = api_resp.parameters.and_then(|p| p.retry_after);

                match err_code {
                    401 => Err(TelegramApiError::Unauthorized),
                    403 => Err(TelegramApiError::Forbidden(clean_desc)),
                    409 => Err(TelegramApiError::Conflict(clean_desc)),
                    429 => Err(TelegramApiError::RateLimited {
                        retry_after: retry_after.unwrap_or(1),
                    }),
                    _ => Err(TelegramApiError::BadResponse {
                        status: err_code as u16,
                        description: clean_desc,
                    }),
                }
            }
            Err(_) => {
                if status.as_u16() == 401 {
                    return Err(TelegramApiError::Unauthorized);
                }
                if status.as_u16() == 429 {
                    return Err(TelegramApiError::RateLimited { retry_after: 1 });
                }
                let truncated: String = raw_str.chars().take(200).collect();
                Err(TelegramApiError::InvalidResponse(self.sanitize(&truncated)))
            }
        }
    }
}

// ── Unit Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitization_redacts_token_and_bot_pattern() {
        let token = "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ_123456";
        let raw = format!("Failed to connect to https://api.telegram.org/bot{token}/getMe with token {token}");
        let clean = sanitize(&raw, Some(token));
        assert!(!clean.contains(token));
        assert!(clean.contains("bot<redacted-token>"));
        assert!(clean.contains("<redacted-token>"));

        let generic = "Error: bot987654321:XYZ-abc_123 responded with error";
        let clean_generic = sanitize(generic, None);
        assert!(!clean_generic.contains("987654321:XYZ-abc_123"));
        assert_eq!(clean_generic, "Error: bot<redacted-token> responded with error");
    }

    #[test]
    fn test_error_display_never_leaks_token() {
        let token = "123456:token_value";
        let err = TelegramApiError::BadResponse {
            status: 400,
            description: format!("Invalid call to bot{token}"),
        };
        let disp = format!("{}", err);
        let debug = format!("{:?}", err);
        assert!(!disp.contains(token));
        assert!(!debug.contains(token));
        assert!(disp.contains("bot<redacted-token>"));
    }

    #[test]
    fn test_deserialize_updates_fixtures() {
        let approval_json = include_str!("../../../tests/fixtures/telegram/get-updates-approval.json");
        let parsed: serde_json::Value = serde_json::from_str(approval_json).unwrap();
        let result = parsed.get("result").unwrap();
        let updates: Vec<TelegramUpdate> = serde_json::from_value(result.clone()).unwrap();
        assert_eq!(updates.len(), 1);
        let u = &updates[0];
        assert_eq!(u.update_id, 1002);
        let cb = u.callback_query.as_ref().unwrap();
        assert_eq!(cb.id, "callback-approval-1");
        assert_eq!(cb.from.id, 987654321);
        assert_eq!(cb.data.as_deref(), Some("c:QmFzZTY0UmVmMDAwMDAwMQ:allow"));

        let pairing_json = include_str!("../../../tests/fixtures/telegram/get-updates-pairing.json");
        let parsed_pair: serde_json::Value = serde_json::from_str(pairing_json).unwrap();
        let updates_pair: Vec<TelegramUpdate> =
            serde_json::from_value(parsed_pair.get("result").unwrap().clone()).unwrap();
        assert_eq!(updates_pair.len(), 1);
        let msg = updates_pair[0].message.as_ref().unwrap();
        assert_eq!(msg.message_id, 7);
        assert_eq!(msg.chat.chat_type, "private");
        assert_eq!(msg.text.as_deref(), Some("/start pairNonceExample"));

        let foreign_json = include_str!("../../../tests/fixtures/telegram/get-updates-foreign-chat.json");
        let parsed_foreign: serde_json::Value = serde_json::from_str(foreign_json).unwrap();
        let updates_foreign: Vec<TelegramUpdate> =
            serde_json::from_value(parsed_foreign.get("result").unwrap().clone()).unwrap();
        assert_eq!(updates_foreign.len(), 2);
        assert_eq!(updates_foreign[0].message.as_ref().unwrap().chat.chat_type, "group");
    }

    #[test]
    fn test_inline_keyboard_serialization() {
        let kb = InlineKeyboardMarkup {
            inline_keyboard: vec![vec![
                InlineKeyboardButton {
                    text: "Allow".to_string(),
                    callback_data: Some("c:ref123:allow".to_string()),
                    url: None,
                },
                InlineKeyboardButton {
                    text: "Deny".to_string(),
                    callback_data: Some("c:ref123:deny".to_string()),
                    url: None,
                },
            ]],
        };
        let val = serde_json::to_value(&kb).unwrap();
        assert!(val.get("inline_keyboard").is_some());
        let rows = val["inline_keyboard"].as_array().unwrap();
        assert_eq!(rows.len(), 1);
        let cols = rows[0].as_array().unwrap();
        assert_eq!(cols.len(), 2);
        assert_eq!(cols[0]["text"], "Allow");
        assert_eq!(cols[0]["callback_data"], "c:ref123:allow");
        assert!(cols[0].get("url").is_none());
    }

    #[test]
    fn test_api_errors_from_action_cases_fixture() {
        let action_cases_json = include_str!("../../../tests/fixtures/telegram/action-cases.json");
        let val: serde_json::Value = serde_json::from_str(action_cases_json).unwrap();
        let errors = val["api_errors"].as_array().unwrap();

        for err_val in errors {
            let status = err_val["status"].as_u64().unwrap();
            let desc = err_val["description"].as_str().unwrap();
            if status == 409 {
                let err = TelegramApiError::Conflict(desc.to_string());
                assert_eq!(err, TelegramApiError::Conflict("Conflict: another getUpdates instance is active".into()));
            } else if status == 429 {
                let retry = err_val["parameters"]["retry_after"].as_u64().unwrap();
                let err = TelegramApiError::RateLimited { retry_after: retry };
                assert_eq!(err, TelegramApiError::RateLimited { retry_after: 3 });
            }
        }
    }
}
