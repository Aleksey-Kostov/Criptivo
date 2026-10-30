use std::collections::HashMap;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls::prelude::OpenMlsProvider;
use serde::{Deserialize, Serialize};

use crate::error::MlsError;

pub const IDENTITY_SCHEMA_VERSION: u32 = 2;

#[derive(Debug, Serialize, Deserialize)]
pub struct StorageEntry {
    pub key_base64: String,
    pub value_base64: String,
}

/// Protected identity snapshot — само локално, никога към Supabase.
#[derive(Debug, Serialize, Deserialize)]
pub struct IdentityState {
    pub schema_version: u32,
    pub identity: String,
    pub signature_public_key_base64: String,
    pub signer_json_base64: String,
    pub storage_entries: Vec<StorageEntry>,
}

impl IdentityState {
    pub fn to_json(&self) -> Result<String, MlsError> {
        serde_json::to_string(self).map_err(|e| MlsError::Serialization(e.to_string()))
    }

    pub fn from_json(json: &str) -> Result<Self, MlsError> {
        let state: Self =
            serde_json::from_str(json).map_err(|_| MlsError::InvalidStateJson)?;
        if state.schema_version != IDENTITY_SCHEMA_VERSION {
            return Err(MlsError::UnsupportedSchema(state.schema_version));
        }
        if state.identity.trim().is_empty() {
            return Err(MlsError::EmptyIdentity);
        }
        Ok(state)
    }
}

/// Чете storage map от provider и го сериализира.
pub fn export_storage(provider: &OpenMlsRustCrypto) -> Result<Vec<StorageEntry>, MlsError> {
    let values = provider
        .storage()
        .values
        .read()
        .map_err(|_| MlsError::Storage("Could not read OpenMLS storage".into()))?;

    let entries: Vec<StorageEntry> = values
        .iter()
        .map(|(key, value)| StorageEntry {
            key_base64: BASE64.encode(key),
            value_base64: BASE64.encode(value),
        })
        .collect();

    if entries.is_empty() {
        return Err(MlsError::EmptyStorage);
    }
    Ok(entries)
}

/// Възстановява provider от storage entries.
pub fn restore_provider(entries: &[StorageEntry]) -> Result<OpenMlsRustCrypto, MlsError> {
    let mut restored: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();

    for entry in entries {
        let key = BASE64
            .decode(&entry.key_base64)
            .map_err(|_| MlsError::InvalidBase64)?;
        let value = BASE64
            .decode(&entry.value_base64)
            .map_err(|_| MlsError::InvalidBase64)?;

        if restored.insert(key, value).is_some() {
            return Err(MlsError::DuplicateStorageKey);
        }
    }

    if restored.is_empty() {
        return Err(MlsError::EmptyStorage);
    }

    let provider = OpenMlsRustCrypto::default();
    {
        let mut values = provider
            .storage()
            .values
            .write()
            .map_err(|_| MlsError::Storage("Could not lock OpenMLS storage".into()))?;
        *values = restored;
    }
    Ok(provider)
}