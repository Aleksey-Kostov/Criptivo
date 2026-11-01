use std::collections::HashMap;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use openmls::prelude::{
    tls_codec::{Deserialize as TlsDeserialize, Serialize as TlsSerialize},
    GroupId, KeyPackageIn, MlsGroup, MlsGroupCreateConfig, MlsGroupJoinConfig, MlsMessageBodyIn,
    MlsMessageIn, OpenMlsProvider, ProcessedMessageContent, ProtocolMessage, ProtocolVersion,
    StagedWelcome,
};
use openmls_rust_crypto::OpenMlsRustCrypto;
use serde::{Deserialize as SerdeDeserialize, Serialize as SerdeSerialize};

use crate::error::MlsError;
use crate::identity::MlsIdentity;
use crate::state::{export_storage, StorageEntry};
use crate::CIPHERSUITE;

/// Сериализируемо group state (за secure storage).
#[derive(Debug, SerdeSerialize, SerdeDeserialize)]
pub struct GroupStateBlob {
    pub schema_version: u32,
    /// Наш conversation id
    pub group_id: String,
    /// OpenMLS GroupId (нужен за MlsGroup::load)
    pub mls_group_id_base64: String,
    pub storage_entries: Vec<StorageEntry>,
    pub ratchet_tree_base64: Option<String>,
}

pub const GROUP_SCHEMA_VERSION: u32 = 2;

pub struct AddMemberResult {
    pub commit_b64: String,
    pub welcome_b64: String,
    pub group_state_json: String,
}

pub enum ProcessResult {
    Application {
        plaintext: Vec<u8>,
        group_state_json: String,
        epoch: u64,
    },
    CommitMerged {
        group_state_json: String,
        epoch: u64,
    },
    Proposal {
        group_state_json: String,
    },
    Other {
        info: String,
        group_state_json: String,
    },
}

/// In-memory group session.
pub struct MlsGroupSession {
    pub group_id: String,
    pub group: MlsGroup,
}

impl MlsGroupSession {
    /// Alice създава 1:1 група и добавя Bob чрез KeyPackage.
    pub fn create_dm(
        identity: &MlsIdentity,
        group_id: &str,
        their_key_package_b64: &str,
    ) -> Result<(Self, AddMemberResult), MlsError> {
        let kp_bytes = BASE64
            .decode(their_key_package_b64.trim())
            .map_err(|_| MlsError::InvalidBase64)?;

        let key_package_in = KeyPackageIn::tls_deserialize_exact(kp_bytes.as_slice())
            .map_err(|e| MlsError::OpenMls(format!("KP deserialize: {e}")))?;

        let key_package = key_package_in
            .validate(identity.provider.crypto(), ProtocolVersion::Mls10)
            .map_err(|e| MlsError::OpenMls(format!("KP validate: {e}")))?;

        let create_config = MlsGroupCreateConfig::builder()
            .ciphersuite(CIPHERSUITE)
            .use_ratchet_tree_extension(true)
            .build();

        let mut group = MlsGroup::new(
            &identity.provider,
            &identity.signer,
            &create_config,
            identity.credential_with_key.clone(),
        )
        .map_err(|e| MlsError::OpenMls(format!("create group: {e}")))?;

        let (commit, welcome, _group_info) = group
            .add_members(
                &identity.provider,
                &identity.signer,
                core::slice::from_ref(&key_package),
            )
            .map_err(|e| MlsError::OpenMls(format!("add_members: {e}")))?;

        group
            .merge_pending_commit(&identity.provider)
            .map_err(|e| MlsError::OpenMls(format!("merge commit: {e}")))?;

        let commit_b64 = BASE64.encode(
            commit
                .tls_serialize_detached()
                .map_err(|e| MlsError::Serialization(e.to_string()))?,
        );

        let welcome_b64 = BASE64.encode(
            welcome
                .tls_serialize_detached()
                .map_err(|e| MlsError::Serialization(e.to_string()))?,
        );

        let session = Self {
            group_id: group_id.to_string(),
            group,
        };

        let group_state_json = session.export_state(&identity.provider)?;

        Ok((
            session,
            AddMemberResult {
                commit_b64,
                welcome_b64,
                group_state_json,
            },
        ))
    }

