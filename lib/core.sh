#!/usr/bin/env bash
# Estado global y utilidades base.

WORK="${VOIDMAKER_WORK:-/var/tmp/voidmaker}"
ISO_DIR="$WORK/iso"
ROOTFS="$WORK/rootfs"
TMP="$WORK/tmp"
MNT="$WORK/mnt"
ISO_FILE=""
DISTRO=""

core_die() {
    tui_exit 2>/dev/null
    printf 'error: %s\n' "$*" >&2
    exit 1
}

core_need_root() {
    [[ $EUID -eq 0 ]] || core_die "ejecuta como root:  sudo ./voidmaker"
}

core_need_cmds() {
    local c missing=()
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    ((${#missing[@]} == 0)) && return 0
    core_die "faltan comandos: ${missing[*]}
En Void:  xbps-install -S xorriso squashfs-tools e2fsprogs"
}

core_workdirs() { mkdir -p "$ISO_DIR" "$ROOTFS" "$TMP" "$MNT"; }

core_require_loaded() {
    [[ -n $DISTRO ]] && return 0
    tui_msg "Primero carga una ISO de Void (opción \"Cargar ISO\")."
    return 1
}

core_save_state() {
    printf 'ISO_FILE=%q\nDISTRO=%q\n' "$ISO_FILE" "$DISTRO" >"$WORK/state"
}

core_load_state() {
    # shellcheck disable=SC1091
    [[ -f $WORK/state ]] && source "$WORK/state"
    return 0
}

# Registro de cambios (se muestra antes de crear la ISO)
core_change() { printf '%s  %s\n' "$(date +%H:%M)" "$*" >>"$WORK/changes.log"; }
core_changes_count() { [[ -f $WORK/changes.log ]] && wc -l <"$WORK/changes.log" || echo 0; }

core_safe_relpath() { [[ -n $1 && $1 != *..* ]]; }

core_editor() { command -v "${EDITOR:-}" 2>/dev/null || command -v nano || command -v vi; }

# core_conf_set archivo CLAVE valor   (formato CLAVE="valor")
core_conf_set() {
    local f=$1 k=$2 v=$3
    touch "$f"
    if grep -qE "^#?[[:space:]]*$k=" "$f"; then
        sed -Ei "s|^#?[[:space:]]*$k=.*|$k=\"$v\"|" "$f"
    else
        printf '%s="%s"\n' "$k" "$v" >>"$f"
    fi
}

# Copia de seguridad (una sola vez) de un archivo de la ISO o del sistema
core_backup() {
    local f=$1 base rel dst
    case $f in
    "$ISO_DIR"/*) base=iso; rel=${f#"$ISO_DIR"/} ;;
    "$ROOTFS"/*) base=rootfs; rel=${f#"$ROOTFS"/} ;;
    *) return 0 ;;
    esac
    [[ -f $f ]] || return 0
    dst=$WORK/backup/$base/$rel
    [[ -e $dst ]] && return 0
    mkdir -p "$(dirname "$dst")"
    cp -a "$f" "$dst"
}

core_check_net() {
    timeout 5 bash -c 'exec 3<>/dev/tcp/repo-default.voidlinux.org/443' 2>/dev/null
}

core_cleanup() {
    chroot_umount
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT"
    tui_exit
}
