{ lib, stdenvNoCC, fetchFromGitHub, python3, makeWrapper }:

let
  pyEnv = python3.withPackages (ps: with ps; [
    beautifulsoup4
    requests
    clint
  ]);
  rev = "123c69e150e246c2b253792ca9ec66e4bab144b5";
  src = fetchFromGitHub {
    owner = "anburocky3";
    repo = "tamil-mp3-downloader";
    inherit rev;
    sha256 = "1icpxijlaqfr658a5599w1g3kba7vdb0ihbibp0wijwfmzr5zgja";
  };
in
stdenvNoCC.mkDerivation {
  pname = "tamil-mp3-downloader";
  version = "2.0+git";
  inherit src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    app="$out/opt/tamil-mp3-downloader"
    mkdir -p "$app"
    cp -r . "$app/"
    mkdir -p "$out/bin"
    makeWrapper ${pyEnv}/bin/python3 "$out/bin/tamil-mp3-downloader" \
      --add-flags "$app/main.py" \
      --run "cd \"$app\""
    runHook postInstall
  '';

  meta = {
    description = "CLI to browse/download Tamil MP3 collections (upstream project; educational use)";
    homepage = "https://github.com/anburocky3/tamil-mp3-downloader";
    license = lib.licenses.mit;
    mainProgram = "tamil-mp3-downloader";
  };
}
