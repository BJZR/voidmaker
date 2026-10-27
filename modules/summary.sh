#!/usr/bin/env bash
# Resumen en lenguaje simple de lo que trae la ISO.

summary_h() { printf '\n\e[1;32m%s\e[0m\n' "$1"; }

summary_run() {
    core_require_loaded || return
    tui_pager "$(summary_report)"
}

summary_report() {
    local pretty
    pretty=$(. "$ROOTFS/etc/os-release" 2>/dev/null && echo "$PRETTY_NAME")

    summary_h "Tu ISO"
    printf '  Archivo:    %s (%s)\n' "$(basename "$ISO_FILE")" "$(du -h "$ISO_FILE" | cut -f1)"
    printf '  Sistema:    %s\n' "${pretty:-Void Linux}"
    printf '  Tamaño del sistema ya abierto: %s\n' "$(du -sh "$ROOTFS" | cut -f1)"
    printf '  Programas instalados: %s\n' "$(chroot_run 'xbps-query -l | wc -l' 2>/dev/null)"

    summary_h "Kernel"
    ls "$ROOTFS/usr/lib/modules" 2>/dev/null | sed 's/^/  /'

    summary_h "Usuarios"
    awk -F: '$3==0||($3>=1000&&$3<65534){printf "  %s\n",$1}' "$ROOTFS/etc/passwd" 2>/dev/null

    summary_h "Servicios que arrancan solos"
    svc_enabled_list | sed 's/^/  /'

    summary_h "Idioma, teclado y hora"
    grep -E '^(KEYMAP|TIMEZONE|HARDWARECLOCK)=' "$ROOTFS/etc/rc.conf" 2>/dev/null | sed 's/^/  /'
    [[ -f $ROOTFS/etc/locale.conf ]] && sed 's/^/  /' "$ROOTFS/etc/locale.conf"
    printf '  Hostname: %s\n' "$(cat "$ROOTFS/etc/hostname" 2>/dev/null)"

    summary_h "Menú de arranque (archivos que puedes editar)"
    boot_configs | sed "s|^$ISO_DIR|  |"

    summary_h "Lo más pesado del sistema (/usr)"
    du -xh --max-depth=2 "$ROOTFS/usr" 2>/dev/null | sort -rh | head -6 | sed "s|$ROOTFS|  |"

    if [[ -f $WORK/changes.log ]]; then
        summary_h "Cambios hechos hasta ahora"
        sed 's/^/  /' "$WORK/changes.log"
    fi
}
