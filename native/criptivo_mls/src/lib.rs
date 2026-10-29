
#![forbid(unsafe_code)]

/// Версия на native криптографския модул.
pub const CRIPTIVO_MLS_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Проверява, че native модулът може да бъде зареден.
///
/// Това НЕ означава, че MLS сесия е създадена,
/// че има криптирани съобщения или че E2EE е активно.
pub fn native_status() -> &'static str {
    "criptivo_mls_ready"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_module_reports_ready() {
        assert_eq!(native_status(), "criptivo_mls_ready");
    }

    #[test]
    fn package_version_is_not_empty() {
        assert!(!CRIPTIVO_MLS_VERSION.is_empty());
    }
}
