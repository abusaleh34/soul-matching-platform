/// Versioned consent gate. Bump [kCurrentConsentVersion] whenever the consent
/// text (`legal/consent_vN_ar.md`) changes materially — users on an older
/// version are then routed back through the consent screen before anything else.
const int kCurrentConsentVersion = 1;

/// True when the user must (re)consent: they have never consented, or their
/// stored version is older than the current one. A newer stored version never
/// prompts (defensive).
bool needsConsent(int? storedVersion) => (storedVersion ?? 0) < kCurrentConsentVersion;
