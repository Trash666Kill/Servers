#!/bin/bash

# Close on any error
set -e

container_a() {
    local USE_LUKS=${USE_LUKS:-}  # Enable LUKS if USE_LUKS="yes"
    local DEVICE_UUID="d394b90a-9eb5-40b3-bd33-a89abeaa3e7d"  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/Container/A"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/d394b90a-9eb5-40b3-bd33-a89abeaa3e7d"
    local LUKS_NAME="Container-A_crypt"
    local LUKS_KEY_FILE="/root/.crypt/d394b90a-9eb5-40b3-bd33-a89abeaa3e7d.key"

    # Handle LUKS decryption if enabled
    if [ "$USE_LUKS" = "yes" ]; then
        if [ ! -e "/dev/mapper/$LUKS_NAME" ]; then
            cryptsetup luksOpen "$LUKS_DEVICE" "$LUKS_NAME" --key-file "$LUKS_KEY_FILE"
        fi
        DEVICE_UUID="/dev/mapper/$LUKS_NAME"
    fi

    # Create mount point if it doesn't exist
    [ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"

    # Perform the mount
    if [ "$USE_LUKS" = "yes" ]; then
        if [ -n "$OPTIONS" ]; then
            mount "$DEVICE_UUID" "$MOUNT_POINT" -o "$OPTIONS"
        else
            mount "$DEVICE_UUID" "$MOUNT_POINT"
        fi
    else
        if [ -n "$OPTIONS" ]; then
            mount -U "$DEVICE_UUID" "$MOUNT_POINT" -o "$OPTIONS"
        else
            mount -U "$DEVICE_UUID" "$MOUNT_POINT"
        fi
    fi
}

usb_a() {
    local USE_LUKS=${USE_LUKS:-}  # Enable LUKS if USE_LUKS="yes"
    local DEVICE_UUID="8969890d-ccca-4e64-89b0-be045c1a3772"  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/USB/A"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/8969890d-ccca-4e64-89b0-be045c1a3772"
    local LUKS_NAME="USB-A_crypt"
    local LUKS_KEY_FILE="/root/.crypt/8969890d-ccca-4e64-89b0-be045c1a3772.key"

    # Handle LUKS decryption if enabled
    if [ "$USE_LUKS" = "yes" ]; then
        if [ ! -e "/dev/mapper/$LUKS_NAME" ]; then
            cryptsetup luksOpen "$LUKS_DEVICE" "$LUKS_NAME" --key-file "$LUKS_KEY_FILE"
        fi
        DEVICE_UUID="/dev/mapper/$LUKS_NAME"
    fi

    # Create mount point if it doesn't exist
    [ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"

    # Perform the mount
    if [ "$USE_LUKS" = "yes" ]; then
        if [ -n "$OPTIONS" ]; then
            mount "$DEVICE_UUID" "$MOUNT_POINT" -o "$OPTIONS"
        else
            mount "$DEVICE_UUID" "$MOUNT_POINT"
        fi
    else
        if [ -n "$OPTIONS" ]; then
            mount -U "$DEVICE_UUID" "$MOUNT_POINT" -o "$OPTIONS"
        else
            mount -U "$DEVICE_UUID" "$MOUNT_POINT"
        fi
    fi
}

usb_b() {
    local USE_LUKS=${USE_LUKS:-}  # Enable LUKS if USE_LUKS="yes"
    local DEVICE_UUID="51afdba4-727a-4b6b-b5a2-f24bfee7641b"  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/USB/B"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/51afdba4-727a-4b6b-b5a2-f24bfee7641b"
    local LUKS_NAME="USB-B_crypt"
    local LUKS_KEY_FILE="/root/.crypt/51afdba4-727a-4b6b-b5a2-f24bfee7641b.key"

    # Handle LUKS decryption if enabled
    if [ "$USE_LUKS" = "yes" ]; then
        if [ ! -e "/dev/mapper/$LUKS_NAME" ]; then
            cryptsetup luksOpen "$LUKS_DEVICE" "$LUKS_NAME" --key-file "$LUKS_KEY_FILE"
        fi
        DEVICE_UUID="/dev/mapper/$LUKS_NAME"
    fi

    # Create mount point if it doesn't exist
    [ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"

    # Perform the mount
    if [ "$USE_LUKS" = "yes" ]; then
        if [ -n "$OPTIONS" ]; then
            mount "$DEVICE_UUID" "$MOUNT_POINT" -o "$OPTIONS"
        else
            mount "$DEVICE_UUID" "$MOUNT_POINT"
        fi
    else
        if [ -n "$OPTIONS" ]; then
            mount -U "$DEVICE_UUID" "$MOUNT_POINT" -o "$OPTIONS"
        else
            mount -U "$DEVICE_UUID" "$MOUNT_POINT"
        fi
    fi
}

pool_a() {
    local branches=(
        "/mnt/Local/USB/A"
        "/mnt/Local/USB/B"
    )
    local target="/mnt/Local/Pool/A"
    local options="defaults,allow_other,category.create=mfs,minfreespace=8G"
    local all_mounted=true

    # 1. Verifica se as origens estão montadas
    for dir in "${branches[@]}"; do
        if ! mountpoint -q "$dir"; then
            printf "\033[33m*\033[0m WARNING: %s IS NOT MOUNTED\n" "$dir" >&2
            all_mounted=false
        fi
    done

    if ! $all_mounted; then
        return 0
    fi

    # 2. Verifica se o destino já está montado
    if mountpoint -q "$target"; then
        printf "\033[33m*\033[0m WARNING: %s ALREADY MOUNTED\n" "$target" >&2
        return 0
    fi

    # 3. Cria o diretório alvo se ele não existir (mkdir -p é idempotente)
    if ! mkdir -p "$target"; then
        printf "\033[31m*\033[0m ERROR: FAILED TO CREATE TARGET DIRECTORY %s\n" "$target" >&2
        return 1
    fi

    # 4. Executa o mergerfs
    mergerfs -o "$options" \
        "$(IFS=:; echo "${branches[*]}")" \
        "$target"
}

# Main function to orchestrate the setup
main() {
    usb_a
    container_a
    usb_b
    pool_a
}

# Execute main function
main