// Telegram runtime service for Coucou on Windows and Linux.
// Provides action registry, pairing, polling loop, notification queue, and Tauri commands.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};

use crate::secrets;
use crate::settings;
use crate::telegram_api::{
    self, InlineKeyboardButton, InlineKeyboardMarkup, TelegramApi, TelegramApiError, TelegramUpdate,
};
use crate::Shared;

// ── Action Registry ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TelegramActionKind {
    ApprovalAllow,
    ApprovalDeny,
    QuestionSelect,
    QuestionSubmit,
    QuestionText,
    QuestionTerminal,
}

impl TelegramActionKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::ApprovalAllow => "approvalAllow",
            Self::ApprovalDeny => "approvalDeny",
            Self::QuestionSelect => "questionSelect",
            Self::QuestionSubmit => "questionSubmit",
            Self::QuestionText => "questionText",
            Self::QuestionTerminal => "questionTerminal",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "approvalAllow" | "allow" => Some(Self::ApprovalAllow),
            "approvalDeny" | "deny" => Some(Self::ApprovalDeny),
            "questionSelect" | "select" => Some(Self::QuestionSelect),
            "questionSubmit" | "submit" => Some(Self::QuestionSubmit),
            "questionText" | "text" => Some(Self::QuestionText),
            "questionTerminal" | "terminal" => Some(Self::QuestionTerminal),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TelegramActionState {
    Pending,
    Consumed,
    Expired,
    Revoked,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TelegramAction {
    pub r#ref: String,
    pub kind: TelegramActionKind,
    pub fingerprint: String,
    pub session_id: String,
    pub expires_at: Instant,
    pub chat_id: i64,
    pub user_id: i64,
    pub message_id: i64,
    pub state: TelegramActionState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TelegramActionRejection {
    Unauthorized,
    Expired,
    Consumed,
    Unknown,
    FingerprintMismatch,
    Revoked,
}

#[derive(Debug, Clone, PartialEq)]
pub enum TelegramActionResult {
    Accepted(TelegramAction),
    Rejected(TelegramActionRejection),
}

pub struct TelegramActionRegistry {
    pub entries: HashMap<String, TelegramAction>,
    pub ttl: Duration,
    pub capacity: usize,
}

impl Default for TelegramActionRegistry {
    fn default() -> Self {
        Self::new(Duration::from_secs(120), 64)
    }
}

impl TelegramActionRegistry {
    pub fn new(ttl: Duration, capacity: usize) -> Self {
        Self {
            entries: HashMap::new(),
            ttl,
            capacity,
        }
    }

    pub fn insert(
        &mut self,
        kind: TelegramActionKind,
        fingerprint: String,
        session_id: String,
        chat_id: i64,
        user_id: i64,
        message_id: i64,
        now: Instant,
    ) -> TelegramAction {
        self.prune(now);
        while self.entries.len() >= self.capacity {
            if let Some(oldest_ref) = self
                .entries
                .iter()
                .min_by_key(|(_, a)| a.expires_at)
                .map(|(r, _)| r.clone())
            {
                self.entries.remove(&oldest_ref);
            } else {
                break;
            }
        }

        let r#ref = generate_base64url_16();
        let action = TelegramAction {
            r#ref: r#ref.clone(),
            kind,
            fingerprint,
            session_id,
            expires_at: now + self.ttl,
            chat_id,
            user_id,
            message_id,
            state: TelegramActionState::Pending,
        };
        self.entries.insert(r#ref, action.clone());
        action
    }

    pub fn consume(
        &mut self,
        r#ref: &str,
        chat_id: i64,
        user_id: i64,
        fingerprint: &str,
        now: Instant,
    ) -> TelegramActionResult {
        let entry = match self.entries.get_mut(r#ref) {
            Some(e) => e,
            None => return TelegramActionResult::Rejected(TelegramActionRejection::Unknown),
        };

        if now >= entry.expires_at {
            entry.state = TelegramActionState::Expired;
            return TelegramActionResult::Rejected(TelegramActionRejection::Expired);
        }

        if entry.chat_id != chat_id || entry.user_id != user_id {
            return TelegramActionResult::Rejected(TelegramActionRejection::Unauthorized);
        }

        match entry.state {
            TelegramActionState::Consumed => {
                return TelegramActionResult::Rejected(TelegramActionRejection::Consumed)
            }
            TelegramActionState::Expired => {
                return TelegramActionResult::Rejected(TelegramActionRejection::Expired)
            }
            TelegramActionState::Revoked => {
                return TelegramActionResult::Rejected(TelegramActionRejection::Revoked)
            }
            TelegramActionState::Pending => {}
        }

        if !fingerprint.is_empty() && entry.fingerprint != fingerprint {
            return TelegramActionResult::Rejected(TelegramActionRejection::FingerprintMismatch);
        }

        entry.state = TelegramActionState::Consumed;
        TelegramActionResult::Accepted(entry.clone())
    }

    pub fn revoke_all(&mut self) {
        for entry in self.entries.values_mut() {
            if entry.state == TelegramActionState::Pending {
                entry.state = TelegramActionState::Revoked;
            }
        }
    }

    pub fn prune(&mut self, now: Instant) {
        self.entries.retain(|_, action| action.expires_at > now);
    }

    pub fn count(&self) -> usize {
        self.entries.len()
    }
}

// ── Callback Grammar: c:<ref>:<op> (<= 64 bytes) ────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedCallback {
    pub r#ref: String,
    pub op: String,
}

pub fn parse_callback_data(data: &str) -> Option<ParsedCallback> {
    if data.len() > 64 {
        return None;
    }
    let parts: Vec<&str> = data.splitn(3, ':').collect();
    if parts.len() == 3 && parts[0] == "c" {
        Some(ParsedCallback {
            r#ref: parts[1].to_string(),
            op: parts[2].to_string(),
        })
    } else {
        None
    }
}

pub fn make_callback_data(r#ref: &str, op: &str) -> String {
    let s = format!("c:{}:{}", r#ref, op);
    debug_assert!(s.len() <= 64, "callback_data exceeds 64 bytes: {}", s);
    s
}

// ── Base64URL and Nonce Helpers ─────────────────────────────────────────────

pub fn base64url_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::new();
    let mut i = 0;
    while i < data.len() {
        let b0 = data[i];
        let b1 = if i + 1 < data.len() { data[i + 1] } else { 0 };
        let b2 = if i + 2 < data.len() { data[i + 2] } else { 0 };

        out.push(ALPHABET[(b0 >> 2) as usize] as char);
        out.push(ALPHABET[(((b0 & 3) << 4) | (b1 >> 4)) as usize] as char);
        if i + 1 < data.len() {
            out.push(ALPHABET[(((b1 & 0x0f) << 2) | (b2 >> 6)) as usize] as char);
        }
        if i + 2 < data.len() {
            out.push(ALPHABET[(b2 & 0x3f) as usize] as char);
        }
        i += 3;
    }
    out
}

pub fn generate_base64url_16() -> String {
    let mut bytes = [0u8; 16];
    let rng = ring::rand::SystemRandom::new();
    if ring::rand::SecureRandom::fill(&rng, &mut bytes).is_err() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        for (i, b) in bytes.iter_mut().enumerate() {
            *b = (nanos >> (i * 8)) as u8 ^ ((i as u8).wrapping_mul(37));
        }
    }
    base64url_encode(&bytes)
}

// ── Pairing Logic ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingResult {
    Success {
        chat_id: i64,
        user_id: i64,
        username: Option<String>,
    },
    Ignored,
    Expired,
    InvalidNonce,
}

