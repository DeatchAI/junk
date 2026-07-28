# Security policy

## Supported versions

Until the first public tagged release, security fixes are made on `main`. Once releases begin, the latest published major version is supported.

## Reporting a vulnerability

Do **not** open a public issue for a suspected vulnerability.

Use GitHub's **Private Vulnerability Reporting** for this repository. Include:

- a concise description and affected component;
- reproduction steps or a proof of concept;
- the potential impact; and
- any suggested mitigation.

If private reporting has not yet been enabled, contact a repository maintainer privately through their GitHub profile and do not disclose exploit details publicly.

We will acknowledge a good-faith report, investigate it privately, prepare a fix, and publish a security advisory when users need to take action.

## Sensitive areas

Extra care is required when changing:

- Accessibility, Screen Recording, Apple Events, Finder, keyboard, or mouse automation;
- local HTTP/WebSocket and native-messaging bridges;
- Chrome extension permissions and page automation;
- Keychain, credentials, secret storage, or redaction; and
- release signing, notarization, Sparkle, or update publishing.

Never include credentials, decrypted user data, or real browser/session data in an issue, test fixture, log, or pull request.
