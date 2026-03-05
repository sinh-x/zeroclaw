#!/usr/bin/env bash
set -euo pipefail

# publish_sinh_release.sh — Automates the sinh-x fork release cycle:
# build binary → create GitHub Release → update package.nix hash/URL.

###############################################################################
# Defaults
###############################################################################
DRY_RUN="false"
SKIP_BUILD="false"
DRAFT=""

###############################################################################
# Usage
###############################################################################
usage() {
  cat <<'USAGE'
Usage: scripts/release/publish_sinh_release.sh [OPTIONS]

Build, release, and update package.nix for the sinh-x fork.

Options:
  --dry-run      Show what would happen without creating a release or modifying files
  --skip-build   Reuse existing binary (skip cargo build)
  --draft        Create the GitHub release as a draft
  -h, --help     Show this help message
USAGE
}

###############################################################################
# Helpers
###############################################################################
info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()   { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

###############################################################################
# Parse args
###############################################################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)    DRY_RUN="true"; shift ;;
      --skip-build) SKIP_BUILD="true"; shift ;;
      --draft)      DRAFT="--draft"; shift ;;
      -h|--help)    usage; exit 0 ;;
      *)            die "Unknown option: $1" ;;
    esac
  done
}

###############################################################################
# Extract version from Cargo.toml
###############################################################################
extract_version() {
  VERSION=$(grep -m1 '^version' Cargo.toml | sed 's/version *= *"\(.*\)"/\1/')
  [[ -n "$VERSION" ]] || die "Could not parse version from Cargo.toml"
  TAG="v${VERSION}"
  info "Version: $VERSION  Tag: $TAG"
}

###############################################################################
# Validate prerequisites
###############################################################################
validate_prereqs() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "Not inside a git repository"

  command -v gh  >/dev/null 2>&1 || die "'gh' CLI not found"
  command -v nix >/dev/null 2>&1 || die "'nix' CLI not found"

  gh auth status >/dev/null 2>&1 || die "'gh' is not authenticated"

  REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
  [[ -n "$REPO" ]] || die "Could not determine GitHub repo"
  info "Repo: $REPO"

  if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    die "Tag $TAG already exists on remote"
  fi
}

###############################################################################
# Build binary
###############################################################################
build_binary() {
  TARGET=$(rustc -vV | grep '^host:' | awk '{print $2}')
  # cargo puts output in target/release-fast/ (no triple) unless --target is passed
  BINARY_PATH="target/release-fast/zeroclaw"

  if [[ "$SKIP_BUILD" == "true" ]]; then
    info "Skipping build (--skip-build)"
    [[ -f "$BINARY_PATH" ]] || die "Binary not found at $BINARY_PATH"
  else
    info "Building zeroclaw (profile: release-fast, target: $TARGET)"
    cargo build --profile release-fast --locked
  fi

  [[ -x "$BINARY_PATH" ]] || die "Binary not executable at $BINARY_PATH"

  BUILT_VERSION=$("$BINARY_PATH" --version 2>&1 || true)
  info "Binary version: $BUILT_VERSION"
}

###############################################################################
# Create GitHub release
###############################################################################
create_release() {
  RELEASE_URL="https://github.com/${REPO}/releases/download/${TAG}/zeroclaw"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would create release $TAG and upload $BINARY_PATH"
    info "[DRY RUN] Release URL: $RELEASE_URL"
    return
  fi

  info "Creating GitHub release: $TAG"
  # shellcheck disable=SC2086
  gh release create "$TAG" "$BINARY_PATH" \
    --title "zeroclaw $TAG" \
    --notes "Release zeroclaw $TAG" \
    $DRAFT

  info "Release created: https://github.com/${REPO}/releases/tag/${TAG}"
}

###############################################################################
# Update package.nix
###############################################################################
update_package_nix() {
  local nix_file="package.nix"
  [[ -f "$nix_file" ]] || die "package.nix not found"

  if [[ "$DRY_RUN" == "true" ]]; then
    local dry_hash
    dry_hash=$(nix hash file --sri --type sha256 "$BINARY_PATH")
    local url_tag="${TAG//+/%2B}"
    local dry_url="https://github.com/${REPO}/releases/download/${url_tag}/zeroclaw"
    info "[DRY RUN] Would update package.nix:"
    info "  version = \"$VERSION\""
    info "  url     = \"$dry_url\""
    info "  hash    = \"$dry_hash\""
    return
  fi

  info "Computing SRI hash of binary"
  local sri_hash
  sri_hash=$(nix hash file --sri --type sha256 "$BINARY_PATH")
  info "Hash: $sri_hash"

  # Encode + as %2B for the Nix fetchurl URL
  local url_tag="${TAG//+/%2B}"
  local new_url="https://github.com/${REPO}/releases/download/${url_tag}/zeroclaw"

  info "Updating $nix_file"
  # Replace version line
  sed -i "s|version = \".*\";|version = \"${VERSION}\";|" "$nix_file"
  # Replace url line
  sed -i "s|url = \".*\";|url = \"${new_url}\";|" "$nix_file"
  # Replace hash line
  sed -i "s|hash = \".*\";|hash = \"${sri_hash}\";|" "$nix_file"

  info "package.nix updated"
}

###############################################################################
# Summary
###############################################################################
print_summary() {
  echo
  info "Release summary"
  echo "  Tag:     $TAG"
  echo "  Version: $VERSION"
  echo "  Repo:    $REPO"
  echo "  Binary:  $BINARY_PATH"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo
    info "Dry run complete — no changes were made"
  else
    echo
    info "Next steps:"
    echo "  1. Verify package.nix changes: git diff package.nix"
    echo "  2. Test Nix build:             nix build .#"
    echo "  3. Verify binary:              ./result/bin/zeroclaw --version"
    echo "  4. Commit and push package.nix update"
  fi
}

###############################################################################
# Main
###############################################################################
main() {
  parse_args "$@"
  extract_version
  validate_prereqs
  build_binary
  create_release
  update_package_nix
  print_summary
}

main "$@"
