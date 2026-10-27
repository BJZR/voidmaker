#!/usr/bin/env bash
# Idioma, teclado, zona horaria y nombre del equipo.

locale_keymap() {
    local vals=(us es la-latin1 br-abnt2 uk de fr it pt-latin1)
    local names=("Inglés (EE.UU.)" "Español (España)" "Español (Latinoamérica)" "Portugués (Brasil)"
        "Inglés (Reino Unido)" "Alemán" "Francés" "Italiano" "Portugués (Portugal)")
    ui_pick "Teclado" vals names || return
    core_conf_set "$ROOTFS/etc/rc.conf" KEYMAP "$PICK_VALUE"
    boot_set_kv vconsole.keymap "$PICK_VALUE"
    core_change "Teclado: $PICK_VALUE"
    tui_msg "Teclado: $PICK_VALUE"
}

locale_timezone() {
    local vals=(America/Bogota America/Mexico_City America/Lima America/Santiago
        America/Argentina/Buenos_Aires America/Sao_Paulo America/New_York Europe/Madrid UTC)
    local names=("Colombia" "México" "Perú" "Chile" "Argentina" "Brasil (São Paulo)"
        "EE.UU. (Nueva York)" "España" "UTC")
    ui_pick "Zona horaria" vals names || return
    if [[ -d $ROOTFS/usr/share/zoneinfo && ! -e $ROOTFS/usr/share/zoneinfo/$PICK_VALUE ]]; then
        tui_msg "Zona no válida: $PICK_VALUE"
        return
    fi
    core_conf_set "$ROOTFS/etc/rc.conf" TIMEZONE "$PICK_VALUE"
    core_change "Zona horaria: $PICK_VALUE"
    tui_msg "Zona horaria: $PICK_VALUE"
}

locale_language() {
    local vals=(en_US.UTF-8 es_ES.UTF-8 es_CO.UTF-8 es_MX.UTF-8 pt_BR.UTF-8 fr_FR.UTF-8 de_DE.UTF-8)
    local names=("Inglés (EE.UU.)" "Español (España)" "Español (Colombia)" "Español (México)"
        "Portugués (Brasil)" "Francés" "Alemán")
    ui_pick "Idioma del sistema" vals names || return
    local l=$PICK_VALUE lc="$ROOTFS/etc/default/libc-locales"
    if [[ -f $lc ]]; then
        sed -Ei "s|^#[[:space:]]*($l[[:space:]])|\1|" "$lc"
        tui_shell_out chroot_run "xbps-reconfigure -f glibc-locales"
    else
        tui_warn "Esta ISO no usa glibc-locales (¿musl?). Solo se guarda la preferencia."
    fi
    echo "LANG=$l" >"$ROOTFS/etc/locale.conf"
    boot_set_kv locale.LANG "$l"
    core_change "Idioma: $l"
    tui_msg "Idioma: $l"
}

locale_hostname() {
    tui_prompt "Nombre del equipo" "$(cat "$ROOTFS/etc/hostname" 2>/dev/null)"
    [[ $REPLY_TXT =~ ^[a-zA-Z0-9-]+$ ]] || { tui_msg "Nombre inválido (letras, números y guiones)."; return; }
    echo "$REPLY_TXT" >"$ROOTFS/etc/hostname"
    core_change "Nombre del equipo: $REPLY_TXT"
    tui_msg "Nombre del equipo: $REPLY_TXT"
}
