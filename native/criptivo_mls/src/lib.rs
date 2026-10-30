#![deny(unsafe_code)]

#[allow(unsafe_code)]
mod frb_generated;

pub mod api;
pub mod error;
pub mod identity;
pub mod state;

use once_cell::sync::OnceCell;
use std::sync::Mutex;

use openmls::prelude::Ciphersuite;

use crate::error::MlsError;
use crate::identity::MlsIdentity;

pub const CRIPTIVO_MLS_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

/// Глобален runtime — една identity на процес.
static IDENTITY: OnceCell<Mutex<Option<MlsIdentity>>> = OnceCell::new();

fn identity_slot() -> &'static Mutex<Option<MlsIdentity>> {
    IDENTITY.get_or_init(|| Mutex::new(None))
}

pub fn set_identity(id: MlsIdentity) -> Result<(), MlsError> {
    let mut guard = identity_slot()
        .lock()
        .map_err(|_| MlsError::Other("identity lock poisoned".into()))?;
    *guard = Some(id);
    Ok(())
}

pub fn with_identity<F, R>(f: F) -> Result<R, MlsError>
where
    F: FnOnce(&MlsIdentity) -> Result<R, MlsError>,
{
    let guard = identity_slot()
        .lock()
        .map_err(|_| MlsError::Other("identity lock poisoned".into()))?;
    let id = guard.as_ref().ok_or(MlsError::IdentityNotLoaded)?;
    f(id)
}

pub fn with_identity_mut<F, R>(f: F) -> Result<R, MlsError>
where
    F: FnOnce(&mut MlsIdentity) -> Result<R, MlsError>,
{
    let mut guard = identity_slot()
        .lock()
        .map_err(|_| MlsError::Other("identity lock poisoned".into()))?;
    let id = guard.as_mut().ok_or(MlsError::IdentityNotLoaded)?;
    f(id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::MlsIdentity;

    #[test]
    fn create_and_export_identity() {
        let id = MlsIdentity::create("alice-test").expect("create");
        assert_eq!(id.identity, "alice-test");

        let state_json = id.export_state().expect("export");
        assert!(state_json.contains("alice-test"));

        let restored = MlsIdentity::restore(&state_json).expect("restore");
        assert_eq!(restored.identity, "alice-test");
        assert_eq!(
            restored.public_signature_key_base64(),
            id.public_signature_key_base64()
        );
    }

    #[test]
    fn generate_multiple_key_packages() {
        let id = MlsIdentity::create("bob-test").expect("create");
        let kps = id.generate_key_packages(5).expect("kps");
        assert_eq!(kps.len(), 5);
        // Всички трябва да са различни
        let set: std::collections::HashSet<_> = kps.iter().collect();
        assert_eq!(set.len(), 5);
    }

    #[test]
    fn rejects_empty_identity() {
        assert!(MlsIdentity::create("   ").is_err());
    }

    #[test]
    fn restore_roundtrip_preserves_storage() {
        let id = MlsIdentity::create("roundtrip").expect("create");
        let _ = id.generate_key_packages(3).expect("kps");
        let json = id.export_state().expect("export");

        let restored = MlsIdentity::restore(&json).expect("restore");
        let kps2 = restored.generate_key_packages(2).expect("more kps");
        assert_eq!(kps2.len(), 2);
    }
}