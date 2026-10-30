use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use openmls::prelude::{
    tls_codec::Serialize, BasicCredential, Ciphersuite, CredentialWithKey, KeyPackage,
};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls::prelude::OpenMlsProvider;

use crate::error::MlsError;
use crate::state::{
    export_storage, restore_provider, IdentityState, IDENTITY_SCHEMA_VERSION,
};
use crate::CIPHERSUITE;

pub struct MlsIdentity {
    pub identity: String,
    pub signer: SignatureKeyPair,
    pub credential_with_key: CredentialWithKey,
    pub provider: OpenMlsRustCrypto,
}

impl MlsIdentity {
    /// Нова дългоживуща identity + първоначален storage.
    pub fn create(identity: &str) -> Result<Self, MlsError> {
        let identity = identity.trim();
        if identity.is_empty() {
            return Err(MlsError::EmptyIdentity);
        }
        if identity.len() > 255 {
            return Err(MlsError::IdentityTooLong);
        }

        let provider = OpenMlsRustCrypto::default();

        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
            .map_err(|e| MlsError::OpenMls(format!("signature keygen: {e}")))?;

        signer
            .store(provider.storage())
            .map_err(|e| MlsError::Storage(format!("store signer: {e}")))?;

        let credential = BasicCredential::new(identity.as_bytes().to_vec());
        let credential_with_key = CredentialWithKey {
            credential: credential.into(),
            signature_key: signer.public().into(),
        };

        Ok(Self {
            identity: identity.to_string(),
            signer,
            credential_with_key,
            provider,
        })
    }

    /// Възстановява identity от protected snapshot.
    pub fn restore(state_json: &str) -> Result<Self, MlsError> {
        let state = IdentityState::from_json(state_json)?;

        let provider = restore_provider(&state.storage_entries)?;

        let signer_bytes = BASE64
            .decode(&state.signer_json_base64)
            .map_err(|_| MlsError::InvalidBase64)?;

        if signer_bytes.is_empty() {
            return Err(MlsError::InvalidKeyMaterial);
        }

        let signer: SignatureKeyPair = serde_json::from_slice(&signer_bytes)
            .map_err(|e| MlsError::Serialization(format!("signer deserialize: {e}")))?;

        // Уверяваме се, че signer е в storage-а
        signer
            .store(provider.storage())
            .map_err(|e| MlsError::Storage(format!("re-store signer: {e}")))?;

        let pub_key = BASE64
            .decode(&state.signature_public_key_base64)
            .map_err(|_| MlsError::InvalidBase64)?;

        if pub_key.is_empty() || pub_key.as_slice() != signer.public() {
            return Err(MlsError::InvalidKeyMaterial);
        }

        let credential = BasicCredential::new(state.identity.as_bytes().to_vec());
        let credential_with_key = CredentialWithKey {
            credential: credential.into(),
            signature_key: signer.public().into(),
        };

        Ok(Self {
            identity: state.identity,
            signer,
            credential_with_key,
            provider,
        })
    }

    /// Генерира `count` свежи KeyPackages (за качване в Supabase).
    pub fn generate_key_packages(&self, count: u32) -> Result<Vec<String>, MlsError> {
        if count == 0 || count > 200 {
            return Err(MlsError::Other(
                "count must be between 1 and 200".into(),
            ));
        }

        let mut packages = Vec::with_capacity(count as usize);

        for _ in 0..count {
            let bundle = KeyPackage::builder()
                .build(
                    CIPHERSUITE,
                    &self.provider,
                    &self.signer,
                    self.credential_with_key.clone(),
                )
                .map_err(|e| MlsError::OpenMls(format!("KeyPackage: {e}")))?;

            let bytes = bundle
                .key_package()
                .tls_serialize_detached()
                .map_err(|e| MlsError::Serialization(format!("KP serialize: {e}")))?;

            packages.push(BASE64.encode(&bytes));
        }

        Ok(packages)
    }

    /// Експортира protected state за secure storage.
    pub fn export_state(&self) -> Result<String, MlsError> {
        let storage_entries = export_storage(&self.provider)?;

        let signer_json = serde_json::to_vec(&self.signer)
            .map_err(|e| MlsError::Serialization(e.to_string()))?;

        let state = IdentityState {
            schema_version: IDENTITY_SCHEMA_VERSION,
            identity: self.identity.clone(),
            signature_public_key_base64: BASE64.encode(self.signer.public()),
            signer_json_base64: BASE64.encode(&signer_json),
            storage_entries,
        };

        state.to_json()
    }

    pub fn public_signature_key_base64(&self) -> String {
        BASE64.encode(self.signer.public())
    }
}