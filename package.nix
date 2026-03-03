{
  stdenv,
  lib,
  autoPatchelfHook,
  fetchurl,
}:
stdenv.mkDerivation {
  pname = "sinh-x-zeroclaw";
  version = "0.2.0";

  src = fetchurl {
    url = "https://github.com/sinh-x/zeroclaw/releases/download/v0.2.0/zeroclaw";
    hash = "sha256-eDnlZtNVJ1C73SHogDrDlLmnKa/WKujOzdJo4ck5LFA=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    install -Dm755 $src $out/bin/zeroclaw
  '';

  meta = with lib; {
    description = "ZeroClaw autonomous agent runtime";
    mainProgram = "zeroclaw";
  };
}
