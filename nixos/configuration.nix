{ config, pkgs, ... }:
let
  unstable = import <nixos-unstable> { config = { allowUnfree = true; }; };

  # systemd-sleep runs as root: hyprctl / systemctl --user need the *graphical user's*
  # runtime dir + D-Bus + Hyprland instance id, or they no-op and resume looks "frozen".
  hyprResumeInner = pkgs.writeText "hypr-resume-inner.sh" ''
    #!/usr/bin/env bash
    set -euo pipefail
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=''${XDG_RUNTIME_DIR}/bus"
    if [[ -d "''${XDG_RUNTIME_DIR}/hypr" ]]; then
      for d in "''${XDG_RUNTIME_DIR}"/hypr/*; do
        [[ -d "$d" ]] || continue
        export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$d")"
        break
      done
    fi
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
    export PATH="/run/current-system/sw/bin''${PATH:+:$PATH}"

    # Long S3 / hibernate: DRM stack sometimes needs a hard DPMS cycle, not only "on".
    /run/current-system/sw/bin/hyprctl dispatch dpms on >/dev/null 2>&1 || true
    sleep 0.4
    /run/current-system/sw/bin/hyprctl dispatch dpms off >/dev/null 2>&1 || true
    sleep 0.6
    /run/current-system/sw/bin/hyprctl dispatch dpms on >/dev/null 2>&1 || true
    sleep 0.3
    /run/current-system/sw/bin/hyprctl dispatch dpms on >/dev/null 2>&1 || true

    /run/current-system/sw/bin/systemctl --user restart xdg-desktop-portal-hyprland.service >/dev/null 2>&1 || true
    /run/current-system/sw/bin/systemctl --user restart xdg-desktop-portal.service >/dev/null 2>&1 || true

    # swww / mpvpaper lose the Wayland surface after sleep; wallpaper stays black until reboot
    # unless we re-apply from ~/.config/wallpaper-manager/current_wallpaper.txt.
    if [[ -x "$HOME/.config/hypr/scripts/wallpaper-manager.sh" ]]; then
      sleep 0.5
      "$HOME/.config/hypr/scripts/wallpaper-manager.sh" init >/dev/null 2>&1 || true
    fi
  '';

  hyprResumeRecover = pkgs.writeShellScript "99-hypr-resume-recover.sh" ''
    set -euo pipefail
    case "''${1:-}" in post) ;; *) exit 0 ;; esac
    # After many hours in sleep, USB + GPU can take noticeably longer to come back.
    sleep 3
    runuser -u cyberexpert -- ${pkgs.bash}/bin/bash ${hyprResumeInner}
  '';
in
{
  imports = [ ./hardware-configuration.nix
    ./cursor.nix
    ./deepcool.nix ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  # Bootloader — only keep the newest N generations in the boot menu (and on /boot).
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 4;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.kernelPackages = pkgs.linuxPackages_6_6;  

  # Nvidia: keep modeset/fbdev on the real kernel; do **not** load NVIDIA in initrd.
  # Loading nvidia_drm in stage-1 before `resume=` runs can leave the GPU half-initialized so
  # hibernate **resume** fails after the image is fully loaded (`pci_pm_freeze … -5`, then
  # "Failed to load image, recovering" → looks like a fresh boot). Hyprland still gets the
  # driver after switch-root. If your LUKS prompt needs a framebuffer, you still have EFI fb.
  # Also set resume= so hibernate/hybrid-sleep can restore from swap.
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
    "resume=UUID=ccca1d4a-bbf0-41e1-b330-0e74d0858318"
    # Long suspend: hubs / wireless dongles / some keyboards stop responding after deep S3
    # unless USB autosuspend is disabled (looks like a full freeze if pointer won't move).
    "usbcore.autosuspend=-1"
    # Long suspend + discrete NVIDIA: link power management can leave the GPU in a bad state
    # on resume (flip timeouts / dead compositor). Trades a bit of idle power for stability.
    "pcie_aspm=off"
    # Do NOT force mem_sleep_default=s2idle here: s2idle keeps most of the platform powered,
    # so AIO/pump/fan headers often stay alive and fans keep spinning. True S3 ("deep") is
    # what actually powered your cooler off before. If NVIDIA resume breaks again (TTY /
    # nv_drm_atomic_commit errors), add back: "mem_sleep_default=s2idle" as a tradeoff.
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "usbhid" "hid_generic" "evdev" "xhci_hcd" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];

  # GPU
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    # VRAM save/restore + nvidia-suspend/nvidia-resume (systemd). Needed for many
    # proprietary-driver setups so monitors come back after S3 (deep) sleep.
    #
    # PreserveVideoMemoryAllocations + nvidia-suspend/hibernate/resume services.
    # Hibernate needs nvidia-hibernate.service (nvidia-sleep.sh hibernate): without it,
    # pci_pm_freeze on the GPU returns -5 and hibernate aborts (screen freezes, then
    # nothing). Resume-from-hibernate can still fail on some setups; then prefer sleep.
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # After suspend/hibernate, NVIDIA DRM sometimes resumes with broken modesets; Hyprland
  # then looks frozen (no pointer / can't type into a locker). Run recovery as the seat user.
  environment.etc."systemd/system-sleep/99-hypr-resume-recover.sh" = {
    source = hyprResumeRecover;
    mode = "0755";
  };

  # Input
  services.libinput.enable = true;

  # Network
  hardware.enableRedistributableFirmware = true;
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Time / Locale
  time.timeZone = "Asia/Colombo";
  i18n.defaultLocale = "en_US.UTF-8";

  # User
  users.users.cyberexpert = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "seat" "lp" "scanner" "plugdev" "docker" ];
    shell = pkgs.zsh;
  };

  virtualisation.docker.enable = true;

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    enableTCPIP = true;
    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE  USER  ADDRESS          METHOD
      local   all       all                    trust
      host    all       all   127.0.0.1/32     trust
      host    all       all   ::1/128          trust
    '';
  };

  services.redis.servers."" = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  # Shell & Git
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };
  programs.git.enable = true;
  # nix-ld: allow running unpatched dynamic binaries (Android SDK, adb, sdkmanager, etc.)
  programs.nix-ld.enable = true;

  # Security
  security.sudo.wheelNeedsPassword = true;
  security.polkit.enable = true;
  # loginctl / systemctl suspend+hibernate from the graphical session must be allowed without
  # an interactive prompt; `sudo systemctl hibernate` runs as root and often freezes then
  # aborts because it is not tied to your seat/session the same way.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (!subject.local || !subject.isInGroup("wheel")) return;
      if (action.id == "org.freedesktop.login1.hibernate" ||
          action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
          action.id == "org.freedesktop.login1.suspend" ||
          action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
          action.id == "org.freedesktop.login1.power-off" ||
          action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
          action.id == "org.freedesktop.login1.reboot" ||
          action.id == "org.freedesktop.login1.reboot-multiple-sessions") {
        return polkit.Result.YES;
      }
    });
  '';
  security.rtkit.enable = true;

  # Hibernate / hybrid-sleep — allow wheel users without extra password prompt
  security.sudo.extraRules = [{
    groups = [ "wheel" ];
    commands = [
      { command = "/run/current-system/sw/bin/systemctl hibernate"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl hybrid-sleep"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl suspend"; options = [ "NOPASSWD" ]; }
    ];
  }];

  # Enable hibernate and hybrid-sleep targets
  systemd.sleep.extraConfig = ''
    # Use platform (ACPI S4) only; "shutdown" as a fallback writes a different /sys/power/disk
    # path and can end up powering off like a cold boot instead of resuming from swap.
    HibernateMode=platform
  '';

  # greetd — text login screen, launches Hyprland directly (no compositor conflict)
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
      user = "greeter";
    };
  };

  # Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Nvidia Wayland env vars — must be set system-wide so greetd + Hyprland see them
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";
    WLR_NO_HARDWARE_CURSORS = "1";
    LIBSEAT_BACKEND = "logind";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_STYLE_OVERRIDE = "Fusion";
    XDG_SESSION_TYPE = "wayland";
    # Android SDK
    ANDROID_HOME = "/home/cyberexpert/sdk/android";
    ANDROID_SDK_ROOT = "/home/cyberexpert/sdk/android";
    # Flutter / Dart pub cache
    PUB_CACHE = "/home/cyberexpert/sdk/pub-cache";
    # Node.js global packages
    npm_config_prefix = "/home/cyberexpert/sdk/node";
    # Java (required for Android builds)
    JAVA_HOME = "${pkgs.jdk17}";
    # Android Studio — point to system JDK so it can determine bundled Java version
    STUDIO_JDK = "${pkgs.jdk17}";
    # Flutter web — use Brave as Chrome
    CHROME_EXECUTABLE = "brave";
  };

  # Audio
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # Printing — CUPS with Epson L130 driver
  services.printing = {
    enable = true;
    drivers = [ pkgs.epson-escpr pkgs.epson-escpr2 pkgs.epson-201401w ];
  };
  # Avahi — network printer/service discovery (needed for CUPS auto-detect)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Packages — only what was requested
  environment.systemPackages = with pkgs; [
    # Polkit agent (needed for Dolphin LUKS unlock popup)
    # Browser & apps
    brave unstable.vscode kdePackages.dolphin kitty firefox obsidian spotify telegram-desktop
    # Hyprland bar / launcher / notifications
    rofi-wayland
    # Hyprland extras
    hyprpaper hyprlock hypridle wlogout swww
    # Wayland tools
    wl-clipboard grim slurp swappy brightnessctl playerctl
    # Network / tray
    networkmanagerapplet xdg-utils xdg-user-dirs
    # Quickshell + deps
    matugen imagemagick mpvpaper pulseaudio dunst libnotify cryptsetup gptfdisk
    inotify-tools pamixer swayosd udiskie cliphist socat jq
    python3 dbus playerctl mpd mpc ncmpcpp cava
    python3Packages.pip
    pipx
    # Filesystem tools
    xfsprogs
    # CLI essentials
    htop btop fastfetch curl wget git unzip zip ripgrep fd bat eza awscli2
    # Audio control
    pavucontrol
    # Editors
    gedit
    # Polkit agent (needed for LUKS unlock popup in Dolphin)
    # Themes
    papirus-icon-theme kdePackages.qtsvg
    bibata-cursors
    hyprpolkitagent
    # Development — Node.js
    nodejs_22
    nodePackages.pnpm
    # Development — Dart & Flutter
    flutter
    dart
    # Development — Android
    unstable.android-studio
    android-tools
    jdk17
    gradle
    # Development — Build tools
    gcc
    gnumake
    chromium
    # Development — Database GUI
    pgadmin4-desktopmode
    # Shell
    starship
    # Productivity
    qbittorrent
    qalculate-qt
    libreoffice-fresh
    thunderbird
  ];

  # Fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts =
  [ "JetBrainsMono" ]; })  
    noto-fonts
  ];

  # XDG Portal (needed for screen sharing, file pickers)
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
  };

  # Swap + resume: partition is already in hardware-configuration.nix (do not duplicate
  # swapDevices — two identical entries can break hibernate / swapon at boot).
  boot.resumeDevice = "/dev/disk/by-uuid/ccca1d4a-bbf0-41e1-b330-0e74d0858318";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  fileSystems."/Vault" = {
    device = "/dev/disk/by-uuid/f66e087b-a35f-45a6-9cdc-7887d82d0c78";
    fsType = "xfs";
    options = [ "defaults" "nofail" ];
  };

  # Second SSD: SATA sda1 at /media — same stack as /Vault (xfs + defaults + nofail).
  # Mount by PARTUUID so mkfs.xfs (new FS UUID) does not require editing this file.
  fileSystems."/media" = {
    device = "/dev/disk/by-partuuid/f3805ff9-96b0-4326-ba8c-c271e17aec82";
    fsType = "xfs";
    options = [ "defaults" "nofail" ];
  };

  # New XFS root is root:root — without this, Dolphin shows “lock” and you cannot mkdir/rm.
  systemd.services.media-owner-fix = {
    description = "chown /media to cyberexpert after mount";
    wantedBy = [ "multi-user.target" ];
    after = [ "media.mount" "local-fs.target" ];
    wants = [ "media.mount" ];
    unitConfig.ConditionPathIsMountPoint = "/media";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/chown cyberexpert:users /media";
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="9780cc9b-16d3-4987-808d-fbd4aace1fc3", ENV{UDISKS_IGNORE}="1"
  '';

  qt = { enable = true; };
  system.stateVersion = "24.11";



}
