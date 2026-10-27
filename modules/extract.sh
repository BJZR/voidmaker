#!/usr/bin/env bash
# Cargar una ISO de Void: extraer, guardar arranque, desempaquetar sistema.

extract_candidates() {
    local dirs=("$PWD" "$HOME" "$HOME/Downloads" "$HOME/Descargas") h
    if [[ -n ${SUDO_USER:-} ]]; then
        h=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        [[ -n $h ]] && dirs+=("$h" "$h/Downloads" "$h/Descargas")
    fi
    local all
    all=$(find "${dirs[@]}" -maxdepth 2 -type f -iname '*.iso' 2>/dev/null | sort -u)
    { grep -i void <<<"$all"; grep -vi void <<<"$all"; } | grep -v '^$'
}

extract_run() {
    local files=() items=() f
    mapfile -t files < <(extract_candidates)
    for f in "${files[@]}"; do
        items+=("$(basename "$f")::$f ($(du -h "$f" | cut -f1))")
    done
    items+=("Escribir otra ruta::Indica la ruta de la ISO a mano")
    tui_menu "Cargar ISO — elige una ISO de Void" "${items[@]}" || return
    if ((MENU_SEL < ${#files[@]})); then
        f=${files[MENU_SEL]}
    else
        tui_prompt "Ruta de la ISO"
        f=$REPLY_TXT
    fi
    [[ -f $f ]] || { tui_msg "No existe: $f"; return; }
    if [[ -n $DISTRO ]] && ! tui_confirm "Se descarta el trabajo actual. ¿Continuar?"; then
        return
    fi
    tui_shell_out extract_exec "$f"
}

extract_exec() {
    local f need avail
    f=$(realpath "$1")
    need=$(($(stat -c %s "$f") * 4))
    avail=$(df --output=avail -B1 "$WORK" | tail -1)
    if ((avail < need)); then
        tui_warn "Poco espacio en $WORK (libre: $((avail / 1048576)) MB, recomendado: $((need / 1048576)) MB)."
        tui_confirm "¿Continuar de todos modos?" || return 1
    fi

    chroot_umount
    ISO_FILE=$f
    DISTRO=""
    rm -rf "$ISO_DIR" "$ROOTFS" "$TMP" "$WORK/changes.log" "$WORK/backup"
    core_workdirs
    : >"$WORK/log.txt"

    printf '\n Cargando %s\n\n' "$(basename "$f")"
    printf ' [1/4] Extrayendo contenido de la ISO...\n'
    xorriso -osirrox on -indev "$ISO_FILE" -extract / "$ISO_DIR" >>"$WORK/log.txt" 2>&1 ||
        { tui_err "Falló la extracción (detalles: $WORK/log.txt)"; tui_wait; return 1; }
    chmod -R u+w "$ISO_DIR"

    printf ' [2/4] Guardando datos de arranque...\n'
    xorriso -indev "$ISO_FILE" -report_el_torito as_mkisofs 2>/dev/null |
        grep -E '^-' >"$WORK/boot_args"

    printf ' [3/4] Comprobando que es Void Linux...\n'
    if ! detect_void; then
        tui_err "Esta ISO no parece ser Void Linux (Voidmaker solo trabaja con Void)."
        ISO_FILE=""
        tui_wait
        return 1
    fi
    DISTRO=void

    printf ' [4/4] Abriendo el sistema de la ISO (puede tardar)...\n'
    rootfs_unpack || { tui_err "Falló al abrir el sistema."; DISTRO=""; tui_wait; return 1; }

    core_save_state
    printf '\n'
    tui_ok "ISO cargada. Ya puedes personalizarla desde el menú."
    tui_wait
}

extract_reset() {
    [[ -f $ISO_FILE ]] || { tui_msg "No encuentro la ISO original: $ISO_FILE"; return; }
    tui_confirm "Se borrarán TODOS tus cambios y se vuelve a la ISO original. ¿Seguro?" || return
    tui_shell_out extract_exec "$ISO_FILE"
}
