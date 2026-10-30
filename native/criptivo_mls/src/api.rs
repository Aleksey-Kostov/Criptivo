use serde_json::json;

use crate::error::{err_json, ok_json, MlsError};
use crate::identity::MlsIdentity;
use crate::{set_identity, with_identity, with_identity_mut, CRIPTIVO_MLS_VERSION};

/// Проверява дали native модулът е зареден.
pub fn mls_native_status() -> String {
    "criptivo_mls_ready".to_string()
}

pub fn mls_version() -> String {
    CRIPTIVO_MLS_VERSION.to_string()
}

/// Създава нова identity и я зарежда в runtime.
///
/// Връща:
/// ```json
/// {
///   "status": "ok",
///   "identity": "...",
///   "signature_public_key_base64": "...",
///   "protected_state_json": "..."   // САМО в secure storage!
/// }
/// ```
pub fn mls_create_identity(identity: String) -> String {
    match create_identity_inner(&identity) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn create_identity_inner(identity: &str) -> Result<String, MlsError> {
    let id = MlsIdentity::create(identity)?;
    let public_key = id.public_signature_key_base64();
    let state = id.export_state()?;
    let name = id.identity.clone();

    set_identity(id)?;

    Ok(ok_json(json!({
        "identity": name,
        "signature_public_key_base64": public_key,
        "protected_state_json": state,
        "ciphersuite": "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
        "mls_version": CRIPTIVO_MLS_VERSION,
    })))
}

/// Зарежда identity от protected snapshot (при старт на приложението).
pub fn mls_load_identity(protected_state_json: String) -> String {
    match load_identity_inner(&protected_state_json) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn load_identity_inner(state_json: &str) -> Result<String, MlsError> {
    let id = MlsIdentity::restore(state_json)?;
    let public_key = id.public_signature_key_base64();
    let name = id.identity.clone();

    set_identity(id)?;

    Ok(ok_json(json!({
        "identity": name,
        "signature_public_key_base64": public_key,
    })))
}

/// Генерира N KeyPackages. След това връща и обновен protected_state
/// (storage-ът се е променил).
pub fn mls_generate_key_packages(count: u32) -> String {
    match generate_kps_inner(count) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn generate_kps_inner(count: u32) -> Result<String, MlsError> {
    let (packages, state) = with_identity_mut(|id| {
        let kps = id.generate_key_packages(count)?;
        let state = id.export_state()?;
        Ok((kps, state))
    })?;

    Ok(ok_json(json!({
        "key_packages": packages,
        "protected_state_json": state,
    })))
}

/// Връща публичния signature key на заредената identity.
pub fn mls_public_key() -> String {
    match with_identity(|id| Ok(id.public_signature_key_base64())) {
        Ok(pk) => ok_json(json!({ "signature_public_key_base64": pk })),
        Err(e) => err_json(e),
    }
}
