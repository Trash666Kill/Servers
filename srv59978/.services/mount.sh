#!/bin/bash

# - Description: Mounts a device by UUID, an NFS share, or an SMB share to specified mount points.
# - Optionally decrypts a LUKS device before mounting for mount_unit if USE_LUKS is set to 'yes'.
# - Creates the mount point directories if they do not exist and mounts the device or share using provided UUID, source, and options.
# - Uses 'mount -U' for UUID-based mounts (non-LUKS in mount_unit) and 'mount' for NFS, SMB, or LUKS-mapped devices.
# - The nfs_mount_unit and smb_mount_unit functions are designed for network file systems and do not support LUKS decryption.
# - The OPTIONS variable is empty by default in all functions; specify custom mount options as needed.
# - Exits on any error using set -e.
# - To modify mount parameters, edit the DEVICE_UUID, NFS_SOURCE, SMB_SOURCE, MOUNT_POINT, or OPTIONS variables in the respective functions.
# - To enable LUKS decryption for mount_unit, set USE_LUKS="yes" before running the script.

# Close on any error
set -e

pool_a() {
    50026B7785D3588D() {
        local USE_LUKS="yes"  # Enable LUKS if USE_LUKS="yes"
        local DEVICE_UUID=""  # UUID for non-LUKS case
        local MOUNT_POINT="/mnt/Local/Container/A"
        local OPTIONS=""
        local LUKS_DEVICE="/dev/disk/by-uuid/ca52541c-b2e3-41e5-9c31-3048833fa08b"
        local LUKS_NAME="Container-A_crypt"
        local LUKS_KEY_FILE="/root/.crypt/ca52541c-b2e3-41e5-9c31-3048833fa08b.key"

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

    50026B7785D35B0D() {
        local USE_LUKS="yes"  # Enable LUKS if USE_LUKS="yes"
        local DEVICE_UUID=""  # UUID for non-LUKS case
        local MOUNT_POINT="/mnt/Local/Container/B"
        local OPTIONS=""
        local LUKS_DEVICE="/dev/disk/by-uuid/f515527f-eb65-424c-b88b-652e84609c5e"
        local LUKS_NAME="Container-B_crypt"
        local LUKS_KEY_FILE="/root/.crypt/f515527f-eb65-424c-b88b-652e84609c5e.key"

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

    # Call
    50026B7785D3588D
    50026B7785D35B0D
    mergerfs -o defaults,allow_other,category.create=mfs,minfreespace=8G /mnt/Local/Container/A:/mnt/Local/Container/B /mnt/Local/Pool/A
}

container_c() {
    local USE_LUKS="yes"  # Enable LUKS if USE_LUKS="yes"
    local DEVICE_UUID=""  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/Container/C"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/0842a224-fa02-4707-a6b3-d8ade5f4d2fd"
    local LUKS_NAME="Container-C_crypt"
    local LUKS_KEY_FILE="/root/.crypt/0842a224-fa02-4707-a6b3-d8ade5f4d2fd.key"

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
    local USE_LUKS="yes"  # Enable LUKS if USE_LUKS="yes"
    local DEVICE_UUID=""  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/Container/D"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/a58059c1-1254-4b8f-893d-220e8d9b6b6b"
    local LUKS_NAME="Container-D_crypt"
    local LUKS_KEY_FILE="/root/.crypt/a58059c1-1254-4b8f-893d-220e8d9b6b6b.key"

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

container_e() {
    local USE_LUKS="yes"  # Enable LUKS if USE_LUKS="yes"
    local DEVICE_UUID=""  # UUID for non-LUKS case
    local MOUNT_POINT="/mnt/Local/Container/E"
    local OPTIONS=""
    local LUKS_DEVICE="/dev/disk/by-uuid/bac62242-f1ff-43dc-bf18-cfedfbc1f1ff"
    local LUKS_NAME="Container-E_crypt"
    local LUKS_KEY_FILE="/root/.crypt/bac62242-f1ff-43dc-bf18-cfedfbc1f1ff.key"

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

# Main function to orchestrate the setup
main() {
    pool_a
    container_c
    container_d
    container_e
}

# Execute main function
main