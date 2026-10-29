use serde_json::json;

/// Проверява дали Rust/OpenMLS модулът е достъпен през Flutter bridge.
pub fn mls_native_status() -> String {
    "criptivo_mls_ready".to_string()
}

/// Връща версията на native crate.
pub fn mls_version() -> String {
    crate::CRIPTIVO_MLS_VERSION.to_string()
}

/// Създава MLS идентичност.
///
/// Връща JSON низ:
/// - при успех: резултатът от create_identity()
/// - при грешка: {"status":"error","error":"..."}
///
/// ВАЖНО:
/// Резултатът при успех съдържа protected_state_json със секретен материал.
/// Не го записвай в логове и не го изпращай към Supabase.
/// Преди продукционна употреба го съхранявай само чрез защитено локално
/// съхранение и добави валидирано възстановяване на цялото MLS състояние.
pub fn mls_create_identity(identity: String) -> String {
    match crate::create_identity(&identity) {
        Ok(result_json) => result_json,
        Err(error) => json!({
            "status": "error",
            "error": error
        })
        .to_string(),
    }
}
