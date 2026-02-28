#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Arch Linux Balanced LUKS Install
# UEFI + LUKS (root) + Btrfs + KDE
# EDIT DISK VARIABLE CAREFULLY
# ==============================
# Require root + user password as arguments
[[ $# -eq 2 ]] || { echo "Usage: $0 <rootpass> <userpass>"; exit 1; }

ROOTPASS="$1"
USERPASS="$2"

[[ -n "${ROOTPASS// }" && -n "${USERPASS// }" ]] || { echo "Passwords cannot be empty."; exit 1; }
DISK="/dev/nvme0n1"
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
CRYPT_NAME="REDACTED"
HOSTNAME="REDACTED"
USERNAME="REDACTED"
TIMEZONE="America/Chicago"
#ROOTPASS="##########"  # REMEMBER TO FIX THIS BEFORE RUNNING THIS
#USERPASS="#############" # REMEMBER TO FIX THIS BEFORE RUNNING THIS

read -rp "This will wipe ${DISK}. Continue? (YES): " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# 1. Partition
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 513MiB 100%

# 2. Format EFI
mkfs.fat -F32 "$EFI_PART"

# 3. LUKS Encrypt Root
cryptsetup luksFormat "$ROOT_PART"
cryptsetup open "$ROOT_PART" "$CRYPT_NAME"

# 4. Btrfs Filesystem
mkfs.btrfs /dev/mapper/$CRYPT_NAME
mount /dev/mapper/$CRYPT_NAME /mnt

# Optional subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o noatime,compress=zstd,ssd,subvol=@ /dev/mapper/$CRYPT_NAME /mnt
mkdir -p /mnt/{home,boot}
mount -o noatime,compress=zstd,ssd,subvol=@home /dev/mapper/$CRYPT_NAME /mnt/home

# 5. Mount EFI
mount "$EFI_PART" /mnt/boot

# 6. Base Install
pacstrap -K /mnt base linux linux-firmware sudo vim \
    networkmanager grub efibootmgr fprintd libfprint \
    btrfs-progs amd-ucode plasma sddm kde-applications

# 7. fstab
genfstab -U /mnt >> /mnt/etc/fstab

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
# 8. Chroot Config
arch-chroot /mnt /bin/bash <<EOF
ROOT_UUID="$ROOT_UUID"

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
# mkinitcpio for LUKS
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB config
UUID=$(blkid -s UUID -o value $ROOT_PART)
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cryptdevice=UUID='"$ROOT_UUID"':'"$CRYPT_NAME"' root=\/dev\/mapper\/'"$CRYPT_NAME"'"/' /etc/default/grub
echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Users
echo "root:$ROOTPASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable fstrim.timer
systemctl enable NetworkManager
systemctl enable sddm

EOF

umount -R /mnt

echo "Install complete. Reboot."