pub fn check_pairing_message(
    chat_type: &str,
    chat_id: i64,
    user_id: i64,
    username: Option<String>,
    text: &str,
    expected_nonce: Option<&str>,
    expires_at: Option<f64>,
    now_secs: f64,
) -> PairingResult {
    if chat_type != "private" {
        return PairingResult::Ignored;
    }

    let trimmed = text.trim();
    if !trimmed.starts_with("/start") {
        return PairingResult::Ignored;
    }

    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    if parts.len() != 2 || parts[0] != "/start" {
        return PairingResult::Ignored;
    }

    let nonce = parts[1];
    let Some(expected) = expected_nonce else {
        return PairingResult::Ignored;
    };

    if nonce != expected {
        return PairingResult::InvalidNonce;
    }

    if let Some(exp) = expires_at {
        if now_secs > exp {
            return PairingResult::Expired;
        }
    }

    PairingResult::Success {
        chat_id,
        user_id,
        username,
    }
}

// ── Truncation Logic ────────────────────────────────────────────────────────

pub fn truncate_text(text: &str, limit: usize) -> String {
    text.chars().take(limit).collect()
}

// ── Backoff Schedule ────────────────────────────────────────────────────────

pub const BACKOFF_SCHEDULE: &[u64] = &[1, 2, 4, 8, 16, 30, 60];

pub fn get_backoff_delay(consecutive_failures: usize) -> u64 {
    let idx = consecutive_failures.min(BACKOFF_SCHEDULE.len() - 1);
    BACKOFF_SCHEDULE[idx]
}

// ── Notification Queue ──────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotificationKind {
    Finished,
    Question,
    Approval,
    Error,
}

#[derive(Debug, Clone)]
pub struct QueuedNotification {
    pub id: String,
    pub kind: NotificationKind,
    pub text: String,
    pub created_at: Instant,
}

pub struct NotificationQueue {
    items: Vec<QueuedNotification>,
    capacity: usize,
}

impl Default for NotificationQueue {
    fn default() -> Self {
        Self::new(32)
    }
}

impl NotificationQueue {
    pub fn new(capacity: usize) -> Self {
        Self {
            items: Vec::new(),
            capacity,
        }
    }

    pub fn push(&mut self, notification: QueuedNotification) -> bool {
        if self.items.len() >= self.capacity {
            if let Some(pos) = self
                .items
                .iter()
                .position(|n| n.kind == NotificationKind::Finished)
            {
                self.items.remove(pos);
            } else if notification.kind == NotificationKind::Finished {
                return false;
            } else if let Some(pos) = self
                .items
                .iter()
                .position(|n| n.kind == NotificationKind::Error)
            {
                self.items.remove(pos);
            }
        }
        self.items.push(notification);
        true
    }

