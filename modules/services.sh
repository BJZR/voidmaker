#!/usr/bin/env bash
# Servicios runit de Void: /etc/sv (disponibles) y /etc/runit/runsvdir/default (activos).

svc_dir() { echo "$ROOTFS/etc/runit/runsvdir/default"; }

svc_enabled() { [[ -e $(svc_dir)/$1 || -L $(svc_dir)/$1 ]]; }

svc_list() {
    find "$ROOTFS/etc/sv" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -printf '%f\n' 2>/dev/null | sort
}

svc_enabled_list() { ls "$(svc_dir)" 2>/dev/null; }

svc_desc() {
    case $1 in
    sshd) echo "Acceso remoto por SSH" ;;
    dbus) echo "Bus de mensajes (lo necesitan los escritorios)" ;;
    elogind) echo "Sesiones de usuario (escritorios)" ;;
    lightdm) echo "Pantalla de inicio de sesión gráfica" ;;
    NetworkManager) echo "Gestor de red" ;;
    dhcpcd) echo "Red por cable (cliente DHCP)" ;;
    wpa_supplicant) echo "Wi-Fi básico" ;;
    bluetoothd) echo "Bluetooth" ;;
    cupsd) echo "Impresión" ;;
    chronyd) echo "Sincronizar la hora" ;;
    agetty-*) echo "Terminal de texto (${1#agetty-})" ;;
    *) echo "Servicio del sistema" ;;
    esac
}

# svc_set enable|disable nombre [quiet]
svc_set() {
    local act=$1 name=$2 quiet=${3:-}
    if [[ $act == enable ]]; then
        [[ -d $ROOTFS/etc/sv/$name ]] || {
            [[ -n $quiet ]] || tui_msg "El servicio $name no existe en la ISO."
            return 1
        }
        mkdir -p "$(svc_dir)"
        ln -sf "/etc/sv/$name" "$(svc_dir)/$name"
    else
        rm -f "$(svc_dir)/$name"
    fi
    [[ -n $quiet ]] || core_change "Servicio $name: $act"
}

services_menu() {
    core_require_loaded || return
    local svcs=() items=() s sel=0
    while true; do
        mapfile -t svcs < <(svc_list)
        ((${#svcs[@]})) || { tui_msg "No se encontraron servicios."; return; }
        items=()
        for s in "${svcs[@]}"; do
            if svc_enabled "$s"; then
                items+=("[✔] $s::ACTIVO al arrancar — $(svc_desc "$s").  Enter = desactivar")
            else
                items+=("[ ] $s::apagado — $(svc_desc "$s").  Enter = activar")
            fi
        done
        MENU_START=$sel
        tui_menu "Servicios (lo que arranca solo en tu ISO)" "${items[@]}" || break
        sel=$MENU_SEL
        s=${svcs[sel]}
        if svc_enabled "$s"; then svc_set disable "$s" quiet && core_change "Servicio $s: desactivado"
        else svc_set enable "$s" quiet && core_change "Servicio $s: activado"; fi
    done
}
