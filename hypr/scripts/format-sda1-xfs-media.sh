#!/usr/bin/env bash
# Wipe /dev/sda1 completely and create XFS like /Vault (label: media, mount: /media via PARTUUID).
# Destroys all data on that partition. Run: sudo ./format-sda1-xfs-media.sh
set -euo pipefail

part=/dev/sda1
[[ -b "$part" ]] || { echo "Missing $part"; exit 1; }

echo "Target: $part  (second SATA disk → will be XFS, mounted at /media)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN,UUID,PARTUUID "$part" || true

read -r -p "This ERASES EVERYTHING on $part and creates XFS (same kind as /Vault). Type YES: " ans
[[ "$ans" == "YES" ]] || { echo "Aborted."; exit 1; }

sync
if findmnt "$part" &>/dev/null; then
  echo "Unmounting $part …"
  umount "$part" || { echo "Unmount failed (close programs using /media)."; exit 1; }
fi

echo "Clearing old signatures (btrfs/extfat/…) …"
wipefs -a "$part"

echo "Creating XFS (label: media) …"
mkfs.xfs -f -L media "$part"

echo "Done."
blkid "$part" || true
echo "Run: sudo nixos-rebuild switch   (if you have not pulled the xfs /media config yet)"
echo "Then: sudo mount /dev/disk/by-partuuid/f3805ff9-96b0-4326-ba8c-c271e17aec82 /media"
echo "  or reboot."
