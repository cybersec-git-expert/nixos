# NixOS configuration

This repository tracks only the **necessary NixOS configuration** from my `~/.config`, under `./nixos`.

## Layout

- `nixos/configuration.nix`: Main system configuration
- `nixos/hardware-configuration.nix`: Generated hardware config
- `nixos/cursor.nix`, `nixos/deepcool.nix`: Host-specific modules

## Apply

On the machine:

```bash
sudo ln -sf "$(pwd)/nixos/configuration.nix" /etc/nixos/configuration.nix
sudo ln -sf "$(pwd)/nixos/hardware-configuration.nix" /etc/nixos/hardware-configuration.nix
sudo nixos-rebuild switch
```

