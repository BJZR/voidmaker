#!/usr/bin/env bash
# Crea la ISO nueva reutilizando el arranque de la original.

build_run() {
    core_require_loaded || return
    local n def
    n=$(core_changes_count)
    def="${ISO_FILE%.iso}-custom.iso"
    tui_header "Crear la ISO nueva"
    if ((n == 0)); then
        printf ' Aún no has hecho cambios; la ISO saldrá igual a la original.\n'
    else
        printf ' Cambios que llevará tu ISO:\n\n'
        sed 's/^/   /' "$WORK/changes.log"
    fi
    tui_prompt "Nombre del archivo de salida" "$def"
    [[ -n $REPLY_TXT ]] || return
    local out=$REPLY_TXT
    [[ -e $out ]] && { tui_confirm "$out ya existe, ¿sobrescribir?" || return; }
    tui_shell_out build_exec "$out"
}

build_exec() {
    local out=$1 cat_path
    chroot_umount
    rm -rf "${ROOTFS:?}"/var/cache/xbps/* 2>/dev/null
    printf '\n Tamaño del sistema: %s\n' "$(du -sh "$ROOTFS" | cut -f1)"
    printf ' [1/2] Empaquetando el sistema (puede tardar varios minutos)...\n'
    rootfs_pack || { tui_err "Falló el empaquetado."; tui_wait; return 1; }

    cat_path=$(sed -nE "s/^-c '([^']+)'.*/\1/p" "$WORK/boot_args" | head -1)
    [[ -n $cat_path ]] && rm -f "$ISO_DIR$cat_path"

    printf ' [2/2] Generando la ISO...\n'
    eval "xorriso -as mkisofs $(tr '\n' ' ' <"$WORK/boot_args") -o $(printf %q "$out") $(printf %q "$ISO_DIR")" \
        >>"$WORK/log.txt" 2>&1 ||
        { tui_err "Falló xorriso (detalles: $WORK/log.txt)"; tui_wait; return 1; }

    printf '\n'
    tui_ok "ISO creada: $out ($(du -h "$out" | cut -f1))"
    printf '\n Pruébala en una máquina virtual antes de grabarla:\n'
    printf '   qemu-system-x86_64 -m 2G -enable-kvm -cdrom %q\n' "$out"
    printf ' (la ISO original debe seguir en %s)\n' "$ISO_FILE"
    tui_wait
}
