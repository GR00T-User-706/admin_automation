#!/usr/bin/env bash
# ==============================
# ARCH LINUX SECURE INSTALL
# UEFI + LUKS2 + BTRFS
# USB KEYFILE + HEADER BACKUP
# ==============================
set -euo pipefail

#===================================================
# THESE ARE FOR THE FINAL TARGET UNLESS WE MAKE IT
# TRUELY DYNAMIC DISK DETECTION AND SELECTION
# ---- DEVICE CONFIG (EDIT CAREFULLY) ----
#DISK="/dev/disk/by-id/nvme-eui.001b444a44b7f809"
#EFI_PART="${DISK}-part1"
#ROOT_PART="${DISK}-part2"
#SWAP_PART="${DISK}-part3"
#===================================================

USB_AUTH_PART="REDACTED"
VAULT_CRYPT="REDACTED"
CRYPT_NAME="REDACTED"
HOSTNAME="REDACTED"
USERNAME="REDACTED"
ROOTPASS="$1"
#ROOTPASS="##########"  # REMEMBER TO FIX THIS BEFORE RUNNING THIS
USERPASS="$2"
#USERPASS="#############" # REMEMBER TO FIX THIS BEFORE RUNNING THIS
TIMEZONE="America/Chicago"

#============================================================================#
# ------------------------------ SAFETY CHECKS ----------------------------- #
#============================================================================#
# CHECK 1) MUST BE RAN AS ROOT
[[ $EUID -eq 0 ]] || {
    echo "Run as root."
    exit 1
}
# CHECK 2) MUST INCLUDE 2 ARGUMENTS 1 FOR EACH OF THE PASSWORDS
[[ $# -eq 2 ]] || {
    echo "Usage: $0 <rootpass> <userpass>"
    exit 1
}
# CHECK 3) ENSURE THATS THE PASSWORDS ARE NOT WHITE SPACE OR EMPTY " ":" "
[[ -n "${ROOTPASS// /}" && -n "${USERPASS// /}" ]] || {
    echo "Passwords cannot be empty."
    exit 1
}
# CHECK 4) DONT REMEMBER WHAT THISONE IS FOR BUT IM LEAVING IT, IT LOOKS USEFUL
# I THINK I NEED TO ADD SOMETHING TO THE CONFIG VARS BC I FORGOT WHAT WAS THERE FIRST
# BEFORE I DELELTED THEM AND WROTE REDACTED
for DEV in "$DISK" "$EFI_PART" "$ROOT_PART" "$USB_AUTH_PART" "$VAULT_CRYPT"; do
    [[ -b "$DEV" ]] || {
        echo "Missing device: $DEV"
        exit 1
    }
done
# CHECK 5) FINAL CONFIRMATION SHOULD HAPPEN ALONG WITH THE DYNAMIC SELECTION SECTION SO
# THIS PROBABLY NEEDS TO MOVE BUT IDK
read -rp "This will wipe ${DISK}. Continue? (YES): " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

#============================================================================#
# -------------------------- PARTITION FORMATTING -------------------------- #
#============================================================================#
# 1) ---- PARTITION (if needed, comment out if pre-partitioned) ----
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 513MiB 100%

# 2) ---- FORMAT EFI ----
mkfs.fat -F32 "$EFI_PART"

# ---- LUKS ROOT ENCRYPTION ----
cryptsetup luksFormat "$ROOT_PART" \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --pbkdf argon2id

# -------- AN OTHER SAFETY GATE MAKING SURE ENCRYPTION WAS SUCESSFULL --------
cryptsetup isLuks "$ROOT_PART" || {
    echo "Partition is not LUKS. Aborting."
    exit 1
}

# ---- OPEN ROOT ----
cryptsetup open "$ROOT_PART" "$CRYPT_NAME"

# -------------------------- SAFETY REDUNDENCY CHECK --------------------------
[[ -e /dev/mapper/$CRYPT_NAME ]] || {
    echo "Encryption mapper not present. Aborting."
    exit 1
}

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

mount -o noatime,compress=zstd,ssd,subvol=@ /dev/mapper/$CRYPT_NAME /mnt
mkdir -p /mnt/{home,boot}
mount -o noatime,compress=zstd,ssd,subvol=@home /dev/mapper/$CRYPT_NAME /mnt/home
mount "$EFI_PART" /mnt/boot

# 6. Base Install
# I FEEL LIKE SOMETHING IS MISSING FROM HERE JUST NOT SURE WHAT
pacstrap -K /mnt base linux linux-firmware sudo vim \
    networkmanager grub efibootmgr fprintd libfprint \
    btrfs-progs amd-ucode plasma sddm kde-applications
# 7. fstab
genfstab -U /mnt >>/mnt/etc/fstab

# ROOT_UUID="$ROOT_UUID" YEAH IDK WHAT WAS GOING ON HERE IT WAS NOT ME I SWEAR
# 8. Chroot Config
# ---- CHROOT ----
arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# mkinitcpio for LUKS
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf
echo "$HOSTNAME" > /etc/hostname
mkinitcpio -P

# GRUB config
#ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
#UUID=$(blkid -s UUID -o value $ROOT_PART)
#UUID=$(blkid -s UUID -o value $ROOT_PART)
#sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:$CRYPT_NAME root=/dev/mapper/$CRYPT_NAME\"|" /etc/default/grub
#sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cryptdevice=UUID='"$ROOT_UUID"':'"$CRYPT_NAME"' root=\/dev\/mapper\/'"$CRYPT_NAME"'"/' /etc/default/grub
#echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Users
useradd -m -G wheel -s /bin/zsh "$USERNAME" # I PREFER ZSH OVER BASH FOR SOME REASON
echo "root:$ROOTPASS" | chpasswd
echo "$USERNAME:$USERPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable fstrim.timer
systemctl enable NetworkManager
systemctl enable sddm
EOF

# ---- CLEANUP ----
umount -R /mnt
cryptsetup close "$CRYPT_NAME"
cryptsetup close "$VAULT_MAPPER"
umount /mnt/usb || true

echo "Install complete. Reboot."
