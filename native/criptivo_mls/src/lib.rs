#![deny(unsafe_code)]

#[allow(unsafe_code)]
mod frb_generated;

pub mod api;

use std::collections::HashMap;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use openmls::prelude::OpenMlsProvider;
use openmls::prelude::{
    tls_codec::Serialize, BasicCredential, Ciphersuite, CredentialWithKey, KeyPackage,
};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use serde::{Deserialize, Serialize as SerdeSerialize};

pub const CRIPTIVO_MLS_VERSION: &str = env!("CARGO_PKG_VERSION");

const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

#[derive(Debug, SerdeSerialize, Deserialize)]
struct StorageEntry {
    key_base64: String,
    value_base64: String,
}

/// Локално състояние с чувствителен криптографски материал.
/// Не изпращай този snapshot към Supabase в незащитен вид.
#[derive(Debug, SerdeSerialize, Deserialize)]
struct IdentityState {
    schema_version: u32,
    identity: String,
    signature_public_key_base64: String,
    key_package_base64: String,
    signer_json_base64: String,
    storage_entries: Vec<StorageEntry>,
}

#[derive(Debug, SerdeSerialize, Deserialize)]
struct IdentityResult {
    status: String,
    mls_version: String,
    ciphersuite: String,
    identity: String,
    key_package_base64: String,
    protected_state_json: String,
}

/// Генерира MLS идентичност и KeyPackage.
pub fn create_identity(identity: &str) -> Result<String, String> {
    let identity = identity.trim();

    if identity.is_empty() {
        return Err("Identity must not be empty.".to_string());
    }

    if identity.len() > 255 {
        return Err("Identity must not exceed 255 UTF-8 bytes.".to_string());
    }

    let provider = OpenMlsRustCrypto::default();

    let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
        .map_err(|e| format!("Could not generate signature keys: {e}"))?;

    signer
        .store(provider.storage())
        .map_err(|e| format!("Could not store signature keys: {e}"))?;

    let credential = BasicCredential::new(identity.as_bytes().to_vec());

    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: signer.public().into(),
    };

    let key_package_bundle = KeyPackage::builder()
        .build(CIPHERSUITE, &provider, &signer, credential_with_key)
        .map_err(|e| format!("Could not generate KeyPackage: {e}"))?;

    let key_package_bytes = key_package_bundle
        .key_package()
        .tls_serialize_detached()
        .map_err(|e| format!("Could not serialize KeyPackage: {e}"))?;

    let signer_json =
        serde_json::to_vec(&signer).map_err(|e| format!("Could not serialize signer: {e}"))?;

    let values = provider
        .storage()
        .values
        .read()
        .map_err(|_| "Could not read OpenMLS storage.".to_string())?;

    let storage_entries: Vec<StorageEntry> = values
        .iter()
        .map(|(key, value)| StorageEntry {
            key_base64: BASE64.encode(key),
            value_base64: BASE64.encode(value),
        })
        .collect();

    let key_package_base64 = BASE64.encode(&key_package_bytes);

    let state = IdentityState {
        schema_version: 1,
        identity: identity.to_string(),
        signature_public_key_base64: BASE64.encode(signer.public()),
        key_package_base64: key_package_base64.clone(),
        signer_json_base64: BASE64.encode(signer_json),
        storage_entries,
    };

    let protected_state_json = serde_json::to_string(&state)
        .map_err(|e| format!("Could not serialize identity state: {e}"))?;

    let result = IdentityResult {
        status: "key_package_created".to_string(),
        mls_version: CRIPTIVO_MLS_VERSION.to_string(),
        ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519".to_string(),
        identity: identity.to_string(),
        key_package_base64,
        protected_state_json,
    };

    serde_json::to_string(&result).map_err(|e| format!("Could not serialize result: {e}"))
}

