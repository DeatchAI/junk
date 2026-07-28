# GitHub setup before making Detach public

These settings live in GitHub, not in source code. Complete them after the first CI run has appeared on the repository.

## 1. Turn on collaboration features

In **Settings → General → Features**, enable Issues and Discussions. In **Settings → Code security and analysis**, enable Dependabot alerts, Dependabot security updates, secret scanning, and push protection. Enable **Private vulnerability reporting** in the repository security settings.

## 2. Protect `main`

In **Settings → Rules → Rulesets**, create a ruleset for `main`:

- require a pull request before merging;
- require one approval when another maintainer is available;
- require conversations to be resolved;
- block force pushes and branch deletion;
- apply the rule to administrators; and
- require these checks after their first successful run: `Runtime checks`, `macOS build`, `Website checks`, `Dependency review`, and `Analyze Swift and TypeScript`.

Add a `CODEOWNERS` file once the canonical GitHub maintainer account is final. Do not add a guessed owner name: an incorrect owner can block every pull request.

## 3. Configure production releases

Create a GitHub Environment named `release`. Add the release secrets listed in [app/SPARKLE_RELEASE.md](../app/SPARKLE_RELEASE.md), limit the environment to protected `v*` tags, and require a maintainer review before it can publish.

The release workflow is intentionally separate from ordinary pull-request CI. It is the only workflow that receives signing, notarization, Sparkle, and update-publishing credentials.

## 4. Keep the website separate

The `web` directory is a Git submodule because its Vercel project must remain attached to your personal GitHub account. Keep its own Vercel project connected to the website repository. When website changes are ready:

1. Commit and push them inside `web` to the personal-account repository.
2. Update the submodule pointer in this repository in a separate pull request.

The parent CI checks the pinned website revision, while the website repository must keep its own branch rules, security settings, license, and dependency automation before it is made public.
