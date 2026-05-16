#!/bin/bash

container_c() {
    local USE_LUKS="yes"
    local DEVICE_UUID="407c2263-1f73-4424-a56b-2e1cb87a15af"  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/Container/C"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/74b51efb-be76-4e11-b971-4a98596676f7"
    local LUKS_NAME="Container-C_crypt"
    local LUKS_KEY_FILE="/root/.crypt/74b51efb-be76-4e11-b971-4a98596676f7.key"

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

container_d() {
    local USE_LUKS="yes"
    local DEVICE_UUID="407c2263-1f73-4424-a56b-2e1cb87a15af"  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/Container/D"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/cdd5b622-6efe-4f36-8bf6-ec99a6086279"
    local LUKS_NAME="Container-D_crypt"
    local LUKS_KEY_FILE="/root/.crypt/cdd5b622-6efe-4f36-8bf6-ec99a6086279.key"

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
        "/mnt/Local/Container/C"
        "/mnt/Local/Container/D"
    )
    local target="/mnt/Local/Pool/A"
    local options="defaults,allow_other,category.create=mfs,minfreespace=8G"
    local all_mounted=true

    for dir in "${branches[@]}"; do
        if ! { mountpoint -q "$dir" || true; }; then
            printf "\033[33m*\033[0m WARNING: %s IS NOT MOUNTED\n" "$dir" >&2
            all_mounted=false
        fi
    done

    "$all_mounted" || return 1

    if [[ ! -d "$target" ]]; then
        mkdir -p "$target" || {
            printf "\033[31m*\033[0m ERROR: FAILED TO CREATE TARGET DIRECTORY %s\n" "$target" >&2
            return 1
        }
    fi

    mergerfs -o "$options" \
        "$(IFS=:; echo "${branches[*]}")" \
        "$target"
}

# Main
container_c
container_d
pool_a