#!/bin/bash
set -e

# ========== CONFIG ==========
DISK="/dev/sda"
EFI_PART="${DISK}1"
ROOT_PART="${DISK}2"
HOSTNAME="archvm"
TIMEZONE="America/Chicago"
USERNAME="username"   # CHANGE THIS
ROOT_PASS="rootpass"  # CHANGE THIS
USER_PASS="userpass"  # CHANGE THIS
# ============================

echo ">>> Partitioning..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 513MiB 100%

echo ">>> Formatting..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"

echo ">>> Mounting..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

echo ">>> Pacstrapping..."
pacstrap -K /mnt base linux linux-firmware networkmanager nano \
    xorg xfce4 xfce4-goodies lightdm lightdm-gtk-greeter

echo ">>> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> Chroot configuration..."
arch-chroot /mnt /bin/bash <<EOF
# Time
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Network
systemctl enable NetworkManager


# Bootloader
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Root password
echo "root:$ROOT_PASS" | chpasswd

# User
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel

# Enable lightdm
systemctl enable lightdm

# VirtualBox Guest Utils (if in VM)
pacman -S virtualbox-guest-utils --noconfirm
systemctl enable vboxservice
EOF

echo ">>> Unmounting..."
umount -R /mnt

echo ">>> Done. Reboot with 'reboot' and remove ISO."
