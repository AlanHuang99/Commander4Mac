# Security

For a suspected vulnerability involving file loss, traversal, remote authentication, host verification or credential handling, use GitHub's **Security → Report a vulnerability** for this repository. Do not put credentials or exploitable private details in a public issue. For an ordinary bug, use the issue templates.

Include the app version, macOS version, protocol, reproduction using disposable data, expected behavior and impact. Redact private server names, paths, keys and credentials. We assess reports against the current published release and main branch; there is no guaranteed response deadline.

Release builds use Developer ID signing, hardened runtime, library validation and Apple notarization. SSH fingerprints require explicit trust; HTTPS WebDAV uses system certificate validation. Full Disk Access and Local Network grants belong to macOS and are granted by the user. Neither notarization nor those permissions guarantee a server or file is safe.
