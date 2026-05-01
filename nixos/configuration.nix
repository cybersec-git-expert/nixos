{ config, pkgs, ... }:
let
  unstable = import <nixos-unstable> { config = { allowUnfree = true; }; };
in
{
  imports = [ ./hardware-configuration.nix
    ./cursor.nix
    ./deepcool.nix ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.kernelPackages = pkgs.linuxPackages_6_6;  

  # Nvidia — load modules in initrd so they're ready before Hyprland
  # Also set resume= so hibernate/hybrid-sleep can restore from swap.
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
    "resume=UUID=ccca1d4a-bbf0-41e1-b330-0e74d0858318"
    # Default "deep" (S3) suspend often triggers nvidia-drm atomic commit failures on wake
    # (Hyprland dies → you see a TTY like "nixos login:" instead of hyprlock). s2idle is
    # shallower (still saves most power on desktop) but usually survives resume with the
    # proprietary NVIDIA stack. Remove this line if you need true S3 and accept the risk.
    "mem_sleep_default=s2idle"
  ];
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
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
    # NOTE: Hibernate resume currently fails with NVIDIA returning -5 during freeze
    # when PreserveVideoMemoryAllocations is enabled. Disable NVIDIA power management
    # to avoid enabling that path so hibernate can resume reliably.
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
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
    HibernateMode=platform shutdown
    HybridSleepMode=suspend platform shutdown
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
    htop btop fastfetch curl wget git unzip zip ripgrep fd bat eza
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

  # Swap (ext4 install — no btrfs)
  swapDevices = [ { device = "/dev/disk/by-uuid/ccca1d4a-bbf0-41e1-b330-0e74d0858318"; } ];
  boot.resumeDevice = "/dev/disk/by-uuid/ccca1d4a-bbf0-41e1-b330-0e74d0858318";
  

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  fileSystems."/Vault" = {
    device = "/dev/disk/by-uuid/f66e087b-a35f-45a6-9cdc-7887d82d0c78";
    fsType = "xfs";
    options = [ "defaults" "nofail" ];
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="9780cc9b-16d3-4987-808d-fbd4aace1fc3", ENV{UDISKS_IGNORE}="1"
  '';

  qt = { enable = true; };
  system.stateVersion = "24.11";



}