    /// Bob приема Welcome и влиза в групата.
    pub fn join_from_welcome(
        identity: &MlsIdentity,
        group_id: &str,
        welcome_b64: &str,
    ) -> Result<Self, MlsError> {
        let welcome_bytes = BASE64
            .decode(welcome_b64.trim())
            .map_err(|_| MlsError::InvalidBase64)?;

        let mls_message = MlsMessageIn::tls_deserialize_exact(welcome_bytes.as_slice())
            .map_err(|e| MlsError::OpenMls(format!("Welcome deserialize: {e}")))?;

        let welcome = match mls_message.extract() {
            MlsMessageBodyIn::Welcome(w) => w,
            other => {
                return Err(MlsError::UnexpectedMessageType(format!("{other:?}")));
            }
        };

        let join_config = MlsGroupJoinConfig::builder()
            .use_ratchet_tree_extension(true)
            .build();

        let staged = StagedWelcome::new_from_welcome(
            &identity.provider,
            &join_config,
            welcome,
            None,
        )
        .map_err(|e| MlsError::OpenMls(format!("StagedWelcome: {e}")))?;

        let group = staged
            .into_group(&identity.provider)
            .map_err(|e| MlsError::OpenMls(format!("into_group: {e}")))?;

        Ok(Self {
            group_id: group_id.to_string(),
            group,
        })
    }

    /// Възстановява група от protected blob (след restart).
    pub fn load_from_state(
        identity: &MlsIdentity,
        conversation_id: &str,
        state_json: &str,
    ) -> Result<Self, MlsError> {
        let blob: GroupStateBlob =
            serde_json::from_str(state_json).map_err(|_| MlsError::InvalidStateJson)?;

        if blob.schema_version != GROUP_SCHEMA_VERSION {
            return Err(MlsError::UnsupportedSchema(blob.schema_version));
        }

        if blob.group_id != conversation_id {
            return Err(MlsError::Other(format!(
                "group_id mismatch: blob={} arg={}",
                blob.group_id, conversation_id
            )));
        }

        // Merge storage entries в identity provider
        {
            let mut values = identity
                .provider
                .storage()
                .values
                .write()
                .map_err(|_| MlsError::Storage("lock storage".into()))?;

            for entry in &blob.storage_entries {
                let key = BASE64
                    .decode(&entry.key_base64)
                    .map_err(|_| MlsError::InvalidBase64)?;
                let value = BASE64
                    .decode(&entry.value_base64)
                    .map_err(|_| MlsError::InvalidBase64)?;
                values.insert(key, value);
            }
        }

        let gid_bytes = BASE64
            .decode(blob.mls_group_id_base64.trim())
            .map_err(|_| MlsError::InvalidBase64)?;

        let mls_group_id = GroupId::from_slice(&gid_bytes);

        let group = MlsGroup::load(identity.provider.storage(), &mls_group_id)
            .map_err(|e| MlsError::OpenMls(format!("MlsGroup::load: {e}")))?
            .ok_or_else(|| {
                MlsError::GroupNotFound(format!(
                    "MLS group not in storage for conversation {conversation_id}"
                ))
            })?;

        Ok(Self {
            group_id: conversation_id.to_string(),
            group,
        })
    }

    /// Криптира application message.
    pub fn encrypt(
        &mut self,
        identity: &MlsIdentity,
        plaintext: &[u8],
    ) -> Result<(String, String), MlsError> {
        let message = self
            .group
            .create_message(&identity.provider, &identity.signer, plaintext)
            .map_err(|e| MlsError::OpenMls(format!("create_message: {e}")))?;

        let ciphertext = BASE64.encode(
            message
                .tls_serialize_detached()
                .map_err(|e| MlsError::Serialization(e.to_string()))?,
        );

        let state = self.export_state(&identity.provider)?;
        Ok((ciphertext, state))
    }

