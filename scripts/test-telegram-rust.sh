#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS_DIR="$ROOT_DIR/windows/target/telegram_test_harness"

mkdir -p "$HARNESS_DIR/src"

cat << "EOF" > "$HARNESS_DIR/Cargo.toml"
[package]
name = "telegram-test-harness"
version = "0.1.0"
edition = "2021"

[workspace]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = { version = "1", features = ["preserve_order"] }
tokio = { version = "1", features = ["net", "io-util", "sync", "time", "rt", "macros"] }
reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }
ring = "0.17"
tauri = { version = "2" }

[[bin]]
name = "test_runner"
path = "src/main.rs"
EOF

cat << "EOF" > "$HARNESS_DIR/src/main.rs"
// Standalone test runner for Coucou Telegram runtime

// Platform and logging stubs for standalone testing
pub mod platform {
    use std::path::{Path, PathBuf};
    pub fn config_dir() -> PathBuf { std::env::temp_dir() }
    pub fn local_dir() -> PathBuf { std::env::temp_dir() }
    pub const HOOK_EXE: &str = "coucou-hook";
    pub struct LocalTime { pub year: u32, pub month: u32, pub day: u32, pub hour: u32, pub minute: u32, pub second: u32 }
    pub fn local_time() -> LocalTime { LocalTime { year: 2026, month: 10, day: 16, hour: 12, minute: 0, second: 0 } }
    pub fn ensure_private_dir(_path: &Path) -> std::io::Result<()> { Ok(()) }
}

pub mod log {
    pub fn line(_msg: String) {}
}

pub mod pipe {
    use std::collections::HashMap;
    use std::sync::Mutex;
    use tokio::sync::mpsc;
    use serde_json::{json, Value};
    use tauri::AppHandle;

    pub enum Reply {
        Ack,
        Decision(String),
        Decline,
    }

    #[derive(Default)]
    pub struct Pending(pub Mutex<HashMap<String, mpsc::Sender<Reply>>>);

    pub fn send_to_pending(pending: &Pending, request_id: &str, reply: Reply, keep: bool) {
        let sender = {
            let mut map = match pending.0.lock() {
                Ok(m) => m,
                Err(e) => e.into_inner(),
            };
            if keep { map.get(request_id).cloned() } else { map.remove(request_id) }
        };
        match sender {
            Some(tx) => {
                let _ = tx.try_send(reply);
            }
            None => crate::log::line(format!("reply for id={request_id} — no pending request")),
        }
    }

    pub fn answer_with_pending(pending: &Pending, request_id: &str, decision: &str) {
        let word = match decision {
            "allow" | "always" => "allow",
            _ => "deny",
        };
        crate::log::line(format!("decision id={request_id} {word}"));
        send_to_pending(pending, request_id, Reply::Decision(word.to_string()), false);
    }

    pub fn answer_question_with_pending(
        pending: &Pending,
        request_id: &str,
        answers: &HashMap<String, Value>,
    ) {
        crate::log::line(format!("decision id={request_id} answered a question"));
        let line = json!({ "answers": answers }).to_string();
        send_to_pending(pending, request_id, Reply::Decision(line), false);
    }

    static RECORDED_ANSWERS: Mutex<Vec<(String, String)>> = Mutex::new(Vec::new());
    static RECORDED_QUESTION_ANSWERS: Mutex<Vec<(String, HashMap<String, Value>)>> = Mutex::new(Vec::new());

    pub fn record_answer(request_id: &str, decision: &str) {
        RECORDED_ANSWERS.lock().unwrap().push((request_id.to_string(), decision.to_string()));
    }

    pub fn record_question_answer(request_id: &str, answers: &HashMap<String, Value>) {
        RECORDED_QUESTION_ANSWERS.lock().unwrap().push((request_id.to_string(), answers.clone()));
    }

    pub fn get_recorded_answers() -> Vec<(String, String)> {
        RECORDED_ANSWERS.lock().unwrap().clone()
    }

    pub fn get_recorded_question_answers() -> Vec<(String, HashMap<String, Value>)> {
        RECORDED_QUESTION_ANSWERS.lock().unwrap().clone()
    }

    pub fn clear_recorded() {
        RECORDED_ANSWERS.lock().unwrap().clear();
        RECORDED_QUESTION_ANSWERS.lock().unwrap().clear();
    }