/// Възстановява OpenMLS storage map от локален snapshot.
/// Това само по себе си не доказва, че цяла MLS сесия е възстановена.
pub fn restore_storage_snapshot(state_json: &str) -> Result<OpenMlsRustCrypto, String> {
    let state: IdentityState =
        serde_json::from_str(state_json).map_err(|_| "Invalid identity state JSON.".to_string())?;

    if state.schema_version != 1 {
        return Err("Unsupported identity state version.".to_string());
    }

    if state.identity.trim().is_empty() {
        return Err("Identity must not be empty.".to_string());
    }

    let public_key = BASE64
        .decode(&state.signature_public_key_base64)
        .map_err(|_| "Invalid public signature key encoding.".to_string())?;

    if public_key.is_empty() {
        return Err("Public signature key must not be empty.".to_string());
    }

    let key_package = BASE64
        .decode(&state.key_package_base64)
        .map_err(|_| "Invalid KeyPackage encoding.".to_string())?;

    if key_package.is_empty() {
        return Err("KeyPackage must not be empty.".to_string());
    }

    let signer = BASE64
        .decode(&state.signer_json_base64)
        .map_err(|_| "Invalid signer encoding.".to_string())?;

    if signer.is_empty() {
        return Err("Signer data must not be empty.".to_string());
    }

    let mut restored_values = HashMap::new();

    for entry in state.storage_entries {
        let key = BASE64
            .decode(&entry.key_base64)
            .map_err(|_| "Invalid storage key encoding.".to_string())?;

        let value = BASE64
            .decode(&entry.value_base64)
            .map_err(|_| "Invalid storage value encoding.".to_string())?;

        if restored_values.insert(key, value).is_some() {
            return Err("Duplicate storage key.".to_string());
        }
    }

    if restored_values.is_empty() {
        return Err("Storage snapshot is empty.".to_string());
    }

    let provider = OpenMlsRustCrypto::default();

    {
        let mut values = provider
            .storage()
            .values
            .write()
            .map_err(|_| "Could not lock OpenMLS storage.".to_string())?;

        *values = restored_values;
    }

    Ok(provider)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_module_reports_version() {
        assert!(!CRIPTIVO_MLS_VERSION.is_empty());
    }

    #[test]
    fn creates_a_key_package_and_local_state() {
        let output = create_identity("test-user-001").expect("identity creation should succeed");

        let result: IdentityResult =
            serde_json::from_str(&output).expect("result should be valid JSON");

        assert_eq!(result.status, "key_package_created");
        assert_eq!(result.identity, "test-user-001");
        assert!(!result.key_package_base64.is_empty());

        let package_bytes = BASE64
            .decode(&result.key_package_base64)
            .expect("KeyPackage should be valid Base64");

        assert!(!package_bytes.is_empty());

        let state: IdentityState = serde_json::from_str(&result.protected_state_json)
            .expect("local state should be valid JSON");

        assert_eq!(state.schema_version, 1);
        assert_eq!(state.identity, "test-user-001");
        assert!(!state.signer_json_base64.is_empty());
        assert!(!state.signature_public_key_base64.is_empty());
        assert!(!state.storage_entries.is_empty());
    }

    #[test]
    fn rejects_an_empty_identity() {
        assert!(create_identity("  ").is_err());
    }

    #[test]
    fn creates_distinct_key_packages() {
        let first =
            create_identity("test-user-001").expect("first identity creation should succeed");

        let second =
            create_identity("test-user-001").expect("second identity creation should succeed");

        let first: IdentityResult = serde_json::from_str(&first).unwrap();
        let second: IdentityResult = serde_json::from_str(&second).unwrap();

        assert_ne!(first.key_package_base64, second.key_package_base64);
    }

    #[test]
    fn restores_storage_snapshot() {
        let output =
            create_identity("restore-test-user").expect("identity creation should succeed");

        let result: IdentityResult =
            serde_json::from_str(&output).expect("result should be valid JSON");

        let original_state: IdentityState =
            serde_json::from_str(&result.protected_state_json).expect("state should be valid JSON");

        let expected_entries = original_state.storage_entries.len();

        let provider = restore_storage_snapshot(&result.protected_state_json)
            .expect("storage restoration should succeed");

        let restored_values = provider
            .storage()
            .values
            .read()
            .expect("storage should be readable");

        assert_eq!(restored_values.len(), expected_entries);

        for entry in &original_state.storage_entries {
            let key = BASE64.decode(&entry.key_base64).unwrap();
            let expected_value = BASE64.decode(&entry.value_base64).unwrap();

            assert_eq!(restored_values.get(&key), Some(&expected_value));
        }
    }

    #[test]
    fn rejects_invalid_snapshot_json() {
        assert!(restore_storage_snapshot("not-json").is_err());
    }

    #[test]
    fn alice_and_bob_exchange_an_encrypted_message() {
        use openmls::prelude::tls_codec::{Deserialize, Serialize};
        use openmls::prelude::{
            BasicCredential, CredentialWithKey, KeyPackage, MlsGroup, MlsGroupJoinConfig,
            MlsMessageBodyIn, MlsMessageIn, OpenMlsProvider, ProcessedMessageContent,
            StagedWelcome,
        };

        const MESSAGE: &[u8] = b"Hello Bob - encrypted with OpenMLS!";

        // Alice и Bob използват отделни локални crypto providers.
        let alice_provider = OpenMlsRustCrypto::default();
        let bob_provider = OpenMlsRustCrypto::default();

        let alice_signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
            .expect("Alice signing key generation should succeed");

        alice_signer
            .store(alice_provider.storage())
            .expect("Alice signing key should be stored");

        let alice_credential = CredentialWithKey {
            credential: BasicCredential::new(b"Alice".to_vec()).into(),
            signature_key: alice_signer.public().into(),
        };

        let bob_signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
            .expect("Bob signing key generation should succeed");

        bob_signer
            .store(bob_provider.storage())
            .expect("Bob signing key should be stored");

        let bob_credential = CredentialWithKey {
            credential: BasicCredential::new(b"Bob".to_vec()).into(),
            signature_key: bob_signer.public().into(),
        };

        // Bob генерира свой KeyPackage.
        let bob_key_package = KeyPackage::builder()
            .build(CIPHERSUITE, &bob_provider, &bob_signer, bob_credential)
            .expect("Bob KeyPackage creation should succeed");

        // Alice създава групата.
        let mut alice_group = MlsGroup::builder()
            .ciphersuite(CIPHERSUITE)
            .use_ratchet_tree_extension(true)
            .build(&alice_provider, &alice_signer, alice_credential)
            .expect("Alice group creation should succeed");

        // Alice добавя Bob и генерира Commit и Welcome.
        let (_commit, welcome, _group_info) = alice_group
            .add_members(
                &alice_provider,
                &alice_signer,
                core::slice::from_ref(bob_key_package.key_package()),
            )
            .expect("Alice should be able to add Bob");

        // Alice потвърждава промените в собственото си състояние.
        alice_group
            .merge_pending_commit(&alice_provider)
            .expect("Alice should merge the pending commit");

        // Сериализираме Welcome, сякаш минава през транспорт.
        let welcome_bytes = welcome
            .tls_serialize_detached()
            .expect("Welcome serialization should succeed");

        let welcome_message = MlsMessageIn::tls_deserialize_exact(welcome_bytes.as_slice())
            .expect("Bob should deserialize the Welcome");

        // OpenMLS 0.9.2: използваме extract(), не into_welcome().
        let welcome = match welcome_message.extract() {
            MlsMessageBodyIn::Welcome(welcome) => welcome,
            _ => panic!("Incoming message should contain a Welcome"),
        };

        // Bob се присъединява към групата чрез Welcome.
        let staged_welcome = StagedWelcome::new_from_welcome(
            &bob_provider,
            &MlsGroupJoinConfig::default(),
            welcome,
            None,
        )
        .expect("Bob should process the Welcome");

        let mut bob_group = staged_welcome
            .into_group(&bob_provider)
            .expect("Bob should join the group");

        assert_eq!(alice_group.members().count(), 2);
        assert_eq!(bob_group.members().count(), 2);

        // Alice създава криптирано MLS application съобщение.
        let encrypted_message = alice_group
            .create_message(&alice_provider, &alice_signer, MESSAGE)
            .expect("Alice should encrypt the application message");

        let encrypted_bytes = encrypted_message
            .tls_serialize_detached()
            .expect("Encrypted message serialization should succeed");

        // Bob получава сериализираното съобщение и го обработва.
        let incoming_message = MlsMessageIn::tls_deserialize_exact(encrypted_bytes.as_slice())
            .expect("Bob should deserialize the encrypted message");

        let protocol_message = incoming_message
            .try_into_protocol_message()
            .expect("Message should be a protocol message");

        let processed_message = bob_group
            .process_message(&bob_provider, protocol_message)
            .expect("Bob should decrypt and authenticate Alice's message");

        match processed_message.into_content() {
            ProcessedMessageContent::ApplicationMessage(application_message) => {
                assert_eq!(application_message.into_bytes(), MESSAGE);
            }
            other => panic!("Expected an application message, got: {other:?}"),
        }
    }
}
