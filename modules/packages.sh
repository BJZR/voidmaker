#!/usr/bin/env bash
# Programas (xbps) dentro de la ISO.

PKG_PROTECTED='^(base-system|runit-void|runit|xbps|dracut|glibc|musl|bash|coreutils|linux[0-9._]*|linux-headers|void-release-keys|shadow|util-linux|eudev)$'

# preset_data N -> "paquetes|servicios a activar|servicios a desactivar"
preset_data() {
    case $1 in
    0) echo "xorg xfce4 lightdm lightdm-gtk3-greeter dbus elogind|dbus elogind lightdm|" ;;
    1) echo "xorg i3 i3status dmenu alacritty lightdm lightdm-gtk3-greeter dbus elogind|dbus elogind lightdm|" ;;
    2) echo "firefox||" ;;
    3) echo "vim git htop curl wget||" ;;
    4) echo "NetworkManager network-manager-applet|dbus NetworkManager|dhcpcd wpa_supplicant" ;;
    5) echo "openssh|sshd|" ;;
    esac
}

pkg_need_net() {
    core_check_net && return 0
    tui_warn "No hay conexión a Internet (o el servidor de Void no responde)."
    tui_confirm "¿Intentar de todos modos?"
}

pkg_exec() {
    chroot_run "$1"
    local rc=$?
    printf '\n'
    ((rc == 0)) && tui_ok "Listo." || tui_err "Terminó con errores (revisa la salida de arriba)."
    tui_wait
    return $rc
}

pkg_install() {
    pkg_need_net || return
    tui_shell_out pkg_exec "xbps-install -Sy $1" && core_change "Programas instalados: $1"
}

pkg_apply_preset() {
    local data pk en di s
    data=$(preset_data "$1")
    IFS='|' read -r pk en di <<<"$data"
    pkg_need_net || return
    tui_shell_out pkg_exec "xbps-install -Sy $pk" || return
    core_change "Paquete(s) instalados: $pk"
    for s in $en; do svc_set enable "$s" quiet; done
    for s in $di; do svc_set disable "$s" quiet; done
    [[ -n $en ]] && core_change "Servicios activados: $en"
    [[ -n $di ]] && core_change "Servicios desactivados: $di"
    tui_msg "Programas instalados y servicios configurados."
}

packages_presets() {
    local o=(
        "Escritorio XFCE::Ventanas, panel y gestor de inicio de sesión (lightdm)"
        "Escritorio i3::Ligero, por teclado (+ alacritty, dmenu, lightdm)"
        "Navegador Firefox::Navegador web"
        "Herramientas de terminal::vim, git, htop, curl, wget"
        "Internet con NetworkManager::Red por menú gráfico; desactiva dhcpcd y wpa_supplicant"
        "Acceso remoto SSH::Servidor openssh, se activa al arrancar")
    tui_menu "Paquetes listos" "${o[@]}" || return
    tui_confirm "Se instalará \"${o[MENU_SEL]%%::*}\". ¿Seguir?" && pkg_apply_preset "$MENU_SEL"
}

# ---------- Lista de programas editable ----------

# nombres de paquetes instalados (manual|all), ordenados
pkg_current_list() {
    local cmd='xbps-query -m'
    [[ ${1:-manual} == all ]] && cmd="xbps-query -l | awk '{print \$2}'"
    chroot_run "$cmd" 2>/dev/null | sed -E 's/-[^-]+$//' | LC_ALL=C sort -u
}

pkglist_write() { # destino lista_actual
    {
        cat <<'TXT'
# ═══ VOIDMAKER · lista de programas ═══════════════════════════════
#  • BORRA una línea  -> ese programa se QUITARÁ de la ISO.
#  • AÑADE una línea  -> ese programa se INSTALARÁ (necesita Internet).
#  • Puedes poner varios nombres en una línea. Las líneas con # se ignoran.
#  • Guarda y cierra el editor para revisar los cambios antes de aplicarlos.
# ══════════════════════════════════════════════════════════════════
TXT
        cat "$2"
    } >"$1"
}

# nombres válidos de un txt (sin comentarios), ordenados
pkglist_clean() {
    sed 's/#.*//' "$1" | tr -s '[:space:]' '\n' | grep -E '^[A-Za-z0-9._+-]+$' | LC_ALL=C sort -u
}

