#!/usr/bin/env bash
# Wipe /dev/sda1 and create a new btrfs (same type as /Data). Destroys all data on that partition.
# NixOS is configured to mount this partition at /media by PARTUUID, so you do not need to
# change configuration.nix after reformat (only run nixos-rebuild if you changed the script).
set -euo pipefail

part=/dev/sda1
[[ -b "$part" ]] || { echo "Missing $part"; exit 1; }

echo "Target: $part  (SATA second disk, should be /media when mounted)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN,UUID,PARTUUID "$part" || true

read -r -p "This ERASES EVERYTHING on $part and makes a new btrfs. Type YES: " ans
[[ "$ans" == "YES" ]] || { echo "Aborted."; exit 1; }

sync
if findmnt "$part" &>/dev/null; then
  echo "Unmounting $part …"
  umount "$part" || { echo "Unmount failed (close programs using /media)."; exit 1; }
fi

echo "Creating btrfs …"
mkfs.btrfs -f -L media "$part"

echo "Done."
blkid "$part" || true
echo "Next: sudo mount /dev/disk/by-partuuid/f3805ff9-96b0-4326-ba8c-c271e17aec82 /media"
echo "      (or reboot — NixOS will mount /media automatically.)"