    /// Обработва входящо MLS съобщение (application / commit / proposal).
    pub fn process_message(
        &mut self,
        identity: &MlsIdentity,
        message_b64: &str,
    ) -> Result<ProcessResult, MlsError> {
        let bytes = BASE64
            .decode(message_b64.trim())
            .map_err(|_| MlsError::InvalidBase64)?;

        let mls_in = MlsMessageIn::tls_deserialize_exact(bytes.as_slice())
            .map_err(|e| MlsError::OpenMls(format!("message deserialize: {e}")))?;

        let protocol_message: ProtocolMessage = mls_in
            .try_into_protocol_message()
            .map_err(|e| MlsError::OpenMls(format!("not protocol message: {e}")))?;

        let processed = self
            .group
            .process_message(&identity.provider, protocol_message)
            .map_err(|e| MlsError::OpenMls(format!("process_message: {e}")))?;

        let epoch = self.group.epoch().as_u64();

        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(app) => {
                let plaintext = app.into_bytes();
                let state = self.export_state(&identity.provider)?;
                Ok(ProcessResult::Application {
                    plaintext,
                    group_state_json: state,
                    epoch,
                })
            }
            ProcessedMessageContent::StagedCommitMessage(staged) => {
                self.group
                    .merge_staged_commit(&identity.provider, *staged)
                    .map_err(|e| MlsError::OpenMls(format!("merge_staged: {e}")))?;
                let epoch = self.group.epoch().as_u64();
                let state = self.export_state(&identity.provider)?;
                Ok(ProcessResult::CommitMerged {
                    group_state_json: state,
                    epoch,
                })
            }
            ProcessedMessageContent::ProposalMessage(_) => {
                let state = self.export_state(&identity.provider)?;
                Ok(ProcessResult::Proposal {
                    group_state_json: state,
                })
            }
            other => {
                let state = self.export_state(&identity.provider)?;
                Ok(ProcessResult::Other {
                    info: format!("{other:?}"),
                    group_state_json: state,
                })
            }
        }
    }

    pub fn current_epoch(&self) -> u64 {
        self.group.epoch().as_u64()
    }

    /// Export secret за Glagolitic Seal (epoch-bound).
    pub fn export_seal_secret(
        &self,
        identity: &MlsIdentity,
        conversation_id: &str,
        length: usize,
    ) -> Result<Vec<u8>, MlsError> {
        self.group
            .export_secret(
                identity.provider.crypto(),
                "criptivo-seal-v1",
                conversation_id.as_bytes(),
                length,
            )
            .map_err(|e| MlsError::OpenMls(format!("export_secret: {e}")))
    }

    pub fn export_state(&self, provider: &OpenMlsRustCrypto) -> Result<String, MlsError> {
        let storage_entries = export_storage(provider)?;

        let tree = self.group.export_ratchet_tree();
        let tree_b64 = BASE64.encode(
            tree.tls_serialize_detached()
                .map_err(|e| MlsError::Serialization(e.to_string()))?,
        );

        let mls_group_id_base64 = BASE64.encode(self.group.group_id().as_slice());

        let blob = GroupStateBlob {
            schema_version: GROUP_SCHEMA_VERSION,
            group_id: self.group_id.clone(),
            mls_group_id_base64,
            storage_entries,
            ratchet_tree_base64: Some(tree_b64),
        };

        serde_json::to_string(&blob).map_err(|e| MlsError::Serialization(e.to_string()))
    }
}

/// Глобален registry на групите в процеса.
pub struct GroupRegistry {
    groups: HashMap<String, MlsGroupSession>,
}

impl GroupRegistry {
    pub fn new() -> Self {
        Self {
            groups: HashMap::new(),
        }
    }

    pub fn insert(&mut self, session: MlsGroupSession) {
        self.groups.insert(session.group_id.clone(), session);
    }

    pub fn get_mut(&mut self, group_id: &str) -> Result<&mut MlsGroupSession, MlsError> {
        self.groups
            .get_mut(group_id)
            .ok_or_else(|| MlsError::GroupNotFound(group_id.to_string()))
    }

    pub fn contains(&self, group_id: &str) -> bool {
        self.groups.contains_key(group_id)
    }
}