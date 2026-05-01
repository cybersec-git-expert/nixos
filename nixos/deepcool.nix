{ config, pkgs, lib, ... }:

let
  # Stop LCD/USB polling during suspend so the AIO can idle (s2idle keeps USB power;
  # a running deepcool-cli session can keep the device from powering down like S3 would).
  deepcoolSleepHook = pkgs.writeShellScript "50-deepcool-sleep" ''
    set -euo pipefail
    case "''${1:-}" in
      pre)
        /run/current-system/sw/bin/systemctl stop deepcool-cli.service 2>/dev/null || true
        ;;
      post)
        /run/current-system/sw/bin/systemctl start deepcool-cli.service 2>/dev/null || true
        ;;
    esac
  '';

  deepcool-cli = pkgs.stdenv.mkDerivation {
    pname = "deepcool-cli";
    version = "1.0.0";
    src = /Vault/Projects/DeepCool;

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      qt6.wrapQtAppsHook
    ];

    buildInputs = with pkgs; [
      qt6.qtbase
      libusb1
      systemd # provides libudev
    ];

    cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

    meta = {
      description = "CLI tool for DeepCool MYSTIQUE 360 AIO cooler LCD display";
      mainProgram = "deepcool-cli";
    };
  };
in
{
  environment.systemPackages = [ deepcool-cli ];

  # plugdev group for udev rules
  users.groups.plugdev = {};

  environment.etc."systemd/system-sleep/50-deepcool.sh" = {
    source = deepcoolSleepHook;
    mode = "0755";
  };

  # udev rules — non-root HID/USB access for all DeepCool devices
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb",    ATTR{idVendor}=="3633",  MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0001", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0002", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0003", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0004", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0005", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0006", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0007", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0008", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0009", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb",    ATTR{idVendor}=="3633",  ATTR{idProduct}=="0009",  MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="000a", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="000c", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="000d", MODE="0666", GROUP="plugdev"
  '';

  # Main controller service
  systemd.services.deepcool-cli = {
    description = "DeepCool Digital Controller";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${deepcool-cli}/bin/deepcool-cli --mode cpu --interval 1000";
      Restart = "always";
      RestartSec = 5;
      User = "root";
      Environment = "QT_QPA_PLATFORM=offscreen";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "deepcool-cli";
    };
  };
}
