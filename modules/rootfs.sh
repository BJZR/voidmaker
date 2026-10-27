#!/usr/bin/env bash
# Void live: LiveOS/squashfs.img -> LiveOS/ext3fs.img (ext4) -> sistema.

rootfs_unpack() {
    local img="$TMP/void/LiveOS/ext3fs.img"
    rm -rf "$ROOTFS" "$TMP"
    mkdir -p "$ROOTFS" "$TMP"
    unsquashfs -f -d "$TMP/void" "$ISO_DIR/LiveOS/squashfs.img" || return 1
    e2label "$img" >"$WORK/void_label" 2>/dev/null
    mount -o loop,ro "$img" "$MNT" || return 1
    cp -a "$MNT"/. "$ROOTFS"/
    local rc=$?
    umount "$MNT"
    return $rc
}

rootfs_pack() {
    local img="$TMP/void/LiveOS/ext3fs.img" label size_mb
    label=$(cat "$WORK/void_label" 2>/dev/null)
    size_mb=$(du -sm "$ROOTFS" | cut -f1)
    rm -f "$img"
    truncate -s "$((size_mb * 125 / 100 + 256))M" "$img" || return 1
    mkfs.ext4 -F -q -L "${label:-LiveOS}" "$img" || return 1
    mount -o loop "$img" "$MNT" || return 1
    cp -a "$ROOTFS"/. "$MNT"/
    local rc=$?
    umount "$MNT"
    ((rc == 0)) || return 1
    mksquashfs "$TMP/void" "$ISO_DIR/LiveOS/squashfs.img" -comp xz -noappend
}
