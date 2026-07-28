# Contributing to Detach

Thanks for improving Detach. Small, focused pull requests are easiest to review and release.

## Before you start

1. Search existing issues and discussions.
2. Open an issue for substantial changes so the approach can be agreed before implementation.
3. Fork the repository, create a branch, and keep unrelated formatting or refactors out of the pull request.

## Local checks

Run the relevant checks before opening a pull request:

```bash
bash scripts/verify.sh
```

The website is intentionally a Git submodule hosted in a separate personal account. Website-only changes should be contributed to that repository; this repository should update the submodule pointer only after that change is merged.

## Pull request expectations

- Explain the user-visible outcome and how you verified it.
- Add or update tests when changing runtime, browser, or capability behavior.
- Preserve explicit user approval for sensitive operations.
- Do not include secrets, production credentials, personal data, generated binaries, release artifacts, or benchmark run data.
- Keep documentation current when changing installation, permissions, or release behavior.

By contributing, you agree that your contribution is licensed under the Apache License 2.0.