    pub fn pop_front(&mut self) -> Option<QueuedNotification> {
        if self.items.is_empty() {
            None
        } else {
            Some(self.items.remove(0))
        }
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

// ── Service State ───────────────────────────────────────────────────────────

struct TelegramInner {
    status: String,
    registry: TelegramActionRegistry,
    abort_handle: Option<tauri::async_runtime::JoinHandle<()>>,
    queue: NotificationQueue,
    last_finished_key: Option<String>,
}

fn get_state() -> MutexGuard<'static, TelegramInner> {
    static STATE: std::sync::OnceLock<Mutex<TelegramInner>> = std::sync::OnceLock::new();
    STATE
        .get_or_init(|| {
            Mutex::new(TelegramInner {
                status: "idle".to_string(),
                registry: TelegramActionRegistry::default(),
                abort_handle: None,
                queue: NotificationQueue::default(),
                last_finished_key: None,
            })
        })
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
}

// ── Public Service Interface ────────────────────────────────────────────────

pub struct TelegramService;

impl TelegramService {
    pub fn start(app: AppHandle) {
        start(app);
    }

    pub fn stop(app: &AppHandle) {
        stop(app);
    }

    pub fn on_hook(app: &AppHandle, payload: serde_json::Value) {
        on_hook(app, payload);
    }

    pub fn on_pending_approval(app: &AppHandle, payload: &serde_json::Value) {
        on_pending_approval(app, payload);
    }

