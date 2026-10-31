use serde_json::json;

use crate::error::{err_json, ok_json, MlsError};
use crate::group::{MlsGroupSession, ProcessResult};
use crate::identity::MlsIdentity;
use crate::{
    set_identity, with_groups_mut, with_identity, with_identity_mut, CRIPTIVO_MLS_VERSION,
};

/// Проверява дали native модулът е зареден.
pub fn mls_native_status() -> String {
    "criptivo_mls_ready".to_string()
}

pub fn mls_version() -> String {
    CRIPTIVO_MLS_VERSION.to_string()
}

/// Създава нова identity и я зарежда в runtime.
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

/// Генерира N KeyPackages. След това връща и обновен protected_state.
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

// ---------------------------------------------------------------------------
// Group / DM operations
// ---------------------------------------------------------------------------

/// Alice създава 1:1 група и добавя Bob чрез KeyPackage.
pub fn mls_create_dm(group_id: String, their_key_package_b64: String) -> String {
    match create_dm_inner(&group_id, &their_key_package_b64) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn create_dm_inner(group_id: &str, kp_b64: &str) -> Result<String, MlsError> {
    with_identity(|identity| {
        with_groups_mut(|reg| {
            if reg.contains(group_id) {
                return Err(MlsError::GroupAlreadyExists(group_id.to_string()));
            }
            let (session, add) = MlsGroupSession::create_dm(identity, group_id, kp_b64)?;
            reg.insert(session);
            Ok(ok_json(json!({
                "group_id": group_id,
                "commit_b64": add.commit_b64,
                "welcome_b64": add.welcome_b64,
                "group_state_json": add.group_state_json,
            })))
        })
    })
}

/// Bob приема Welcome и влиза в групата.
pub fn mls_join_dm(group_id: String, welcome_b64: String) -> String {
    match join_dm_inner(&group_id, &welcome_b64) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn join_dm_inner(group_id: &str, welcome_b64: &str) -> Result<String, MlsError> {
    with_identity(|identity| {
        with_groups_mut(|reg| {
            let session =
                MlsGroupSession::join_from_welcome(identity, group_id, welcome_b64)?;
            let state = session.export_state(&identity.provider)?;
            let epoch = session.current_epoch();
            reg.insert(session);
            Ok(ok_json(json!({
                "group_id": group_id,
                "group_state_json": state,
                "epoch": epoch,
            })))
        })
    })
}

/// Криптира application message.
pub fn mls_encrypt(group_id: String, plaintext: String) -> String {
    match encrypt_inner(&group_id, plaintext.as_bytes()) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn encrypt_inner(group_id: &str, plaintext: &[u8]) -> Result<String, MlsError> {
    with_identity(|identity| {
        with_groups_mut(|reg| {
            let session = reg.get_mut(group_id)?;
            let (ciphertext_b64, group_state_json) = session.encrypt(identity, plaintext)?;
            let epoch = session.current_epoch();
            Ok(ok_json(json!({
                "ciphertext_b64": ciphertext_b64,
                "group_state_json": group_state_json,
                "epoch": epoch,
            })))
        })
    })
}

/// Обработва входящо MLS съобщение (application / commit / proposal).
pub fn mls_process(group_id: String, message_b64: String) -> String {
    match process_inner(&group_id, &message_b64) {
        Ok(v) => v,
        Err(e) => err_json(e),
    }
}

fn process_inner(group_id: &str, message_b64: &str) -> Result<String, MlsError> {
    with_identity(|identity| {
        with_groups_mut(|reg| {
            let session = reg.get_mut(group_id)?;
            let result = session.process_message(identity, message_b64)?;
            match result {
                ProcessResult::Application {
                    plaintext,
                    group_state_json,
                    epoch,
                } => Ok(ok_json(json!({
                    "type": "application",
                    "plaintext": String::from_utf8_lossy(&plaintext),
                    "group_state_json": group_state_json,
                    "epoch": epoch,
                }))),
                ProcessResult::CommitMerged {
                    group_state_json,
                    epoch,
                } => Ok(ok_json(json!({
                    "type": "commit",
                    "group_state_json": group_state_json,
                    "epoch": epoch,
                }))),
                ProcessResult::Proposal { group_state_json } => Ok(ok_json(json!({
                    "type": "proposal",
                    "group_state_json": group_state_json,
                }))),
                ProcessResult::Other {
                    info,
                    group_state_json,
                } => Ok(ok_json(json!({
                    "type": "other",
                    "info": info,
                    "group_state_json": group_state_json,
                }))),
            }
        })
    })
}