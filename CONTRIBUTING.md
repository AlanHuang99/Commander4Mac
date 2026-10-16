# Contributing

Read the [development guide](docs/DEVELOPMENT.md), then open an issue or pull request with a focused change. Bug reports should include macOS/app versions, reproduction steps, expected and actual behavior, and whether the issue involves local files or a server. Remove credentials, server addresses and private file paths from attachments.

Use Swift 6 strict concurrency. Keep filesystem/network work off the main actor, preserve explicit transfer/conflict semantics, and keep credentials in Keychain or memory. Use owned temporary fixtures for tests. Never run destructive tests on a user's files or change system privacy databases.

Before submitting:

```sh
COMMANDER_CI=1 ./script/test.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 script/verify_licenses.py
```

Network and cross-volume fixtures are described in the development guide. Add a regression test when changing behavior. Describe which checks actually ran and any relevant unverified behavior. Do not include credentials, build products, local state or signing files in commits.

Contributions to original code are provided under the repository's GPLv3 license. Preserve upstream license text and patch provenance in `Vendor/Citadel`. Dependency updates must regenerate and verify the bundled notices and corresponding LGPL source before release. Retain the Niels Provos acknowledgement in materials mentioning the included software's features or use.
