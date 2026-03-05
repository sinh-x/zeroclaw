{
  stdenv,
  lib,
  autoPatchelfHook,
  fetchurl,
}:
stdenv.mkDerivation {
  pname = "sinh-x-zeroclaw";
  version = "0.2.0+sinh.1";

  src = fetchurl {
    url = "https://github.com/sinh-x/zeroclaw/releases/download/v0.2.0%2Bsinh.1/zeroclaw";
    hash = "sha256-BmORs+8GDRrxMa20s5zjFVPJuF5wDL3ls+jsCkD+iXQ=";
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
