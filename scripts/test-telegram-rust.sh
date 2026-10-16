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
    use tauri::AppHandle;
    pub fn answer(_app: &AppHandle, _request_id: &str, _decision: &str) {}
    pub fn answer_question(_app: &AppHandle, _request_id: &str, _answers: &std::collections::HashMap<String, serde_json::Value>) {}
    pub fn decline(_app: &AppHandle, _request_id: &str) {}
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

    pub fn present(key: &str) -> bool {
        KNOWN_KEYS.contains(&key)
    }

    pub fn get(key: &str) -> Option<String> {
        if key == "telegram-bot-token" {
            Some("fake_bot_token".to_string())
        } else {
            None
        }
    }

    pub fn set(_key: &str, _val: &str) -> Result<(), String> {
        Ok(())
    }

    pub fn clear(_key: &str) -> Result<(), String> {
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

    println!("\nALL TELEGRAM RUST UNIT TESTS PASSED (100% OK)");
}
EOF

cd "$HARNESS_DIR"
cargo test --bin test_runner
cargo run --release
