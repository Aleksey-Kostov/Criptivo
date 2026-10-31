use thiserror::Error;

#[derive(Debug, Error)]
pub enum MlsError {
    #[error("Identity must not be empty")]
    EmptyIdentity,

    #[error("Identity must not exceed 255 UTF-8 bytes")]
    IdentityTooLong,

    #[error("Unsupported state schema version: {0}")]
    UnsupportedSchema(u32),

    #[error("Invalid state JSON")]
    InvalidStateJson,

    #[error("Invalid Base64 encoding")]
    InvalidBase64,

    #[error("Empty or invalid key material")]
    InvalidKeyMaterial,

    #[error("Duplicate storage key in snapshot")]
    DuplicateStorageKey,

    #[error("Storage snapshot is empty")]
    EmptyStorage,

    #[error("Identity not loaded — call mls_load_identity first")]
    IdentityNotLoaded,

    #[error("Group not found: {0}")]
    GroupNotFound(String),

    #[error("Group already exists: {0}")]
    GroupAlreadyExists(String),

    #[error("Invalid KeyPackage")]
    InvalidKeyPackage,

    #[error("Invalid Welcome message")]
    InvalidWelcome,

    #[error("Invalid MLS message")]
    InvalidMessage,

    #[error("Unexpected message type: {0}")]
    UnexpectedMessageType(String),

    #[error("OpenMLS error: {0}")]
    OpenMls(String),

    #[error("Storage error: {0}")]
    Storage(String),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("{0}")]
    Other(String),
}

impl From<MlsError> for String {
    fn from(e: MlsError) -> Self {
        e.to_string()
    }
}

/// Хелпер за FRB — винаги връщаме JSON.
pub fn err_json(e: impl std::fmt::Display) -> String {
    serde_json::json!({
        "status": "error",
        "error": e.to_string()
    })
    .to_string()
}

pub fn ok_json(data: serde_json::Value) -> String {
    let mut map = serde_json::Map::new();
    map.insert("status".into(), serde_json::Value::String("ok".into()));
    if let serde_json::Value::Object(obj) = data {
        for (k, v) in obj {
            map.insert(k, v);
        }
    } else {
        map.insert("data".into(), data);
    }
    serde_json::Value::Object(map).to_string()
}