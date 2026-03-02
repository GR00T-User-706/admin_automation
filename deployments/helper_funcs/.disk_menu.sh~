#!/usr/bin/env bash

# Function to display menu of disk options
display_disk_menu() {
    local disk_list=("$@")
    echo "Available disks:"
    for i in "${!disk_list[@]}"; do
        printf "%s\t%s\n" "$((i + 1))) ${disk_list[$i]}"
    done
}

# Function to select disk from menu
select_disk() {
    local disk_list=("$@")
    read -rp "Please enter the number of your selected disk: " disk_num

    [[ $disk_num -lt ${#disk_list[*]} && $disk_num -gt 0 ]] || return 1
    DISK=${disk_list[((disk_num - 1))]}
}

declare -a disk_array
mapfile -t disk_array < <(lsblk -d -n -p -o NAME)
while [[ ${#disk_array[@]} -eq 0 ]]; do
    echo "No disks found."
    sleep 5
    mapfile -t disk_array < <(lsblk -d -n -p -o NAME)
done

display_disk_menu "${disk_array[@]}"
while ! select_disk "${disk_array[@]}"; do
    echo "Invalid selection, please try again."
    display_disk_menu "${disk_array[@]}"
done
echo "You selected: $DISK" # You can replace this line with your code to use the selected disk
