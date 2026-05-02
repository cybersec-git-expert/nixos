#!/usr/bin/env bash
# Re-format a removable USB *partition* with the same filesystem type it already has.
# Usage: sudo ./format-usb-samefstype.sh /dev/sdX1
set -euo pipefail

dev="${1:?Pass partition device, e.g. /dev/sdb1}"

[[ -b "$dev" ]] || { echo "Not a block device: $dev"; exit 1; }

tran="$(lsblk -dn -o TRAN "$dev" 2>/dev/null || true)"
if [[ "$tran" != "usb" ]]; then
  echo "Refusing: $dev has TRAN='$tran' (expected 'usb'). Wrong disk?"
  exit 1
fi

if findmnt -n "$dev" &>/dev/null; then
  echo "Unmounting $dev …"
  udisksctl unmount -b "$dev" 2>/dev/null || umount "$dev"
fi

fstype="$(blkid -p -o value -s TYPE "$dev" 2>/dev/null || true)"
if [[ -z "$fstype" ]]; then
  echo "Could not read TYPE from blkid. Is this a partitioned volume?"
  exit 1
fi

echo "Detected filesystem: $fstype"
read -r -p "This will ERASE ALL DATA on $dev. Type YES to continue: " ans
[[ "$ans" == "YES" ]] || { echo "Aborted."; exit 1; }

case "$fstype" in
  vfat|fat16|fat32|msdos)
    echo "Formatting as FAT32 (vfat) …"
    mkfs.vfat -F 32 -n "USB16G" "$dev"
    ;;
  exfat)
    echo "Formatting as exfat …"
    mkfs.exfat -n "USB16G" "$dev"
    ;;
  ext2|ext3|ext4)
    echo "Formatting as $fstype …"
    "mkfs.$fstype" -F "$dev"
    ;;
  btrfs)
    echo "Formatting as btrfs …"
    mkfs.btrfs -f "$dev"
    ;;
  xfs)
    echo "Formatting as xfs …"
    mkfs.xfs -f "$dev"
    ;;
  ntfs)
    echo "Formatting as ntfs …"
    mkfs.ntfs -f -L USB16G "$dev"
    ;;
  *)
    echo "No automatic formatter for type '$fstype'. Format manually or extend this script."
    exit 2
    ;;
esac

blkid "$dev"
echo "Done."
