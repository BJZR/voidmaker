#!/usr/bin/env bash
# Configuración del sistema: idioma, teclado, hora, repositorios, mensajes, módulos.

config_hwclock() {
    tui_menu "Reloj del equipo" \
        "UTC (recomendado)::Estándar en Linux" \
        "Hora local::Útil si compartes el PC con Windows" || return
    local v=UTC
    ((MENU_SEL == 1)) && v=localtime
    core_conf_set "$ROOTFS/etc/rc.conf" HARDWARECLOCK "$v"
    core_change "Reloj del equipo: $v"
    tui_msg "Reloj del equipo: $v"
}

config_edit_path() {
    local p=$1 f="$ROOTFS$1"
    mkdir -p "$(dirname "$f")"
    [[ -e $f ]] || : >"$f"
    core_backup "$f"
    tui_shell_out "$(core_editor)" "$f"
    core_change "Editado: $p"
}

config_welcome() {
    local o=(
        "Mensaje antes del inicio de sesión::Se muestra en la pantalla de login de texto (/etc/issue)"
        "Mensaje después de entrar::Texto de bienvenida (/etc/motd)")
    while tui_menu "Mensajes de bienvenida" "${o[@]}"; do
        case $MENU_SEL in
        0) config_edit_path /etc/issue ;;
        1) config_edit_path /etc/motd ;;
        esac
    done
}

# ---- Repositorios ----
config_repo_show() {
    local f out=""
    for f in "$ROOTFS"/usr/share/xbps.d/*.conf "$ROOTFS"/etc/xbps.d/*.conf; do
        [[ -f $f ]] || continue
        grep -q 'repository' "$f" || continue
        out+=$(printf '\e[1;32m%s\e[0m\n%s\n\n' "${f#"$ROOTFS"}" "$(grep -v '^#' "$f")")
        out+=$'\n'
    done
    tui_pager "${out:-No se encontraron repositorios configurados.}"
}

config_mirror_apply() { # base sin /current
    local base=$1 f name url new n=0
    mkdir -p "$ROOTFS/etc/xbps.d"
    for f in "$ROOTFS"/usr/share/xbps.d/*.conf "$ROOTFS"/etc/xbps.d/*.conf; do
        [[ -f $f ]] || continue
        url=$(grep -m1 '^repository=' "$f" | cut -d= -f2-)
        [[ $url == *"/current"* ]] || continue
        name=$(basename "$f")
        new="$base/current${url#*/current}"
        sed -E "s|^repository=.*|repository=$new|" "$f" >"$WORK/repo.tmp" &&
            cat "$WORK/repo.tmp" >"$ROOTFS/etc/xbps.d/$name"
        n=$((n + 1))
    done
    rm -f "$WORK/repo.tmp"
    echo "$n"
}

config_mirror() {
    local vals=(https://repo-default.voidlinux.org https://repo-de.voidlinux.org
        https://repo-fi.voidlinux.org https://mirrors.servercentral.com/voidlinux)
    local names=("Automático (recomendado)" "Alemania" "Finlandia" "EE.UU. (servercentral)")
    ui_pick "Servidor de paquetes" vals names || return
    local base=${PICK_VALUE%/}
    local n
    n=$(config_mirror_apply "$base")
    if ((n == 0)); then
        tui_msg "No se encontró ningún repositorio para cambiar."
        return
    fi
    core_change "Servidor de paquetes: $base"
    tui_msg "Servidor cambiado en $n repositorio(s):
 $base"
}

config_repos() {
    local o=(
        "Ver repositorios actuales::Qué servidores usa la ISO para instalar programas"
        "Cambiar servidor (mirror)::Elige uno más cercano si la descarga va lenta"
        "Activar repositorio nonfree::Programas con licencia no libre (instala void-repo-nonfree)"
        "Activar repositorio multilib::Programas de 32 bits en glibc x86_64 (void-repo-multilib)")
    while tui_menu "Repositorios" "${o[@]}"; do
        case $MENU_SEL in
        0) config_repo_show ;;
        1) config_mirror ;;
        2) pkg_need_net && tui_shell_out pkg_exec "xbps-install -Sy void-repo-nonfree" && core_change "Repositorio nonfree activado" ;;
        3) pkg_need_net && tui_shell_out pkg_exec "xbps-install -Sy void-repo-multilib" && core_change "Repositorio multilib activado" ;;
        esac
    done
}

# ---- Módulos del kernel ----
config_module_add() { # archivo prefijo etiqueta
    tui_prompt "Nombre del módulo ($3)"
    local m=$REPLY_TXT f="$ROOTFS$1" line
    [[ $m =~ ^[a-zA-Z0-9_-]+$ ]] || { tui_msg "Nombre de módulo inválido."; return; }
    line="$2$m"
    mkdir -p "$(dirname "$f")"
    touch "$f"
    grep -qxF "$line" "$f" && { tui_msg "Ya estaba configurado."; return; }
    printf '%s\n' "$line" >>"$f"
    core_change "Módulo $m: $3"
    tui_msg "Hecho: $line"
}

config_modules() {
    local o=(
        "Desactivar un módulo (blacklist)::Ej: nouveau, pcspkr — evita que se cargue"
        "Cargar un módulo al arrancar::Ej: vboxguest, loop"
        "Ver lo configurado por Voidmaker::Listas actuales")
    while tui_menu "Módulos del kernel" "${o[@]}"; do
        case $MENU_SEL in
        0) config_module_add /etc/modprobe.d/voidmaker.conf "blacklist " "desactivar" ;;
        1) config_module_add /etc/modules-load.d/voidmaker.conf "" "cargar al inicio" ;;
        2)
            tui_pager "$(printf '\e[1mBlacklist\e[0m\n'; cat "$ROOTFS/etc/modprobe.d/voidmaker.conf" 2>/dev/null
                printf '\n\e[1mCargar al inicio\e[0m\n'; cat "$ROOTFS/etc/modules-load.d/voidmaker.conf" 2>/dev/null)"
            ;;
        esac
    done
}

config_menu() {
    core_require_loaded || return
    local o=(
        "Teclado::Distribución del teclado (sistema y arranque)"
        "Idioma::Idioma del sistema"
        "Zona horaria::Hora local"
        "Reloj del equipo::UTC u hora local"
        "Nombre del equipo::Hostname"
        "Repositorios y servidores::Mirror, nonfree, multilib"
        "Mensajes de bienvenida::Texto antes y después de iniciar sesión"
        "Módulos del kernel::Desactivar o cargar módulos")
    while tui_menu "Configuración del sistema" "${o[@]}"; do
        case $MENU_SEL in
        0) locale_keymap ;;
        1) locale_language ;;
        2) locale_timezone ;;
        3) config_hwclock ;;
        4) locale_hostname ;;
        5) config_repos ;;
        6) config_welcome ;;
        7) config_modules ;;
        esac
    done
}
