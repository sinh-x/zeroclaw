{
  stdenv,
  lib,
  autoPatchelfHook,
}:
stdenv.mkDerivation {
  pname = "sinh-x-zeroclaw";
  version = "0.2.0";

  src = ./target/release;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    install -Dm755 $src/zeroclaw $out/bin/zeroclaw
  '';

  meta = with lib; {
    description = "ZeroClaw autonomous agent runtime";
    mainProgram = "zeroclaw";
  };
}