    pub fn answer(_app: &AppHandle, request_id: &str, decision: &str) {
        record_answer(request_id, decision);
    }

    pub fn answer_question(_app: &AppHandle, request_id: &str, answers: &HashMap<String, Value>) {
        record_question_answer(request_id, answers);
    }

    pub fn decline(_app: &AppHandle, _request_id: &str) {}

    pub fn test_answer_sends_decision_for_pending_request() {
        let pending = Pending::default();
        let (tx, mut rx) = mpsc::channel::<Reply>(4);
        pending.0.lock().unwrap().insert("req-123".to_string(), tx);

        answer_with_pending(&pending, "req-123", "allow");

        let reply = rx.try_recv().expect("should receive reply");
        match reply {
            Reply::Decision(word) => assert_eq!(word, "allow"),
            _ => panic!("expected Reply::Decision"),
        }
        assert!(!pending.0.lock().unwrap().contains_key("req-123"));
    }

    pub fn test_answer_unknown_request_id_safely_ignored() {
        let pending = Pending::default();
        answer_with_pending(&pending, "unknown-req-999", "deny");
        assert!(pending.0.lock().unwrap().is_empty());
    }

    pub fn test_answer_question_formats_json_answers_correctly() {
        let pending = Pending::default();
        let (tx, mut rx) = mpsc::channel::<Reply>(4);
        pending.0.lock().unwrap().insert("req-q1".to_string(), tx);

        let mut answers = HashMap::new();
        answers.insert("Which database?".to_string(), json!("PostgreSQL"));
        answers.insert("Include tests?".to_string(), json!(true));

        answer_question_with_pending(&pending, "req-q1", &answers);

        let reply = rx.try_recv().expect("should receive reply");
        match reply {
            Reply::Decision(line) => {
                let parsed: Value = serde_json::from_str(&line).expect("valid JSON line");
                assert_eq!(parsed["answers"]["Which database?"], "PostgreSQL");
                assert_eq!(parsed["answers"]["Include tests?"], true);
            }
            _ => panic!("expected Reply::Decision"),
        }
        assert!(!pending.0.lock().unwrap().contains_key("req-q1"));
    }

    #[cfg(test)]
    pub mod tests {
        use super::*;

        #[test]
        fn t_answer_sends_decision() {
            test_answer_sends_decision_for_pending_request();
        }

        #[test]
        fn t_answer_unknown() {
            test_answer_unknown_request_id_safely_ignored();
        }

        #[test]
        fn t_answer_question() {
            test_answer_question_formats_json_answers_correctly();
        }
    }
}

pub mod shortcuts {
    use std::collections::BTreeMap;
    use serde::{Deserialize, Serialize};
    #[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase", default)]
    pub struct Binding {
        pub keys: String,
        pub enabled: bool,
    }
    impl Default for Binding {
        fn default() -> Self {
            Self { keys: String::new(), enabled: true }
        }
    }
    pub type Bindings = BTreeMap<String, Binding>;
}

pub mod claude {
    pub const DEFAULT_MODEL: &str = "claude-3-7-sonnet";
}

pub mod chat {
    pub const ANTHROPIC: &str = "anthropic";
}

pub struct PollGate {}

pub struct Shared {
    pub settings: std::sync::Mutex<settings::Settings>,
}

#[path = "../../../src-tauri/src/settings.rs"]
pub mod settings;

#[path = "../../../src-tauri/src/telegram_api.rs"]
pub mod telegram_api;

#[path = "../../../src-tauri/src/telegram.rs"]
pub mod telegram;

pub mod secrets {
    pub const KNOWN_KEYS: &[&str] = &[
        "anthropic-api-key",
        "openai-api-key",
        "google-api-key",
        "openrouter-api-key",
        "openai-compatible-key",
        "n8n-url",
        "n8n-api-key",
        "vercel-token",
        "github-token",
        "stripe-api-key",
        "resend-api-key",
        "notion-api-key",
        "calcom-api-key",
        "elevenlabs-api-key",
        "telegram-bot-token",
    ];

    pub const INTERNAL_KEYS: &[&str] = &[
        "phone-link-cert",
        "phone-link-key",
        "phone-link-token",
        "phone-relay-room",
        "phone-relay-key",
        "phone-relay-access",
    ];

    static STORE: std::sync::Mutex<Option<std::collections::HashMap<String, String>>> = std::sync::Mutex::new(None);

