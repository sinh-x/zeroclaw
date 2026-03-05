# sinh-x Fork Release Runbook

Local release process for the sinh-x fork of ZeroClaw. This fork publishes a **bare binary** to GitHub Releases and updates `package.nix` to fetch it via `fetchurl`.

Last verified: **March 5, 2026**.

## Overview

The sinh-x fork uses Nix packaging (`package.nix`) that fetches a pre-built binary from GitHub Releases. The automated script handles the full cycle:

1. Read version from `Cargo.toml`
2. Build the binary (`cargo build --profile release-fast --locked`)
3. Create a GitHub Release with the binary attached
4. Compute the Nix SRI hash and update `package.nix` in-place
5. Print next steps for verification

## Prerequisites

| Tool | Purpose |
|---|---|
| `cargo` / `rustc` | Build the binary |
| `gh` | Create GitHub Release and upload artifact |
| `nix` | Compute SRI hash for `package.nix` |
| `git` | Tag and repo validation |

Ensure `gh auth status` reports authenticated before running.

## Quick Start

```bash
# Dry run — preview what would happen
./scripts/release/publish_sinh_release.sh --dry-run

# Full release
./scripts/release/publish_sinh_release.sh

# Then commit the package.nix update
git add package.nix
git commit -m "chore(nix): bump package.nix to vX.Y.Z"
```

## Script Reference

**Location:** `scripts/release/publish_sinh_release.sh`

### Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Show what would happen without creating a release or modifying files |
| `--skip-build` | Reuse existing binary at the expected path (skip `cargo build`) |
| `--draft` | Create the GitHub Release as a draft |
| `-h`, `--help` | Show usage |

### What the script does

```
extract_version   → parse version from Cargo.toml
validate_prereqs  → check git repo, gh auth, nix, tag doesn't exist
build_binary      → cargo build --profile release-fast --locked
create_release    → gh release create with bare binary upload
update_package_nix → compute SRI hash, update version/url/hash in package.nix
print_summary     → show results and next steps
```

### Key conventions

- **Tag format:** `v<cargo_version>` (e.g., `v0.2.0+sinh.1`)
- **Build profile:** `release-fast` (inherits `release`: `opt-level = "z"`, LTO, strip, single codegen unit)
- **Binary upload:** bare binary, not a tar.gz archive
- **URL encoding:** `+` is encoded as `%2B` in the Nix `fetchurl` URL
- **Hash format:** Nix SRI (`sha256-...=`)
- **Repo detection:** automatic via `gh repo view`
- **Target triple:** detected via `rustc -vV`

## Post-Release Verification

After the script completes and `package.nix` is updated:

```bash
# 1. Review the changes
git diff package.nix

# 2. Build with Nix to verify the hash and URL are correct
nix build .#

# 3. Verify the built binary
./result/bin/zeroclaw --version

# 4. Commit and push
git add package.nix
git commit -m "chore(nix): bump package.nix to <new-version>"
git push
```

## Version Lifecycle

1. **Bump version** in `Cargo.toml` (e.g., `0.2.0+sinh.1` → `0.2.0+sinh.2`)
2. **Commit** the version bump
3. **Run** `publish_sinh_release.sh`
4. **Commit** the resulting `package.nix` update
5. **Push** both commits

## Troubleshooting

| Problem | Solution |
|---|---|
| `Tag already exists on remote` | The version in `Cargo.toml` was already released. Bump the version first. |
| `gh is not authenticated` | Run `gh auth login` |
| `Binary not found` with `--skip-build` | Build first with `cargo build --profile release-fast --locked` |
| `nix hash` fails | Ensure `nix` is available and the binary path exists |
| `package.nix` URL mismatch after release | Verify the repo detected by `gh repo view` matches your fork |

## Relationship to Upstream Release Process

The upstream release process (documented in [../release-process.md](../release-process.md)) uses CI-driven multi-target builds, SBOMs, cosign signatures, and artifact contracts. The sinh-x fork release is a simpler local workflow for single-target binary distribution via Nix.
