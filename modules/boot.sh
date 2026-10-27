#!/usr/bin/env bash
# Menú de arranque de la ISO (grub / isolinux).

BOOT_RE='^[[:space:]]*(linux|append|options)[[:space:]]'

boot_configs() {
    find "$ISO_DIR" -type f \( -name grub.cfg -o -path '*/isolinux/*.cfg' \
        -o -path '*/syslinux/*.cfg' \) 2>/dev/null | sort
}

boot_backup_all() { local f; while IFS= read -r f; do core_backup "$f"; done < <(boot_configs); }

boot_escape() { printf '%s' "$1" | sed 's/[][\.*^$|/+?(){}&]/\\&/g'; }

# boot_add p  (no duplica)
boot_add() {
    local p f
    boot_backup_all
    p=$(boot_escape "$1")
    while IFS= read -r f; do
        sed -Ei "/$BOOT_RE/I { /(^|[[:space:]])$p([[:space:]]|\$)/! s/\$/ $p/ }" "$f"
    done < <(boot_configs)
}

boot_del() {
    local p f
    boot_backup_all
    p=$(boot_escape "$1")
    while IFS= read -r f; do
        sed -Ei "/$BOOT_RE/I s/[[:space:]]+$p([[:space:]]|\$)/\1/g" "$f"
    done < <(boot_configs)
}

# boot_set_kv clave valor : cambia clave=... solo donde ya existe
boot_set_kv() {
    local k v f
    boot_backup_all
    k=$(boot_escape "$1")
    v=$(boot_escape "$2")
    while IFS= read -r f; do
        grep -qE "(^|[[:space:]])$k=" "$f" &&
            sed -Ei "/$BOOT_RE/I s/(^|[[:space:]])$k=[^[:space:]]*/\1$k=$v/g" "$f"
    done < <(boot_configs)
    return 0
}

boot_edit() {
    local files=() items=() f
    while IFS= read -r f; do files+=("$f"); items+=("${f#"$ISO_DIR"/}::Se abre en el editor"); done < <(boot_configs)
    ((${#files[@]})) || { tui_msg "No hay archivos de arranque."; return; }
    tui_menu "Archivo de arranque a editar" "${items[@]}" || return
    core_backup "${files[MENU_SEL]}"
    tui_shell_out "$(core_editor)" "${files[MENU_SEL]}"
    core_change "Editado a mano: ${files[MENU_SEL]#"$ISO_DIR"/}"
}

boot_rename() {
    tui_prompt "Texto a reemplazar en los títulos del menú" "Void"
    local old=$REPLY_TXT
    [[ -n $old ]] || return
    tui_prompt "Texto nuevo"
    local new=$REPLY_TXT f oe ne
    boot_backup_all
    oe=$(boot_escape "$old")
    ne=$(boot_escape "$new")
    while IFS= read -r f; do
        sed -Ei "/menuentry|MENU[[:space:]]+(LABEL|TITLE)/I s/$oe/$ne/g" "$f"
    done < <(boot_configs)
    core_change "Menú de arranque: \"$old\" → \"$new\""
    tui_msg "Títulos actualizados."
}

boot_restore() {
    local d="$WORK/backup/iso"
    [[ -d $d ]] || { tui_msg "No hay cambios de arranque que deshacer."; return; }
    tui_confirm "¿Volver el menú de arranque al original?" || return
    cp -a "$d"/. "$ISO_DIR"/
    core_change "Arranque restaurado al original"
    tui_msg "Arranque restaurado."
}

boot_menu() {
    core_require_loaded || return
    local o=(
        "Ver mensajes al arrancar::Quita 'quiet' y 'splash' para ver qué pasa al iniciar"
        "Arrancar sin aceleración de video::Añade nomodeset (útil si la pantalla falla)"
        "Cambiar nombres del menú de arranque::Ej: cambiar \"Void\" por el nombre de tu ISO"
        "Añadir parámetro del kernel::Para usuarios avanzados"
        "Quitar parámetro del kernel::Para usuarios avanzados"
        "Editar archivo de arranque a mano::grub.cfg / isolinux.cfg"
        "Restaurar el arranque original::Deshace todos los cambios de esta pantalla")
    while tui_menu "Menú de arranque" "${o[@]}"; do
        case $MENU_SEL in
        0) boot_del quiet; boot_del splash; core_change "Arranque: mensajes visibles"; tui_msg "Hecho." ;;
        1) boot_add nomodeset; core_change "Arranque: nomodeset"; tui_msg "Hecho." ;;
        2) boot_rename ;;
        3)
            tui_prompt "Parámetro a añadir (ej. quiet)"
            [[ -n $REPLY_TXT ]] && { boot_add "$REPLY_TXT"; core_change "Arranque: añadido $REPLY_TXT"; tui_msg "Hecho."; }
            ;;
        4)
            tui_prompt "Parámetro a quitar"
            [[ -n $REPLY_TXT ]] && { boot_del "$REPLY_TXT"; core_change "Arranque: quitado $REPLY_TXT"; tui_msg "Hecho."; }
            ;;
        5) boot_edit ;;
        6) boot_restore ;;
        esac
    done
}