    pub async fn handle_update(app: &AppHandle, update: TelegramUpdate) {
        handle_update(app, update).await;
    }
}

pub fn start(app: AppHandle) {
    let (enabled, has_token, token) = {
        let shared = app.state::<Shared>();
        let settings = shared.settings.lock().unwrap().clone();
        let token = secrets::get("telegram-bot-token");
        (
            settings.telegram_enabled,
            token.is_some(),
            token.unwrap_or_default(),
        )
    };

    if !enabled || !has_token || token.is_empty() {
        let mut st = get_state();
        st.status = "stopped".to_string();
        return;
    }

    stop(&app);

    let api = TelegramApi::new(&token);
    let app_clone = app.clone();

    let task = tauri::async_runtime::spawn(async move {
        run_polling_loop(app_clone, api).await;
    });

    let mut st = get_state();
    st.status = "polling".to_string();
    st.abort_handle = Some(task);
}

pub fn stop(_app: &AppHandle) {
    let mut st = get_state();
    if let Some(handle) = st.abort_handle.take() {
        handle.abort();
    }
    st.status = "stopped".to_string();
    st.registry.revoke_all();
}

async fn run_polling_loop(app: AppHandle, api: TelegramApi) {
    let mut webhook_deleted = false;
    let mut consecutive_failures = 0;

    while !webhook_deleted {
        match api.delete_webhook(false).await {
            Ok(()) => {
                webhook_deleted = true;
                consecutive_failures = 0;
            }
            Err(TelegramApiError::Unauthorized) => {
                get_state().status = "unauthorized".to_string();
                return;
            }
            Err(TelegramApiError::Conflict(_)) => {
                get_state().status = "conflict".to_string();
                let delay = get_backoff_delay(consecutive_failures);
                consecutive_failures += 1;
                tokio::time::sleep(Duration::from_secs(delay)).await;
            }
            Err(TelegramApiError::RateLimited { retry_after }) => {
                get_state().status = "backoff".to_string();
                tokio::time::sleep(Duration::from_secs(retry_after)).await;
            }
            Err(_) => {
                get_state().status = "backoff".to_string();
                let delay = get_backoff_delay(consecutive_failures);
                consecutive_failures += 1;
                tokio::time::sleep(Duration::from_secs(delay)).await;
            }
        }
    }

    let mut offset: Option<i64> = None;
    consecutive_failures = 0;

    loop {
        get_state().status = "polling".to_string();

        match api.get_updates(offset, 25, &["message", "callback_query"]).await {
            Ok(updates) => {
                consecutive_failures = 0;
                get_state().status = "polling".to_string();

                for update in updates {
                    let update_id = update.update_id;
                    handle_update_internal(&app, &api, update).await;
                    offset = Some(offset.map_or(update_id + 1, |cur| cur.max(update_id + 1)));
                }
            }
            Err(TelegramApiError::Unauthorized) => {
                get_state().status = "unauthorized".to_string();
                break;
            }
            Err(TelegramApiError::Conflict(_)) => {
                get_state().status = "conflict".to_string();
                let delay = get_backoff_delay(consecutive_failures);
                consecutive_failures += 1;
                tokio::time::sleep(Duration::from_secs(delay)).await;
            }
            Err(TelegramApiError::RateLimited { retry_after }) => {
                get_state().status = "backoff".to_string();
                tokio::time::sleep(Duration::from_secs(retry_after)).await;
            }
            Err(_) => {
                get_state().status = "backoff".to_string();
                let delay = get_backoff_delay(consecutive_failures);
                consecutive_failures += 1;
                tokio::time::sleep(Duration::from_secs(delay)).await;
            }
        }
    }
}

pub async fn handle_update(app: &AppHandle, update: TelegramUpdate) {
    let token = secrets::get("telegram-bot-token").unwrap_or_default();
    let api = TelegramApi::new(&token);
    handle_update_internal(app, &api, update).await;
}

async fn handle_update_internal(app: &AppHandle, api: &TelegramApi, update: TelegramUpdate) {
    let shared = app.state::<Shared>();
    let settings = shared.settings.lock().unwrap().clone();

    if let Some(msg) = update.message {
        if let Some(text) = msg.text {
            let user_id = msg.from.as_ref().map(|u| u.id).unwrap_or(0);
            let username = msg.from.as_ref().and_then(|u| u.username.clone());
            let now_secs = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs_f64();

            let res = check_pairing_message(
                &msg.chat.chat_type,
                msg.chat.id,
                user_id,
                username,
                &text,
                settings.telegram_pairing_nonce.as_deref(),
                settings.telegram_pairing_expires_at,
                now_secs,
            );

            match res {
                PairingResult::Success {
                    chat_id,
                    user_id,
                    username: _,
                } => {
                    {
                        let mut current = shared.settings.lock().unwrap();
                        current.telegram_paired_chat_id = Some(chat_id);
                        current.telegram_paired_user_id = Some(user_id);
                        current.telegram_pairing_nonce = None;
                        current.telegram_pairing_expires_at = None;
                        if let Err(e) = settings::save(&current) {
                            crate::log::line(format!("telegram: could not save settings: {e}"));
                        }
                        let _ = app.emit("settings-changed", current.clone());
                    }
                    let _ = api
                        .send_message(chat_id, "Telegram connected to Coucou!", None)
                        .await;
                }
                PairingResult::Expired => {
                    let _ = api
                        .send_message(
                            msg.chat.id,
                            "Pairing link has expired. Please generate a new link in Coucou Settings.",
                            None,
                        )
                        .await;
                }
                PairingResult::InvalidNonce => {}
                PairingResult::Ignored => {}
            }
        }
        return;
    }

    if let Some(cb) = update.callback_query {
        let chat = cb.message.as_ref().map(|m| &m.chat);
        let chat_id = chat.map(|c| c.id).unwrap_or(0);
        let chat_type = chat.map(|c| c.chat_type.as_str()).unwrap_or("");
        let user_id = cb.from.id;

        let paired_chat_id = settings.telegram_paired_chat_id.unwrap_or(0);
        let paired_user_id = settings.telegram_paired_user_id.unwrap_or(0);

        if chat_type != "private" || chat_id != paired_chat_id || user_id != paired_user_id {
            return;
        }

        let data = match cb.data.as_deref() {
            Some(d) => d,
            None => {
                let _ = api
                    .answer_callback_query(&cb.id, Some("Invalid callback"), true)
                    .await;
                return;
            }
        };

        let parsed = match parse_callback_data(data) {
            Some(p) => p,
            None => {
                let _ = api
                    .answer_callback_query(&cb.id, Some("Invalid callback format"), true)
                    .await;
                return;
            }
        };

        let now = Instant::now();
        let consume_result = {
            let mut st = get_state();
            st.registry.consume(&parsed.r#ref, chat_id, user_id, "", now)
        };

        match consume_result {
            TelegramActionResult::Accepted(action) => {
                let _ = api
                    .answer_callback_query(&cb.id, Some("Choice recorded"), false)
                    .await;
                let decision_text = match action.kind {
                    TelegramActionKind::ApprovalAllow => "Answered: Allow",
                    TelegramActionKind::ApprovalDeny => "Answered: Deny",
                    TelegramActionKind::QuestionSelect => "Answered: Option selected",
                    TelegramActionKind::QuestionSubmit => "Answered: Submitted",
                    TelegramActionKind::QuestionText => "Answered: Text response",
                    TelegramActionKind::QuestionTerminal => "Answered: Terminal choice",
                };
                if action.message_id > 0 {
                    let _ = api
                        .edit_message(chat_id, action.message_id, Some(decision_text), None)
                        .await;
                }

                match action.kind {
                    TelegramActionKind::ApprovalAllow => {
                        crate::pipe::answer(app, &action.session_id, "allow");
                    }
                    TelegramActionKind::ApprovalDeny => {
                        crate::pipe::answer(app, &action.session_id, "deny");
                    }
                    _ => {}
                }
            }
            TelegramActionResult::Rejected(TelegramActionRejection::Consumed)
            | TelegramActionResult::Rejected(TelegramActionRejection::Expired)
            | TelegramActionResult::Rejected(TelegramActionRejection::Revoked) => {
                let _ = api
                    .answer_callback_query(
                        &cb.id,
                        Some("This action has expired or was already consumed."),
                        true,
                    )
                    .await;
            }
            TelegramActionResult::Rejected(_) => {
                let _ = api
                    .answer_callback_query(&cb.id, Some("Action rejected."), true)
                    .await;
            }
        }
    }
}

pub fn on_pending_approval(app: &AppHandle, payload: &serde_json::Value) {
    let shared = app.state::<Shared>();
    let settings = shared.settings.lock().unwrap().clone();

    if !settings.telegram_enabled || !settings.telegram_notify_approvals {
        return;
    }
    let (chat_id, user_id) = match (
        settings.telegram_paired_chat_id,
        settings.telegram_paired_user_id,
    ) {
        (Some(c), Some(u)) => (c, u),
        _ => return,
    };
    let token = match secrets::get("telegram-bot-token") {
        Some(t) if !t.is_empty() => t,
        _ => return,
    };

    let request_id = payload
        .get("id")
        .or_else(|| payload.get("requestId"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let tool = payload.get("tool").and_then(|v| v.as_str()).unwrap_or("tool");
    let command = payload
        .get("command")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let fingerprint = payload
        .get("fingerprint")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let message_text = if command.is_empty() {
        format!("Permission Request: {}\nAction requested by agent.", tool)
    } else {
        format!("Permission Request: {}\nCommand: {}", tool, command)
    };
    let safe_text = truncate_text(&message_text, 3500);

    let now = Instant::now();
    let (allow_action, deny_action) = {
        let mut st = get_state();
        let allow = st.registry.insert(
            TelegramActionKind::ApprovalAllow,
            fingerprint.clone(),
            request_id.clone(),
            chat_id,
            user_id,
            0,
            now,
        );
        let deny = st.registry.insert(
            TelegramActionKind::ApprovalDeny,
            fingerprint,
            request_id,
            chat_id,
            user_id,
            0,
            now,
        );
        st.queue.push(QueuedNotification {
            id: format!(
                "notif-{}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos()
            ),
            kind: NotificationKind::Approval,
            text: safe_text.clone(),
            created_at: now,
        });
        (allow, deny)
    };

    let keyboard = InlineKeyboardMarkup {
        inline_keyboard: vec![vec![
            InlineKeyboardButton {
                text: "Allow".to_string(),
                callback_data: Some(make_callback_data(&allow_action.r#ref, "allow")),
                url: None,
            },
            InlineKeyboardButton {
                text: "Deny".to_string(),
                callback_data: Some(make_callback_data(&deny_action.r#ref, "deny")),
                url: None,
            },
        ]],
    };

    let allow_ref = allow_action.r#ref.clone();
    let deny_ref = deny_action.r#ref.clone();

    tauri::async_runtime::spawn(async move {
        let api = TelegramApi::new(&token);
        match api.send_message(chat_id, &safe_text, Some(&keyboard)).await {
            Ok(msg_id) => {
                let mut st = get_state();
                if let Some(a) = st.registry.entries.get_mut(&allow_ref) {
                    a.message_id = msg_id;
                }
                if let Some(d) = st.registry.entries.get_mut(&deny_ref) {
                    d.message_id = msg_id;
                }
            }
            Err(e) => {
                crate::log::line(format!("telegram: failed to send approval request: {e}"));
            }
        }
    });
}

pub fn on_hook(app: &AppHandle, payload: serde_json::Value) {
    let shared = app.state::<Shared>();
    let settings = shared.settings.lock().unwrap().clone();

    if !settings.telegram_enabled {
        return;
    }
    let chat_id = match settings.telegram_paired_chat_id {
        Some(c) => c,
        None => return,
    };
    let token = match secrets::get("telegram-bot-token") {
        Some(t) if !t.is_empty() => t,
        _ => return,
    };

    let kind = payload
        .get("type")
        .or_else(|| payload.get("kind"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if kind == "stop" || kind == "finished" {
        if !settings.telegram_notify_finished {
            return;
        }
        let agent = payload
            .get("agent")
            .or_else(|| payload.get("agentName"))
            .and_then(|v| v.as_str())
            .unwrap_or("Agent");
        let project = payload
            .get("project")
            .or_else(|| payload.get("projectName"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let last_line = payload
            .get("lastLine")
            .or_else(|| payload.get("finalText"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let key = format!("{agent}:{project}:{last_line}");
        {
            let mut st = get_state();
            if st.last_finished_key.as_deref() == Some(&key) {
                return;
            }
            st.last_finished_key = Some(key);
        }

        let text = if project.is_empty() {
            format!("{agent} finished working.\n{last_line}")
        } else {
            format!("{agent} finished working on {project}.\n{last_line}")
        };
        let safe_text = truncate_text(&text, 3500);

        let can_send = {
            let mut st = get_state();
            st.queue.push(QueuedNotification {
                id: format!(
                    "notif-{}",
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_nanos()
                ),
                kind: NotificationKind::Finished,
                text: safe_text.clone(),
                created_at: Instant::now(),
            })
        };

        if can_send {
            tauri::async_runtime::spawn(async move {
                let api = TelegramApi::new(&token);
                let _ = api.send_message(chat_id, &safe_text, None).await;
            });
        }
    }
}

// ── Tauri Commands ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TelegramStatusResponse {
    pub enabled: bool,
    pub token_present: bool,
    pub status: String,
    pub paired_chat_id: Option<i64>,
    pub paired_bot_username: Option<String>,
}

#[tauri::command]
pub fn telegram_status(shared: State<'_, Shared>) -> TelegramStatusResponse {
    let settings = shared.settings.lock().unwrap().clone();
    let token_present = secrets::present("telegram-bot-token");
    let status = get_state().status.clone();

    TelegramStatusResponse {
        enabled: settings.telegram_enabled,
        token_present,
        status,
        paired_chat_id: settings.telegram_paired_chat_id,
        paired_bot_username: settings.telegram_paired_bot_username,
    }
}

#[tauri::command]
pub async fn telegram_test_token(token: String) -> Result<String, String> {
    let api = TelegramApi::new(&token);
    match api.get_me().await {
        Ok(me) => {
            let name = me.username.unwrap_or(me.first_name);
            Ok(name)
        }
        Err(e) => Err(telegram_api::sanitize(&e.to_string(), Some(&token))),
    }
}

#[tauri::command]
pub fn telegram_set_enabled(
    app: AppHandle,
    shared: State<'_, Shared>,
    enabled: bool,
) -> Result<(), String> {
    {
        let mut current = shared.settings.lock().unwrap();
        current.telegram_enabled = enabled;
        if let Err(e) = settings::save(&current) {
            crate::log::line(format!("telegram: could not save settings: {e}"));
        }
        let _ = app.emit("settings-changed", current.clone());
    }

    if enabled {
        start(app);
    } else {
        stop(&app);
    }
    Ok(())
}

#[tauri::command]
pub async fn telegram_new_pairing(
    app: AppHandle,
    shared: State<'_, Shared>,
) -> Result<String, String> {
    let token = secrets::get("telegram-bot-token")
        .ok_or_else(|| "No telegram bot token configured".to_string())?;

    let mut bot_username = shared
        .settings
        .lock()
        .unwrap()
        .telegram_paired_bot_username
        .clone();

    if bot_username.is_none() {
        let api = TelegramApi::new(&token);
        let me = api.get_me().await.map_err(|e| e.to_string())?;
        bot_username = me.username;
    }

    let username = bot_username.ok_or_else(|| "Bot has no username".to_string())?;

    let nonce = generate_base64url_16();
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64();
    let expires_at = now_secs + 600.0;

    {
        let mut current = shared.settings.lock().unwrap();
        current.telegram_pairing_nonce = Some(nonce.clone());
        current.telegram_pairing_expires_at = Some(expires_at);
        current.telegram_paired_chat_id = None;
        current.telegram_paired_user_id = None;
        current.telegram_paired_bot_username = Some(username.clone());
        if let Err(e) = settings::save(&current) {
            crate::log::line(format!("telegram: could not save settings: {e}"));
        }
        let _ = app.emit("settings-changed", current.clone());
    }

    Ok(format!("https://t.me/{}?start={}", username, nonce))
}

#[tauri::command]
pub fn telegram_disconnect(app: AppHandle, shared: State<'_, Shared>) -> Result<(), String> {
    let _ = secrets::clear("telegram-bot-token");

    {
        let mut current = shared.settings.lock().unwrap();
        current.telegram_enabled = false;
        current.telegram_paired_chat_id = None;
        current.telegram_paired_user_id = None;
        current.telegram_paired_bot_username = None;
        current.telegram_pairing_nonce = None;
        current.telegram_pairing_expires_at = None;
        if let Err(e) = settings::save(&current) {
            crate::log::line(format!("telegram: could not save settings: {e}"));
        }
        let _ = app.emit("settings-changed", current.clone());
    }

    stop(&app);
    Ok(())
}

// ── Unit Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_action_registry_insert_and_consume() {
        let mut registry = TelegramActionRegistry::default();
        let now = Instant::now();

        let action = registry.insert(
            TelegramActionKind::ApprovalAllow,
            "fp_abc".to_string(),
            "req_123".to_string(),
            123456789,
            987654321,
            41,
            now,
        );

        assert_eq!(action.kind, TelegramActionKind::ApprovalAllow);
        assert_eq!(action.state, TelegramActionState::Pending);
        assert_eq!(action.r#ref.len(), 22);
        assert_eq!(action.expires_at, now + Duration::from_secs(120));

        let callback = make_callback_data(&action.r#ref, "allow");
        assert!(callback.len() <= 64, "length was {}", callback.len());
        let parsed = parse_callback_data(&callback).unwrap();
        assert_eq!(parsed.r#ref, action.r#ref);
        assert_eq!(parsed.op, "allow");

        // Wrong chat
        let res_wrong_chat = registry.consume(&action.r#ref, 999, 987654321, "fp_abc", now);
        assert_eq!(
            res_wrong_chat,
            TelegramActionResult::Rejected(TelegramActionRejection::Unauthorized)
        );

        // Wrong user
        let res_wrong_user = registry.consume(&action.r#ref, 123456789, 111, "fp_abc", now);
        assert_eq!(
            res_wrong_user,
            TelegramActionResult::Rejected(TelegramActionRejection::Unauthorized)
        );

        // Fingerprint mismatch
        let res_bad_fp = registry.consume(&action.r#ref, 123456789, 987654321, "wrong_fp", now);
        assert_eq!(
            res_bad_fp,
            TelegramActionResult::Rejected(TelegramActionRejection::FingerprintMismatch)
        );

        // Valid consumption
        let res_ok = registry.consume(&action.r#ref, 123456789, 987654321, "fp_abc", now);
        match res_ok {
            TelegramActionResult::Accepted(a) => {
                assert_eq!(a.r#ref, action.r#ref);
                assert_eq!(a.state, TelegramActionState::Consumed);
            }
            other => panic!("Expected Accepted, got {:?}", other),
        }

        // Duplicate consumption
        let res_dup = registry.consume(&action.r#ref, 123456789, 987654321, "fp_abc", now);
        assert_eq!(
            res_dup,
            TelegramActionResult::Rejected(TelegramActionRejection::Consumed)
        );
    }

    #[test]
    fn test_action_registry_expiration() {
        let mut registry = TelegramActionRegistry::default();
        let now = Instant::now();

        let action = registry.insert(
            TelegramActionKind::ApprovalDeny,
            "fp_xyz".to_string(),
            "req_456".to_string(),
            100,
            200,
            1,
            now,
        );

        let later = now + Duration::from_secs(121);
        let res = registry.consume(&action.r#ref, 100, 200, "fp_xyz", later);
        assert_eq!(
            res,
            TelegramActionResult::Rejected(TelegramActionRejection::Expired)
        );
    }

    #[test]
    fn test_action_registry_capacity_eviction() {
        let mut registry = TelegramActionRegistry::new(Duration::from_secs(120), 64);
        let now = Instant::now();

        for i in 0..64 {
            registry.insert(
                TelegramActionKind::ApprovalAllow,
                format!("fp_{i}"),
                format!("req_{i}"),
                100,
                200,
                i,
                now + Duration::from_secs(i as u64),
            );
        }
        assert_eq!(registry.count(), 64);

        // Inserting 65th should evict the oldest
        let action65 = registry.insert(
            TelegramActionKind::ApprovalDeny,
            "fp_new".to_string(),
            "req_new".to_string(),
            100,
            200,
            65,
            now + Duration::from_secs(100),
        );
        assert_eq!(registry.count(), 64);
        assert!(registry.entries.contains_key(&action65.r#ref));
    }

    #[test]
    fn test_pairing_acceptance_and_rejection() {
        let nonce = "valid_pairing_nonce_123";
        let now = 1000.0;
        let expires_at = now + 600.0;

        // Valid
        let res_valid = check_pairing_message(
            "private",
            123456789,
            987654321,
            Some("myuser".to_string()),
            "/start valid_pairing_nonce_123",
            Some(nonce),
            Some(expires_at),
            now,
        );
        assert_eq!(
            res_valid,
            PairingResult::Success {
                chat_id: 123456789,
                user_id: 987654321,
                username: Some("myuser".to_string()),
            }
        );

        // Group chat - ignored
        let res_group = check_pairing_message(
            "group",
            -100222333,
            987654321,
            Some("myuser".to_string()),
            "/start valid_pairing_nonce_123",
            Some(nonce),
            Some(expires_at),
            now,
        );
        assert_eq!(res_group, PairingResult::Ignored);

        // Channel - ignored
        let res_chan = check_pairing_message(
            "channel",
            -100555,
            987654321,
            None,
            "/start valid_pairing_nonce_123",
            Some(nonce),
            Some(expires_at),
            now,
        );
        assert_eq!(res_chan, PairingResult::Ignored);

        // Expired nonce
        let res_expired = check_pairing_message(
            "private",
            123456789,
            987654321,
            None,
            "/start valid_pairing_nonce_123",
            Some(nonce),
            Some(expires_at),
            now + 601.0,
        );
        assert_eq!(res_expired, PairingResult::Expired);

        // Wrong nonce
        let res_wrong = check_pairing_message(
            "private",
            123456789,
            987654321,
            None,
            "/start bad_nonce",
            Some(nonce),
            Some(expires_at),
            now,
        );
        assert_eq!(res_wrong, PairingResult::InvalidNonce);
    }

    #[test]
    fn test_text_truncation_unicode_scalars() {
        let short = "Hello world";
        assert_eq!(truncate_text(short, 3500), "Hello world");

        let long = "a".repeat(4000);
        let truncated = truncate_text(&long, 3500);
        assert_eq!(truncated.len(), 3500);

        // Multi-byte Unicode (Cyrillic + emoji)
        let multi = "Привет 🦀 ".repeat(500); // 9 chars per repeat
        let char_count = multi.chars().count();
        assert!(char_count > 3500);
        let trunc_multi = truncate_text(&multi, 3500);
        assert_eq!(trunc_multi.chars().count(), 3500);
    }

    #[test]
    fn test_backoff_schedule() {
        assert_eq!(get_backoff_delay(0), 1);
        assert_eq!(get_backoff_delay(1), 2);
        assert_eq!(get_backoff_delay(2), 4);
        assert_eq!(get_backoff_delay(3), 8);
        assert_eq!(get_backoff_delay(4), 16);
        assert_eq!(get_backoff_delay(5), 30);
        assert_eq!(get_backoff_delay(6), 60);
        assert_eq!(get_backoff_delay(7), 60);
        assert_eq!(get_backoff_delay(100), 60);
    }

    #[test]
    fn test_notification_queue_drop_policy() {
        let mut queue = NotificationQueue::new(3);

        // Push 3 finished
        assert!(queue.push(QueuedNotification {
            id: "1".into(),
            kind: NotificationKind::Finished,
            text: "fin 1".into(),
            created_at: Instant::now(),
        }));
        assert!(queue.push(QueuedNotification {
            id: "2".into(),
            kind: NotificationKind::Finished,
            text: "fin 2".into(),
            created_at: Instant::now(),
        }));
        assert!(queue.push(QueuedNotification {
            id: "3".into(),
            kind: NotificationKind::Approval,
            text: "approval 1".into(),
            created_at: Instant::now(),
        }));
        assert_eq!(queue.len(), 3);

        // Push 4th: should drop oldest finished (id 1)
        assert!(queue.push(QueuedNotification {
            id: "4".into(),
            kind: NotificationKind::Question,
            text: "question 1".into(),
            created_at: Instant::now(),
        }));
        assert_eq!(queue.len(), 3);
        assert_eq!(queue.items[0].id, "2");
        assert_eq!(queue.items[1].id, "3");
        assert_eq!(queue.items[2].id, "4");

        // Never drop approval/question when queue only has approvals/questions
        let mut full_important = NotificationQueue::new(2);
        full_important.push(QueuedNotification {
            id: "a1".into(),
            kind: NotificationKind::Approval,
            text: "app 1".into(),
            created_at: Instant::now(),
        });
        full_important.push(QueuedNotification {
            id: "q1".into(),
            kind: NotificationKind::Question,
            text: "q 1".into(),
            created_at: Instant::now(),
        });
        // Trying to push finished when all are important
        let pushed_fin = full_important.push(QueuedNotification {
            id: "f1".into(),
            kind: NotificationKind::Finished,
            text: "fin".into(),
            created_at: Instant::now(),
        });
        assert!(!pushed_fin);
        assert_eq!(full_important.len(), 2);
    }

    #[test]
    fn test_action_cases_fixtures() {
        let cases_json = include_str!("../../../tests/fixtures/telegram/action-cases.json");
        let val: serde_json::Value = serde_json::from_str(cases_json).unwrap();
        let cases = val["cases"].as_array().unwrap();

        let mut registry = TelegramActionRegistry::default();
        let now = Instant::now();

        for case in cases {
            let name = case["name"].as_str().unwrap();
            let cb_val = &case["callback_query"];
            let chat_id = cb_val["message"]["chat"]["id"].as_i64().unwrap();
            let chat_type = cb_val["message"]["chat"]["type"].as_str().unwrap();
            let user_id = cb_val["from"]["id"].as_i64().unwrap();
            let data = cb_val["data"].as_str().unwrap();

            let parsed_cb = parse_callback_data(data).unwrap();
            assert!(data.len() <= 64);

            if name == "valid-approval" {
                let action = TelegramAction {
                    r#ref: parsed_cb.r#ref.clone(),
                    kind: TelegramActionKind::ApprovalAllow,
                    fingerprint: "fp".into(),
                    session_id: "sess".into(),
                    expires_at: now + Duration::from_secs(120),
                    chat_id,
                    user_id,
                    message_id: 41,
                    state: TelegramActionState::Pending,
                };
                registry.entries.insert(parsed_cb.r#ref.clone(), action);

                let res = registry.consume(&parsed_cb.r#ref, chat_id, user_id, "fp", now);
                match res {
                    TelegramActionResult::Accepted(a) => {
                        assert_eq!(a.kind, TelegramActionKind::ApprovalAllow);
                        assert_eq!(parsed_cb.op, "allow");
                    }
                    _ => panic!("Expected accepted"),
                }
            } else if name == "wrong-user" {
                // from.id is 111222333, action has 987654321
                let action = TelegramAction {
                    r#ref: parsed_cb.r#ref.clone(),
                    kind: TelegramActionKind::ApprovalAllow,
                    fingerprint: "fp".into(),
                    session_id: "sess".into(),
                    expires_at: now + Duration::from_secs(120),
                    chat_id: 123456789,
                    user_id: 987654321,
                    message_id: 41,
                    state: TelegramActionState::Pending,
                };
                registry.entries.insert(parsed_cb.r#ref.clone(), action);
                let res = registry.consume(&parsed_cb.r#ref, chat_id, user_id, "fp", now);
                assert_eq!(
                    res,
                    TelegramActionResult::Rejected(TelegramActionRejection::Unauthorized)
                );
            } else if name == "group-chat" {
                assert_eq!(chat_type, "group");
            } else if name == "duplicate-callback" {
                let action = TelegramAction {
                    r#ref: parsed_cb.r#ref.clone(),
                    kind: TelegramActionKind::ApprovalAllow,
                    fingerprint: "fp".into(),
                    session_id: "sess".into(),
                    expires_at: now + Duration::from_secs(120),
                    chat_id,
                    user_id,
                    message_id: 41,
                    state: TelegramActionState::Consumed,
                };
                registry.entries.insert(parsed_cb.r#ref.clone(), action);
                let res = registry.consume(&parsed_cb.r#ref, chat_id, user_id, "fp", now);
                assert_eq!(
                    res,
                    TelegramActionResult::Rejected(TelegramActionRejection::Consumed)
                );
            } else if name == "expired-action" {
                let action = TelegramAction {
                    r#ref: parsed_cb.r#ref.clone(),
                    kind: TelegramActionKind::ApprovalDeny,
                    fingerprint: "fp".into(),
                    session_id: "sess".into(),
                    expires_at: now - Duration::from_secs(10),
                    chat_id,
                    user_id,
                    message_id: 41,
                    state: TelegramActionState::Expired,
                };
                registry.entries.insert(parsed_cb.r#ref.clone(), action);
                let res = registry.consume(&parsed_cb.r#ref, chat_id, user_id, "fp", now);
                assert_eq!(
                    res,
                    TelegramActionResult::Rejected(TelegramActionRejection::Expired)
                );
            }
        }
    }
}
