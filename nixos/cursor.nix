{ pkgs, ... }:

let
  cursor = pkgs.stdenv.mkDerivation {
    pname = "cursor";
    version = "3.2.11";

    src = /nix/store/d8xrzv079wvjixvzxgm315gnjb2np7i9-cursor_3.2.11_amd64.deb;

    nativeBuildInputs = [ pkgs.dpkg pkgs.makeWrapper pkgs.autoPatchelfHook ];

    buildInputs = with pkgs; [
      glib gtk3 nss nspr atk cups libdrm expat
      xorg.libxcb xorg.libX11 xorg.libXcomposite xorg.libXdamage xorg.libXext
      xorg.libXfixes xorg.libXrandr xorg.libxkbfile
      mesa alsa-lib pango cairo libGL systemd
    ];

    unpackPhase = ''
      mkdir -p $out
      dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner -C $out
      mv $out/usr/* $out/ 2>/dev/null || true
      rmdir $out/usr 2>/dev/null || true
    '';

    installPhase = ''
      chmod +x $out/share/cursor/cursor
      chmod 755 $out/share/cursor/chrome-sandbox 2>/dev/null || true

      mkdir -p $out/bin
      makeWrapper $out/share/cursor/cursor $out/bin/cursor \
        --prefix LD_LIBRARY_PATH : "$out/share/cursor:${pkgs.lib.makeLibraryPath [
          pkgs.glib pkgs.gtk3 pkgs.nss pkgs.nspr pkgs.atk pkgs.cups
          pkgs.libdrm pkgs.expat pkgs.xorg.libxcb pkgs.xorg.libX11
          pkgs.xorg.libXcomposite pkgs.xorg.libXdamage pkgs.xorg.libXext
          pkgs.xorg.libXfixes pkgs.xorg.libXrandr pkgs.xorg.libxkbfile
          pkgs.mesa pkgs.alsa-lib pkgs.pango pkgs.cairo pkgs.libGL pkgs.systemd
        ]}" \
        --add-flags "--no-sandbox"

      # Desktop entry
      mkdir -p $out/share/applications
      cp $out/share/applications/cursor.desktop $out/share/applications/ 2>/dev/null || true
    '';

    meta = {
      description = "Cursor AI Code Editor";
      homepage = "https://cursor.sh";
      license = pkgs.lib.licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ cursor ];
}
