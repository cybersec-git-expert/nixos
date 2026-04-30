{ config, pkgs, lib, ... }:

let
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

  # Restart after suspend/hibernate
  systemd.services.deepcool-resume = {
    description = "Restart DeepCool controller after system resume";
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    wantedBy = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart deepcool-cli.service";
    };
  };
}
