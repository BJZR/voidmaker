#!/usr/bin/env bash
# Chroot sobre el sistema de la ISO.

chroot_mount() {
    local d
    for d in dev dev/pts proc sys; do
        mkdir -p "$ROOTFS/$d"
        mountpoint -q "$ROOTFS/$d" || mount --bind "/$d" "$ROOTFS/$d"
    done
    if [[ -e $ROOTFS/etc/resolv.conf || -L $ROOTFS/etc/resolv.conf ]]; then
        [[ -e $ROOTFS/etc/resolv.conf.vm || -L $ROOTFS/etc/resolv.conf.vm ]] ||
            mv "$ROOTFS/etc/resolv.conf" "$ROOTFS/etc/resolv.conf.vm"
    fi
    cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf" 2>/dev/null
    return 0
}

chroot_umount() {
    local d
    [[ -d $ROOTFS ]] || return 0
    for d in dev/pts dev proc sys; do
        mountpoint -q "$ROOTFS/$d" 2>/dev/null && umount -l "$ROOTFS/$d"
    done
    if [[ -e $ROOTFS/etc/resolv.conf.vm || -L $ROOTFS/etc/resolv.conf.vm ]]; then
        rm -f "$ROOTFS/etc/resolv.conf"
        mv "$ROOTFS/etc/resolv.conf.vm" "$ROOTFS/etc/resolv.conf"
    fi
    return 0
}

# chroot_run "comando de shell"
chroot_run() {
    chroot_mount
    chroot "$ROOTFS" /bin/bash -c "$1"
    local rc=$?
    chroot_umount
    return $rc
}

terminal_menu() {
    core_require_loaded || return
    tui_header "Terminal dentro de la ISO"
    printf ' Vas a entrar al sistema de la ISO como root.\n'
    printf ' Todo lo que hagas ahí (instalar, editar, borrar) queda en la ISO nueva.\n'
    printf ' Escribe \e[1mexit\e[0m para volver a Voidmaker.\n'
    tui_confirm "¿Entrar?" || return
    chroot_mount
    tui_shell_out chroot "$ROOTFS" /bin/bash -l
    chroot_umount
    core_change "Terminal: cambios manuales dentro del sistema"
}
