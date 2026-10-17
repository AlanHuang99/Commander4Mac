# Saved connections quick access

## Intent and approach

Make saving and reusing SFTP, SMB and WebDAV connections obvious. Existing ConnectionStore, CredentialVault and transactional ConnectionProfileCommit already persist profiles and optional credentials safely; reuse them rather than introduce another catalog. Full user authorization covers inline implementation.

The connection sheet adds a saved-connection chooser and a clearly labeled new-connection action. Selecting an existing profile loads its non-secret settings, clears transient credential/error state, and retains the profile identity. A blank credential continues to use Keychain. Show protocol/endpoint alongside saved names so duplicate names remain distinguishable. The primary action reads Save and Connect, and Save Connection saves without any network connection. Persisted connections remain one click away in the sidebar after relaunch, with current/left/right destinations and editing/removal through existing actions. Sidebar labels identify saved connections and protocol without exposing passwords.

Switching a profile must not accidentally reset its port/path/authentication through protocol-change callbacks, save a secret under another identity, duplicate a profile or auto-connect on launch. Cancel never writes an unsubmitted edit. Connection retries preserve the committed profile identity and existing host-key verification.

## Verification

Add real UI acceptance for creating an owned synthetic profile with Save Connection, relaunching, selecting it, loading its endpoint and removing it. Test switching protocol/profile state without credential crossover. Existing store/commit/credential migration tests and core suite remain green. Use only owned loopback/synthetic endpoints, never the user's saved credentials or real servers for destructive tests.
