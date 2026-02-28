#!/usr/bin/env bash
set -euo pipefail

# ==============================
# ARCH LINUX SECURE INSTALL
# UEFI + LUKS2 + BTRFS
# USB KEYFILE + HEADER BACKUP
# ==============================

# ---- DEVICE CONFIG (EDIT CAREFULLY) ----
DISK="/dev/disk/by-id/nvme-eui.001b444a44b7f809"

EFI_PART="${DISK}-part1"
ROOT_PART="${DISK}-part2"
SWAP_PART="${DISK}-part3"

USB_AUTH_PART="REDACTED"
VAULT_CRYPT="REDACTED"

CRYPT_NAME="REDACTED"
VAULT_MAPPER="REDACTED"

HOSTNAME="REDACTED"
USERNAME="REDACTED"
TIMEZONE="America/Chicago"

# ---- SAFETY CHECKS ----
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

for DEV in "$DISK" "$EFI_PART" "$ROOT_PART" "$USB_AUTH_PART" "$VAULT_CRYPT"; do
    [[ -b "$DEV" ]] || { echo "Missing device: $DEV"; exit 1; }
done

read -rp "THIS WILL WIPE ${DISK}. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# ---- PARTITION (if needed, comment out if pre-partitioned) ----
# parted -s "$DISK" mklabel gpt
# parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
# parted -s "$DISK" set 1 esp on
# parted -s "$DISK" mkpart primary 513MiB 100%

# ---- FORMAT EFI ----
mkfs.fat -F32 "$EFI_PART"

# ---- LUKS FORMAT (INTERACTIVE PASSPHRASE ENTRY) ----
cryptsetup luksFormat "$ROOT_PART" \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --pbkdf argon2id

# ---- OPEN ROOT ----
cryptsetup open "$ROOT_PART" "$CRYPT_NAME"

# ---- GENERATE USB KEYFILE ----
mkdir -p /mnt/usb
mount "$USB_AUTH_PART" /mnt/usb

if [ ! -f /mnt/usb/arch_root.key ]; then
    dd if=/dev/urandom of=/mnt/usb/arch_root.key bs=4096 count=1
    chmod 400 /mnt/usb/arch_root.key
fi

cryptsetup luksAddKey "$ROOT_PART" /mnt/usb/arch_root.key

# ---- HEADER BACKUP TO KALIVAULT ----
cryptsetup open "$VAULT_CRYPT" "$VAULT_MAPPER"
mkdir -p /mnt/vault
mount /dev/mapper/$VAULT_MAPPER /mnt/vault

cryptsetup luksHeaderBackup "$ROOT_PART" \
    --header-backup-file /mnt/vault/luks-header-$(date +%F).img

# ---- FILESYSTEM ----
mkfs.btrfs /dev/mapper/$CRYPT_NAME
mount /dev/mapper/$CRYPT_NAME /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o subvol=@ /dev/mapper/$CRYPT_NAME /mnt
mkdir -p /mnt/{home,boot}
mount -o subvol=@home /dev/mapper/$CRYPT_NAME /mnt/home
mount "$EFI_PART" /mnt/boot

# ---- BASE INSTALL ----
pacstrap -K /mnt base linux linux-firmware \
    sudo vim networkmanager grub efibootmgr \
    btrfs-progs amd-ucode plasma sddm \
    fprintd libfprint

genfstab -U /mnt >> /mnt/etc/fstab

# ---- CHROOT ----
arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

UUID=\$(blkid -s UUID -o value $ROOT_PART)
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:$CRYPT_NAME root=/dev/mapper/$CRYPT_NAME\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

passwd
useradd -m -G wheel -s /bin/bash $USERNAME
passwd $USERNAME

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager sddm

EOF

# ---- CLEANUP ----
umount -R /mnt
cryptsetup close "$CRYPT_NAME"
cryptsetup close "$VAULT_MAPPER"
umount /mnt/usb || true

echo "Install complete."
