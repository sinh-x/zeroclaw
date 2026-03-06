{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "sinh-x-zeroclaw";
  version = "0.2.0+sinh.1";

  src = lib.cleanSource ./.;

  cargoHash = "sha256-LaWcHkOAvqRW5S/Ay8SixzAKqwRdqo0gM021dqlG5SM=";

  nativeBuildInputs = [
    pkg-config
    git
  ];

  buildInputs = [
    openssl
  ];

  # build.rs reads git SHA — provide a fallback in the Nix sandbox
  ZEROCLAW_GIT_SHORT_SHA = "nix";

  # Many tests expect a writable $HOME (tilde expansion, config persistence, etc.)
  preCheck = ''
    export HOME="$(mktemp -d)"
  '';

  # Only build the main zeroclaw binary
  cargoBuildFlags = [ "--package" "zeroclaw" ];
  cargoTestFlags = [ "--package" "zeroclaw" ];

  meta = with lib; {
    description = "ZeroClaw autonomous agent runtime";
    mainProgram = "zeroclaw";
    license = with licenses; [ mit asl20 ];
  };
}