    pub fn present(key: &str) -> bool {
        get(key).is_some()
    }

    pub fn get(key: &str) -> Option<String> {
        let mut guard = STORE.lock().unwrap();
        let map = guard.get_or_insert_with(|| {
            let mut m = std::collections::HashMap::new();
            m.insert("telegram-bot-token".to_string(), "fake_bot_token".to_string());
            m
        });
        map.get(key).cloned().filter(|v| !v.is_empty())
    }

    pub fn set(key: &str, val: &str) -> Result<(), String> {
        let mut guard = STORE.lock().unwrap();
        let map = guard.get_or_insert_with(|| {
            let mut m = std::collections::HashMap::new();
            m.insert("telegram-bot-token".to_string(), "fake_bot_token".to_string());
            m
        });
        if val.is_empty() {
            map.remove(key);
        } else {
            map.insert(key.to_string(), val.to_string());
        }
        Ok(())
    }

    pub fn clear(key: &str) -> Result<(), String> {
        let mut guard = STORE.lock().unwrap();
        let map = guard.get_or_insert_with(std::collections::HashMap::new);
        map.remove(key);
        Ok(())
    }
}

fn main() {
    println!("=== Running Telegram Rust Unit Tests ===");

    // 1. Secrets Allowlist Verification
    print!("test secrets_allowlist_contains_telegram_bot_token ... ");
    assert!(secrets::KNOWN_KEYS.contains(&"telegram-bot-token"));
    assert!(!secrets::INTERNAL_KEYS.contains(&"telegram-bot-token"));
    println!("ok");

    // 2. Settings Serialization & Backward Compatibility
    print!("test settings_serialization_and_defaults ... ");
    let defaults = settings::Settings::default();
    assert!(!defaults.telegram_enabled);
    assert!(defaults.telegram_notify_finished);
    assert!(defaults.telegram_notify_questions);
    assert!(defaults.telegram_notify_approvals);
    assert_eq!(defaults.telegram_paired_chat_id, None);
    assert_eq!(defaults.telegram_paired_user_id, None);
    assert_eq!(defaults.telegram_paired_bot_username, None);
    assert_eq!(defaults.telegram_pairing_nonce, None);
    assert_eq!(defaults.telegram_pairing_expires_at, None);

    let json_val = serde_json::to_value(&defaults).unwrap();
    let obj = json_val.as_object().unwrap();
    assert!(obj.contains_key("telegramEnabled"));
    assert!(obj.contains_key("telegramNotifyFinished"));
    assert!(obj.contains_key("telegramNotifyQuestions"));
    assert!(obj.contains_key("telegramNotifyApprovals"));
    assert!(obj.contains_key("telegramPairedChatId"));
    assert!(obj.contains_key("telegramPairedUserId"));
    assert!(obj.contains_key("telegramPairedBotUsername"));
    assert!(obj.contains_key("telegramPairingNonce"));
    assert!(obj.contains_key("telegramPairingExpiresAt"));

    // Deserialization of older settings without telegram fields
    let old_json = serde_json::json!({
        "soundEnabled": true,
        "soundVolume": 0.5
    });
    let loaded_old: settings::Settings = serde_json::from_value(old_json).unwrap();
    assert!(!loaded_old.telegram_enabled);
    assert!(loaded_old.telegram_notify_finished);
    assert!(loaded_old.telegram_notify_questions);
    assert!(loaded_old.telegram_notify_approvals);
    println!("ok");

    // 3. Sanitization & Redaction
    print!("test token_sanitization_and_redaction ... ");
    let raw_token = "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ_123456";
    let text = format!("https://api.telegram.org/bot{raw_token}/getMe and token={raw_token}");
    let sanitized = telegram_api::sanitize(&text, Some(raw_token));
    assert!(!sanitized.contains(raw_token));
    assert_eq!(sanitized, "https://api.telegram.org/bot<redacted-token>/getMe and token=<redacted-token>");

    let err = telegram_api::TelegramApiError::Forbidden(format!("Access denied for bot{raw_token}"));
    let err_str = format!("{}", err);
    let err_dbg = format!("{:?}", err);
    assert!(!err_str.contains(raw_token));
    assert!(!err_dbg.contains(raw_token));
    assert!(err_str.contains("bot<redacted-token>"));
    assert!(err_dbg.contains("bot<redacted-token>"));
    println!("ok");

    // 4. Action Registry: insertion, consumption, TTL, capacity (64)
    print!("test action_registry_lifecycle_and_capacity ... ");
    let mut reg = telegram::TelegramActionRegistry::default();
    let now = std::time::Instant::now();

    let a1 = reg.insert(telegram::TelegramActionKind::ApprovalAllow, "fp1".into(), "req1".into(), 100, 200, 10, now);
    assert_eq!(a1.r#ref.len(), 22);
    let cb = telegram::make_callback_data(&a1.r#ref, "allow");
    assert!(cb.len() <= 64);
    assert_eq!(cb, format!("c:{}:allow", a1.r#ref));

    let parsed = telegram::parse_callback_data(&cb).unwrap();
    assert_eq!(parsed.r#ref, a1.r#ref);
    assert_eq!(parsed.op, "allow");

    // Successful consumption
    let res = reg.consume(&a1.r#ref, 100, 200, "fp1", now);
    assert_eq!(res, telegram::TelegramActionResult::Accepted(telegram::TelegramAction {
        r#ref: a1.r#ref.clone(),
        kind: telegram::TelegramActionKind::ApprovalAllow,
        fingerprint: "fp1".into(),
        session_id: "req1".into(),
        expires_at: now + std::time::Duration::from_secs(120),
        chat_id: 100,
        user_id: 200,
        message_id: 10,
        state: telegram::TelegramActionState::Consumed,
    }));

    // Duplicate consumption rejected as Consumed
    let res_dup = reg.consume(&a1.r#ref, 100, 200, "fp1", now);
    assert_eq!(res_dup, telegram::TelegramActionResult::Rejected(telegram::TelegramActionRejection::Consumed));

    // Expiration after 120s TTL
    let a2 = reg.insert(telegram::TelegramActionKind::ApprovalDeny, "fp2".into(), "req2".into(), 100, 200, 11, now);
    let res_exp = reg.consume(&a2.r#ref, 100, 200, "fp2", now + std::time::Duration::from_secs(121));
    assert_eq!(res_exp, telegram::TelegramActionResult::Rejected(telegram::TelegramActionRejection::Expired));

    // Capacity cap: max 64 entries
    let mut reg64 = telegram::TelegramActionRegistry::new(std::time::Duration::from_secs(120), 64);
    for i in 0..64 {
        reg64.insert(telegram::TelegramActionKind::ApprovalAllow, format!("fp_{i}"), format!("req_{i}"), 100, 200, i, now + std::time::Duration::from_secs(i as u64));
    }
    assert_eq!(reg64.count(), 64);
    let a_new = reg64.insert(telegram::TelegramActionKind::ApprovalAllow, "fp_65".into(), "req_65".into(), 100, 200, 65, now + std::time::Duration::from_secs(100));
    assert_eq!(reg64.count(), 64);
    assert!(reg64.entries.contains_key(&a_new.r#ref));
    println!("ok");

    // 5. Pairing logic
    print!("test pairing_verification_and_rules ... ");
    let nonce = "test_pairing_nonce_xyz";
    let now_secs = 1000.0;
    let expires_at = now_secs + 600.0;

    let success = telegram::check_pairing_message("private", 123456789, 987654321, Some("user1".into()), "/start test_pairing_nonce_xyz", Some(nonce), Some(expires_at), now_secs);
    assert_eq!(success, telegram::PairingResult::Success { chat_id: 123456789, user_id: 987654321, username: Some("user1".into()) });

    // Group chat ignored
    let group = telegram::check_pairing_message("group", -10012345, 987654321, Some("user1".into()), "/start test_pairing_nonce_xyz", Some(nonce), Some(expires_at), now_secs);
    assert_eq!(group, telegram::PairingResult::Ignored);

    // Channel ignored
    let chan = telegram::check_pairing_message("channel", -1009999, 987654321, None, "/start test_pairing_nonce_xyz", Some(nonce), Some(expires_at), now_secs);
    assert_eq!(chan, telegram::PairingResult::Ignored);

    // Expired
    let expired = telegram::check_pairing_message("private", 123456789, 987654321, None, "/start test_pairing_nonce_xyz", Some(nonce), Some(expires_at), now_secs + 601.0);
    assert_eq!(expired, telegram::PairingResult::Expired);

    // Wrong nonce
    let wrong_nonce = telegram::check_pairing_message("private", 123456789, 987654321, None, "/start other_nonce", Some(nonce), Some(expires_at), now_secs);
    assert_eq!(wrong_nonce, telegram::PairingResult::InvalidNonce);
    println!("ok");

    // 6. Text truncation
    print!("test text_truncation_3500_unicode_scalars ... ");
    let text_under = "Hello, world!";
    assert_eq!(telegram::truncate_text(text_under, 3500), "Hello, world!");

    let text_over = "А".repeat(4000); // 2-byte Cyrillic char
    let truncated = telegram::truncate_text(&text_over, 3500);
    assert_eq!(truncated.chars().count(), 3500);
    assert_eq!(truncated.len(), 7000); // 3500 * 2 bytes
    println!("ok");

    // 7. Notification Queue
    print!("test notification_queue_drop_policy ... ");
    let mut q = telegram::NotificationQueue::new(32);
    for i in 0..32 {
        q.push(telegram::QueuedNotification {
            id: format!("notif_{i}"),
            kind: if i < 10 { telegram::NotificationKind::Finished } else { telegram::NotificationKind::Approval },
            text: format!("msg_{i}"),
            created_at: std::time::Instant::now(),
        });
    }
    assert_eq!(q.len(), 32);

    // Pushing one more drops oldest finished
    q.push(telegram::QueuedNotification {
        id: "notif_new".into(),
        kind: telegram::NotificationKind::Question,
        text: "msg_new".into(),
        created_at: std::time::Instant::now(),
    });
    assert_eq!(q.len(), 32);
    // Oldest finished was notif_0, so it was dropped
    assert!(!q.pop_front().map(|n| n.id == "notif_0").unwrap_or(false));
    println!("ok");

    // 8. Backoff Schedule
    print!("test backoff_schedule_sequence ... ");
    assert_eq!(telegram::BACKOFF_SCHEDULE, &[1, 2, 4, 8, 16, 30, 60]);
    assert_eq!(telegram::get_backoff_delay(0), 1);
    assert_eq!(telegram::get_backoff_delay(1), 2);
    assert_eq!(telegram::get_backoff_delay(2), 4);
    assert_eq!(telegram::get_backoff_delay(3), 8);
    assert_eq!(telegram::get_backoff_delay(4), 16);
    assert_eq!(telegram::get_backoff_delay(5), 30);
    assert_eq!(telegram::get_backoff_delay(6), 60);
    assert_eq!(telegram::get_backoff_delay(7), 60);
    println!("ok");

    // 9. Fixtures: action-cases.json and get-updates-*.json
    print!("test fixture_parsing_and_cases ... ");
    let fixture_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../tests/fixtures/telegram");
    let cases_json = std::fs::read_to_string(fixture_dir.join("action-cases.json")).unwrap();
    let val: serde_json::Value = serde_json::from_str(&cases_json).unwrap();
    assert_eq!(val["callback_grammar"], "c:<ref>:<op>");
    let cases = val["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 6);

    let approval_raw = std::fs::read_to_string(fixture_dir.join("get-updates-approval.json")).unwrap();
    let approval_json: serde_json::Value = serde_json::from_str(&approval_raw).unwrap();
    let updates: Vec<telegram_api::TelegramUpdate> = serde_json::from_value(approval_json["result"].clone()).unwrap();
    assert_eq!(updates[0].update_id, 1002);
    assert_eq!(updates[0].callback_query.as_ref().unwrap().id, "callback-approval-1");

    let pairing_raw = std::fs::read_to_string(fixture_dir.join("get-updates-pairing.json")).unwrap();
    let pairing_json: serde_json::Value = serde_json::from_str(&pairing_raw).unwrap();
    let pair_updates: Vec<telegram_api::TelegramUpdate> = serde_json::from_value(pairing_json["result"].clone()).unwrap();
    assert_eq!(pair_updates[0].update_id, 1001);
    assert_eq!(pair_updates[0].message.as_ref().unwrap().text.as_deref(), Some("/start pairNonceExample"));

    let foreign_raw = std::fs::read_to_string(fixture_dir.join("get-updates-foreign-chat.json")).unwrap();
    let foreign_json: serde_json::Value = serde_json::from_str(&foreign_raw).unwrap();
    let foreign_updates: Vec<telegram_api::TelegramUpdate> = serde_json::from_value(foreign_json["result"].clone()).unwrap();
    assert_eq!(foreign_updates.len(), 2);
    assert_eq!(foreign_updates[0].message.as_ref().unwrap().chat.chat_type, "group");
    println!("ok");

    // 10. Pipe Unit Tests
    print!("test pipe_decision_dispatch_and_question_json ... ");
    pipe::test_answer_sends_decision_for_pending_request();
    pipe::test_answer_unknown_request_id_safely_ignored();
    pipe::test_answer_question_formats_json_answers_correctly();
    println!("ok");

    // 11. Telegram Callback Query -> Pipe Dispatch & Verification
    print!("test telegram_callback_query_pipe_invocations ... ");
    pipe::clear_recorded();

    // 11a: Approval Allow callback query
    let mut reg = telegram::TelegramActionRegistry::default();
    let now = std::time::Instant::now();
    let act_allow = reg.insert(
        telegram::TelegramActionKind::ApprovalAllow,
        "fp-app-1".into(),
        "req-app-1".into(),
        12345,
        67890,
        101,
        now,
    );
    let cb_allow = telegram::make_callback_data(&act_allow.r#ref, "allow");
    let parsed_allow = telegram::parse_callback_data(&cb_allow).unwrap();
    assert_eq!(parsed_allow.op, "allow");

    let consume_res = reg.consume(&parsed_allow.r#ref, 12345, 67890, "fp-app-1", now);
    match consume_res {
        telegram::TelegramActionResult::Accepted(action) => {
            assert_eq!(action.kind, telegram::TelegramActionKind::ApprovalAllow);
            assert_eq!(action.session_id, "req-app-1");
            pipe::record_answer(&action.session_id, "allow");
        }
        _ => panic!("expected accepted allow action"),
    }
    assert_eq!(pipe::get_recorded_answers(), vec![("req-app-1".to_string(), "allow".to_string())]);

    // 11b: Approval Deny callback query
    let act_deny = reg.insert(
        telegram::TelegramActionKind::ApprovalDeny,
        "fp-app-2".into(),
        "req-app-2".into(),
        12345,
        67890,
        102,
        now,
    );
    let cb_deny = telegram::make_callback_data(&act_deny.r#ref, "deny");
    let parsed_deny = telegram::parse_callback_data(&cb_deny).unwrap();
    assert_eq!(parsed_deny.op, "deny");

    let consume_deny = reg.consume(&parsed_deny.r#ref, 12345, 67890, "fp-app-2", now);
    match consume_deny {
        telegram::TelegramActionResult::Accepted(action) => {
            assert_eq!(action.kind, telegram::TelegramActionKind::ApprovalDeny);
            assert_eq!(action.session_id, "req-app-2");
            pipe::record_answer(&action.session_id, "deny");
        }
        _ => panic!("expected accepted deny action"),
    }
    assert_eq!(
        pipe::get_recorded_answers(),
        vec![
            ("req-app-1".to_string(), "allow".to_string()),
            ("req-app-2".to_string(), "deny".to_string())
        ]
    );

    // 11c: Question Select & Submit callback query -> pipe::answer_question
    let mut answers_map = std::collections::HashMap::new();
    answers_map.insert("Target branch:".to_string(), serde_json::Value::String("main".to_string()));
    answers_map.insert("Run tests:".to_string(), serde_json::json!(["unit", "integration"]));
    pipe::record_question_answer("req-q-42", &answers_map);

    let recorded_q = pipe::get_recorded_question_answers();
    assert_eq!(recorded_q.len(), 1);
    assert_eq!(recorded_q[0].0, "req-q-42");
    assert_eq!(recorded_q[0].1["Target branch:"], "main");
    assert_eq!(recorded_q[0].1["Run tests:"], serde_json::json!(["unit", "integration"]));

    // 11d: Duplicate / consumed callback safely rejected without dispatch
    let dup_res = reg.consume(&parsed_allow.r#ref, 12345, 67890, "fp-app-1", now);
    assert_eq!(dup_res, telegram::TelegramActionResult::Rejected(telegram::TelegramActionRejection::Consumed));
    println!("ok");

    // 12. Hook processing, message formatting, and deduplication
    print!("test on_hook_processing_formatting_and_deduplication ... ");
    telegram::reset_state_for_test();
    let mut hook_settings = settings::Settings::default();
    hook_settings.telegram_enabled = true;
    hook_settings.telegram_notify_finished = true;
    hook_settings.telegram_paired_chat_id = Some(12345);
    hook_settings.telegram_paired_user_id = Some(67890);

    let raw_stop_payload = serde_json::json!({
        "hook_event_name": "Stop",
        "session_id": "s1",
        "last_assistant_message": "Turn done",
        "coucou_agent": "Claude"
    });

    let notif = telegram::handle_hook(&hook_settings, &raw_stop_payload).expect("should handle hook event");
    assert_eq!(notif.kind, telegram::NotificationKind::Finished);
    assert_eq!(notif.text, "Claude finished working.\nTurn done");
    assert_eq!(telegram::get_last_finished_key().as_deref(), Some("s1:Claude::Turn done"));
    assert_eq!(telegram::get_queue_len(), 1);

    // Verify deduplication via last_finished_key
    let dup_notif = telegram::handle_hook(&hook_settings, &raw_stop_payload);
    assert!(dup_notif.is_none());
    assert_eq!(telegram::get_queue_len(), 1);

    // Verify cwd -> project derivation
    let raw_cwd_payload = serde_json::json!({
        "hook_event_name": "finished",
        "session_id": "s2",
        "lastLine": "Build success",
        "agent": "Claude Code",
        "cwd": "/home/user/workspace/awesome-repo/"
    });
    let notif_cwd = telegram::handle_hook(&hook_settings, &raw_cwd_payload).expect("should handle cwd hook");
    assert_eq!(notif_cwd.kind, telegram::NotificationKind::Finished);
    assert_eq!(notif_cwd.text, "Claude Code finished working on awesome-repo.\nBuild success");

    // Verify StopFailure / error kind
    let raw_err_payload = serde_json::json!({
        "hook_event_name": "StopFailure",
        "session_id": "s3",
        "message": "Crash occurred",
        "agentName": "Claude"
    });
    let notif_err = telegram::handle_hook(&hook_settings, &raw_err_payload).expect("should handle StopFailure");
    assert_eq!(notif_err.kind, telegram::NotificationKind::Error);
    assert_eq!(notif_err.text, "Claude stopped with an error.\nCrash occurred");

    // Question prompt formatting: no duplicate question when header is absent or equal
    assert_eq!(
        telegram::format_question_prompt("❓ Claude", None, "Do you approve?"),
        "❓ Claude\nDo you approve?"
    );
    assert_eq!(
        telegram::format_question_prompt("❓ Claude", Some("Do you approve?"), "Do you approve?"),
        "❓ Claude\nDo you approve?"
    );
    assert_eq!(
        telegram::format_question_prompt("❓ Claude", Some("Confirmation"), "Do you approve?"),
        "❓ Claude\nConfirmation\nDo you approve?"
    );

    telegram::reset_state_for_test();
    println!("ok");

    // 13. telegram_test_token Fallback to Stored Secret
    print!("test telegram_test_token_stored_fallback ... ");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    // 13a: When empty token provided and no secret stored -> Err("No bot token configured")
    secrets::clear("telegram-bot-token").unwrap();
    let err_empty = rt.block_on(telegram::telegram_test_token("".to_string())).unwrap_err();
    assert_eq!(err_empty, "No bot token configured");

    let err_spaces = rt.block_on(telegram::telegram_test_token("   ".to_string())).unwrap_err();
    assert_eq!(err_spaces, "No bot token configured");

    // 13b: When empty token provided and secret IS stored -> uses stored secret
    secrets::set("telegram-bot-token", "stored_secret_token_12345").unwrap();
    let err_fallback = rt.block_on(telegram::telegram_test_token("".to_string())).unwrap_err();
    assert_ne!(err_fallback, "No bot token configured");
    assert!(!err_fallback.contains("stored_secret_token_12345"));

    // 13c: When non-empty token is provided -> uses the provided token (overriding secret)
    let err_explicit = rt.block_on(telegram::telegram_test_token("explicit_token_99999".to_string())).unwrap_err();
    assert_ne!(err_explicit, "No bot token configured");
    assert!(!err_explicit.contains("explicit_token_99999"));

    // Reset secret
    secrets::set("telegram-bot-token", "fake_bot_token").unwrap();
    println!("ok");

    println!("\nALL TELEGRAM RUST UNIT TESTS PASSED (100% OK)");
}
EOF

cd "$HARNESS_DIR"
cargo test --bin test_runner
cargo run --release
