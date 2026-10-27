#!/usr/bin/env bash
# Archivos del sistema de la ISO.

files_add() {
    tui_prompt "Archivo o carpeta a copiar (de tu equipo)"
    local src=$REPLY_TXT dflt=/root
    [[ -e $src ]] || { tui_msg "No existe."; return; }
    [[ -d $ROOTFS/home/anon ]] && dflt=/home/anon
    tui_prompt "¿Dónde ponerlo dentro de la ISO?" "$dflt"
    local dst=/${REPLY_TXT#/}
    core_safe_relpath "$dst" || { tui_msg "Ruta inválida."; return; }
    mkdir -p "$ROOTFS$dst"
    cp -a "$src" "$ROOTFS$dst/" && core_change "Archivo añadido: $(basename "$src") → $dst"
    tui_msg "Copiado a $dst"
}

files_edit() {
    tui_prompt "Archivo dentro de la ISO" "/etc/rc.conf"
    local p=/${REPLY_TXT#/}
    core_safe_relpath "$p" || { tui_msg "Ruta inválida."; return; }
    [[ -L $ROOTFS$p ]] && { tui_msg "Es un enlace simbólico; usa la terminal."; return; }
    core_backup "$ROOTFS$p"
    tui_shell_out "$(core_editor)" "$ROOTFS$p"
    core_change "Editado a mano: $p"
}

files_delete() {
    tui_prompt "Ruta a borrar dentro de la ISO"
    local p=/${REPLY_TXT#/}
    core_safe_relpath "$p" && [[ $p != / ]] || { tui_msg "Ruta inválida."; return; }
    [[ -e $ROOTFS$p || -L $ROOTFS$p ]] || { tui_msg "No existe."; return; }
    tui_confirm "¿Borrar $p definitivamente?" || return
    rm -rf -- "${ROOTFS:?}$p" && core_change "Borrado: $p"
    tui_msg "Borrado."
}

files_browse() { # $1 = dir
    tui_shell_out bash -c "cd '$1' && echo 'Explorando. Escribe exit para volver.' && exec bash"
}

files_menu() {
    core_require_loaded || return
    local o=(
        "Añadir archivo o carpeta::Copia algo de tu equipo dentro de la ISO"
        "Editar un archivo::Abre un archivo del sistema en el editor"
        "Borrar un archivo::Quita algo del sistema de la ISO"
        "Explorar el sistema de la ISO::Abre una terminal en el sistema (sin entrar en chroot)"
        "Explorar los archivos de arranque::Estructura de la ISO (boot, EFI, LiveOS...)")
    while tui_menu "Archivos" "${o[@]}"; do
        case $MENU_SEL in
        0) files_add ;;
        1) files_edit ;;
        2) files_delete ;;
        3) files_browse "$ROOTFS" ;;
        4) files_browse "$ISO_DIR" ;;
        esac
    done
}