pkglist_invalid() {
    sed 's/#.*//' "$1" | tr -s '[:space:]' '\n' | grep -v '^$' | grep -vE '^[A-Za-z0-9._+-]+$'
}

# pkglist_review nuevo.txt original_ordenado -> $WORK/pk.rm y $WORK/pk.add
pkglist_review() {
    pkglist_clean "$1" >"$WORK/pk.new"
    LC_ALL=C comm -23 "$2" "$WORK/pk.new" >"$WORK/pk.rm"
    LC_ALL=C comm -13 "$2" "$WORK/pk.new" >"$WORK/pk.add"
}

pkglist_run() { # nuevo.txt original_ordenado
    local nrm nadd prot bad text
    pkglist_review "$1" "$2"
    nrm=$(wc -l <"$WORK/pk.rm")
    nadd=$(wc -l <"$WORK/pk.add")
    bad=$(pkglist_invalid "$1" | tr '\n' ' ')
    [[ -n ${bad// /} ]] && tui_msg "Se ignoraron nombres no válidos: $bad"
    if ((nrm == 0 && nadd == 0)); then
        tui_msg "No hay cambios en la lista."
        return
    fi
    text=$(
        printf '\e[1;32mCAMBIOS EN LOS PROGRAMAS\e[0m\n\n'
        if ((nrm)); then printf '\e[31mSe QUITARÁN (%s):\e[0m\n' "$nrm"; sed 's/^/  - /' "$WORK/pk.rm"; printf '\n'; fi
        if ((nadd)); then printf '\e[32mSe INSTALARÁN (%s):\e[0m\n' "$nadd"; sed 's/^/  + /' "$WORK/pk.add"; fi
    )
    tui_pager "$text"
    prot=$(grep -E "$PKG_PROTECTED" "$WORK/pk.rm" | tr '\n' ' ')
    if [[ -n ${prot// /} ]]; then
        tui_warn "Vas a quitar paquetes CRÍTICOS: $prot"
        tui_warn "Esto puede dejar la ISO sin arrancar."
        tui_prompt "Escribe SI (en mayúsculas) para continuar"
        [[ $REPLY_TXT == SI ]] || return
    else
        tui_confirm "¿Aplicar estos cambios ahora?" || return
    fi
    ((nadd)) && { pkg_need_net || return; }
    tui_shell_out pkglist_apply_exec
}

pkglist_apply_exec() {
    local rem add p failed=() ok_rm=() ok_add=() fails
    rem=$(tr '\n' ' ' <"$WORK/pk.rm")
    add=$(tr '\n' ' ' <"$WORK/pk.add")
    if [[ -n ${rem// /} ]]; then
        printf '\n Quitando programas...\n'
        if chroot_run "xbps-remove -Ry $rem"; then
            ok_rm=($rem)
        else
            printf '\n Falló el lote; probando uno por uno...\n'
            for p in $rem; do
                if chroot_run "xbps-remove -Ry $p"; then ok_rm+=("$p"); else failed+=("quitar:$p"); fi
            done
        fi
    fi
    if [[ -n ${add// /} ]]; then
        printf '\n Instalando programas...\n'
        if chroot_run "xbps-install -Sy $add"; then
            ok_add=($add)
        else
            printf '\n Falló el lote; probando uno por uno...\n'
            for p in $add; do
                if chroot_run "xbps-install -y $p"; then ok_add+=("$p"); else failed+=("instalar:$p"); fi
            done
        fi
    fi
    printf '\n'
    ((${#ok_rm[@]})) && { tui_ok "Quitados: ${ok_rm[*]}"; core_change "Programas quitados: ${ok_rm[*]}"; }
    ((${#ok_add[@]})) && { tui_ok "Instalados: ${ok_add[*]}"; core_change "Programas instalados: ${ok_add[*]}"; }
    if ((${#failed[@]})); then
        fails=${failed[*]}
        tui_err "No se pudo: $fails"
    fi
    tui_wait
}

pkglist_edit() { # manual|all
    local f="$WORK/packages.txt" orig="$WORK/packages.orig"
    tui_header "Lista de programas"
    printf ' Leyendo los programas instalados...\n'
    pkg_current_list "$1" >"$orig"
    if [[ ! -s $orig ]]; then
        tui_msg "No se pudo leer la lista de programas (¿xbps-query en la ISO?)."
        return
    fi
    pkglist_write "$f" "$orig"
    tui_shell_out "$(core_editor)" "$f"
    pkglist_run "$f" "$orig"
}

pkglist_save() {
    local dflt="$HOME/lista-programas.txt" orig="$WORK/packages.orig"
    [[ -n ${SUDO_USER:-} ]] && dflt="$(getent passwd "$SUDO_USER" | cut -d: -f6)/lista-programas.txt"
    tui_prompt "¿Dónde guardar la lista?" "$dflt"
    [[ -n $REPLY_TXT ]] || return
    pkg_current_list manual >"$orig"
    pkglist_write "$REPLY_TXT" "$orig" && tui_msg "Lista guardada en $REPLY_TXT"
}

pkglist_import() {
    tui_prompt "Archivo .txt con la lista de programas"
    local f=$REPLY_TXT orig="$WORK/packages.orig"
    [[ -f $f ]] || { tui_msg "No existe: $f"; return; }
    tui_header "Lista de programas"
    printf ' Leyendo los programas instalados...\n'
    pkg_current_list manual >"$orig"
    pkglist_run "$f" "$orig"
}

packages_list_menu() {
    local o=(
        "Editar la lista de programas (recomendado)::Se abre un txt con lo instalado a propósito: borra para quitar, añade para instalar"
        "Editar la lista COMPLETA::Incluye dependencias (más larga y delicada)"
        "Guardar la lista en un archivo::Para conservarla o compartirla"
        "Aplicar una lista desde un archivo::La ISO quedará con los programas del archivo")
    while tui_menu "Lista de programas" "${o[@]}"; do
        case $MENU_SEL in
        0) pkglist_edit manual ;;
        1) pkglist_edit all ;;
        2) pkglist_save ;;
        3) pkglist_import ;;
        esac
    done
}

pkg_clean_cache() {
    local before
    before=$(du -sm "$ROOTFS/var/cache/xbps" 2>/dev/null | cut -f1)
    rm -rf "${ROOTFS:?}"/var/cache/xbps/* 2>/dev/null
    tui_msg "Descargas eliminadas (liberado: ${before:-0} MB). Esto también se hace al crear la ISO."
}

packages_menu() {
    core_require_loaded || return
    local o=(
        "Lista de programas (editar en un txt)::Exporta todo a un txt, bórralo o añade líneas y aplícalo al instante"
        "Paquetes listos (XFCE, i3, Firefox...)::Instala un conjunto ya preparado, con sus servicios"
        "Instalar programa por nombre::Ej: neovim  (necesitas Internet)"
        "Buscar programa::Busca en los repositorios de Void"
        "Quitar programa por nombre::Desinstala del sistema de la ISO"
        "Ver programas instalados::Lista completa para leer"
        "Actualizar todo::Actualiza todos los paquetes (necesitas Internet)"
        "Limpiar descargas::Borra la caché de paquetes y reduce el tamaño de la ISO")
    while tui_menu "Programas" "${o[@]}"; do
        case $MENU_SEL in
        0) packages_list_menu ;;
        1) packages_presets ;;
        2)
            tui_prompt "Nombre(s) del programa"
            [[ -n $REPLY_TXT ]] && pkg_install "$REPLY_TXT"
            ;;
        3)
            tui_prompt "Buscar"
            [[ -n $REPLY_TXT ]] && pkg_need_net && tui_shell_out pkg_exec "xbps-query -Rs '$REPLY_TXT' | less"
            ;;
        4)
            tui_prompt "Programa(s) a quitar"
            if [[ -n $REPLY_TXT ]]; then
                tui_shell_out pkg_exec "xbps-remove -Ry $REPLY_TXT" &&
                    core_change "Programas quitados: $REPLY_TXT"
            fi
            ;;
        5) tui_shell_out pkg_exec "xbps-query -l | less" ;;
        6)
            pkg_need_net && tui_shell_out pkg_exec "xbps-install -Suy xbps; xbps-install -Suy" &&
                core_change "Sistema actualizado"
            ;;
        7) pkg_clean_cache ;;
        esac
    done
}
