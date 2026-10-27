#!/usr/bin/env bash
# Usuarios, contraseñas, grupos y sudo.
# Edita directamente passwd/shadow/group/gshadow: no depende de useradd ni chpasswd.

users_f() { echo "$ROOTFS/etc/$1"; }

users_append() { # archivo línea
    local f=$1
    [[ -f $f ]] || : >"$f"
    [[ -n $(tail -c1 "$f") ]] && printf '\n' >>"$f"
    printf '%s\n' "$2" >>"$f"
}

users_exists() { awk -F: -v u="$1" '$1==u{f=1} END{exit !f}' "$(users_f passwd)" 2>/dev/null; }

users_valid_name() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

users_hash() { # contraseña -> hash SHA-512
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$1" | openssl passwd -6 -stdin 2>/dev/null
    elif command -v mkpasswd >/dev/null 2>&1; then
        printf '%s' "$1" | mkpasswd -m sha-512 -s 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        P=$1 python3 -c 'import crypt,os; print(crypt.crypt(os.environ["P"], crypt.mksalt(crypt.METHOD_SHA512)))' 2>/dev/null
    else
        return 1
    fi
}

users_next_id() {
    cat "$(users_f passwd)" "$(users_f group)" 2>/dev/null |
        awk -F: '$3>=1000 && $3<60000 && $3>m {m=$3} END{print (m ? m+1 : 1000)}'
}

users_set_password() { # usuario hash
    local u=$1 h=$2 sf tmp="$WORK/users.tmp" days
    sf=$(users_f shadow)
    days=$(($(date +%s) / 86400))
    if awk -F: -v u="$u" '$1==u{f=1} END{exit !f}' "$sf" 2>/dev/null; then
        H=$h D=$days awk -F: -v OFS=: -v u="$u" \
            '$1==u{$2=ENVIRON["H"]; $3=ENVIRON["D"]} {print}' "$sf" >"$tmp" && cat "$tmp" >"$sf"
    else
        users_append "$sf" "$u:$h:$days:0:99999:7:::"
    fi
    rm -f "$tmp"
}

# users_member_edit archivo(group|gshadow) add|del grupo(""=todos) usuario
users_member_edit() {
    local f tmp="$WORK/users.tmp"
    f=$(users_f "$1")
    [[ -f $f ]] || return 0
    awk -F: -v OFS=: -v act="$2" -v g="$3" -v u="$4" '
        $1==g || g=="" {
            n=split($4,a,","); out=""; found=0
            for(i=1;i<=n;i++){
                if(a[i]=="") continue
                if(a[i]==u){ found=1; if(act=="del") continue }
                out = out (out==""?"":",") a[i]
            }
            if(act=="add" && !found) out = out (out==""?"":",") u
            $4=out
        }
        {print}' "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
}

users_in_group() { # usuario grupo
    awk -F: -v g="$2" -v u="$1" '$1==g{n=split($4,a,","); for(i=1;i<=n;i++) if(a[i]==u) f=1} END{exit !f}' \
        "$(users_f group)" 2>/dev/null
}

users_add() { # nombre hash shell grupos(csv)
    local u=$1 h=$2 sh=$3 groups=$4 id home g days gl=()
    id=$(users_next_id)
    home=/home/$u
    days=$(($(date +%s) / 86400))
    users_append "$(users_f passwd)" "$u:x:$id:$id:$u:$home:$sh"
    users_append "$(users_f group)" "$u:x:$id:"
    [[ -f $(users_f gshadow) ]] && users_append "$(users_f gshadow)" "$u:!::"
    users_append "$(users_f shadow)" "$u:$h:$days:0:99999:7:::"
    IFS=, read -ra gl <<<"$groups"
    for g in "${gl[@]}"; do
        [[ -n $g ]] || continue
        users_member_edit group add "$g" "$u"
        users_member_edit gshadow add "$g" "$u"
    done
    mkdir -p "$ROOTFS$home"
    [[ -d $ROOTFS/etc/skel ]] && cp -a "$ROOTFS/etc/skel/." "$ROOTFS$home/"
    chown -R "$id:$id" "$ROOTFS$home"
    chmod 700 "$ROOTFS$home"
}

users_line_delete() { # archivo usuario
    local f tmp="$WORK/users.tmp"
    f=$(users_f "$1")
    [[ -f $f ]] || return 0
    awk -F: -v u="$2" '$1!=u' "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
}

users_remove() { # usuario borrar_home(0|1)
    local u=$1 delhome=$2 home gid tmp="$WORK/users.tmp"
    home=$(awk -F: -v u="$u" '$1==u{print $6}' "$(users_f passwd)")
    gid=$(awk -F: -v u="$u" '$1==u{print $4}' "$(users_f passwd)")
    users_line_delete passwd "$u"
    users_line_delete shadow "$u"
    users_member_edit group del "" "$u"
    users_member_edit gshadow del "" "$u"
    # grupo privado vacío con el mismo nombre
    if awk -F: -v g="$u" -v gid="$gid" '$1==g && $3==gid && $4=="" {f=1} END{exit !f}' "$(users_f group)"; then
        users_line_delete group "$u"
        users_line_delete gshadow "$u"
    fi
    if ((delhome)) && [[ $home == /home/?* && $home != *..* ]]; then
        rm -rf -- "${ROOTFS:?}$home"
    fi
    rm -f "$tmp"
}

users_set_shell() { # usuario shell
    local f tmp="$WORK/users.tmp"
    f=$(users_f passwd)
    awk -F: -v OFS=: -v u="$1" -v s="$2" '$1==u{$7=s} {print}' "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
}

users_regular() { awk -F: '$3>=1000 && $3<60000 {print $1}' "$(users_f passwd)"; }
users_login_list() { awk -F: '$3==0 || ($3>=1000 && $3<60000) {print $1}' "$(users_f passwd)"; }

users_groups_of() {
    awk -F: -v u="$1" '{n=split($4,a,","); for(i=1;i<=n;i++) if(a[i]==u) printf "%s ", $1} END{print ""}' \
        "$(users_f group)"
}

# users_pick regular|todos  -> PICK_VALUE
users_pick() {
    local us=() items=() u uid sh
    if [[ $1 == regular ]]; then mapfile -t us < <(users_regular); else mapfile -t us < <(users_login_list); fi
    ((${#us[@]})) || { tui_msg "No hay usuarios para elegir."; return 1; }
    for u in "${us[@]}"; do
        uid=$(awk -F: -v u="$u" '$1==u{print $3}' "$(users_f passwd)")
        sh=$(awk -F: -v u="$u" '$1==u{print $7}' "$(users_f passwd)")
        items+=("$u::uid $uid · shell $sh · grupos: $(users_groups_of "$u")")
    done
    tui_menu "Elige un usuario" "${items[@]}" || return 1
    PICK_VALUE=${us[MENU_SEL]}
}

users_pick_shell() { # -> PICK_VALUE
    local shells=() items=() s i
    while IFS= read -r s; do
        [[ $s == /* && -x $ROOTFS$s && $s != *nologin* && $s != */false ]] && shells+=("$s")
    done < <(grep -v '^#' "$ROOTFS/etc/shells" 2>/dev/null)
    ((${#shells[@]})) || shells=(/bin/sh)
    for i in "${!shells[@]}"; do
        items+=("${shells[i]}::Intérprete de comandos")
        [[ ${shells[i]} == /bin/bash ]] && MENU_START=$i
    done
    tui_menu "Shell (intérprete de comandos)" "${items[@]}" || return 1
    PICK_VALUE=${shells[MENU_SEL]}
}

users_ask_password() { # usuario -> PICK_VALUE = hash
    local p1 p2 h
    tui_secret "Contraseña para $1"
    p1=$REPLY_TXT
    tui_secret "Repite la contraseña"
    p2=$REPLY_TXT
    if [[ -z $p1 || $p1 != "$p2" ]]; then
        tui_msg "Las contraseñas no coinciden o están vacías."
        return 1
    fi
    h=$(users_hash "$p1")
    if [[ $h != '$6$'* ]]; then
        tui_msg "No hay herramienta para cifrar contraseñas (instala openssl en tu equipo)."
        return 1
    fi
    PICK_VALUE=$h
}

users_show() {
    local out u
    out=$(printf '\e[1;32mUsuarios de la ISO\e[0m\n\n')
    while IFS=: read -r u uid home sh; do
        out+=$(printf '\n  \e[1m%s\e[0m  (uid %s)\n    carpeta: %s\n    shell:   %s\n    grupos:  %s\n' \
            "$u" "$uid" "$home" "$sh" "$(users_groups_of "$u")")
    done < <(awk -F: '$3==0 || ($3>=1000 && $3<60000) {print $1":"$3":"$6":"$7}' "$(users_f passwd)")
    tui_pager "$out"
}

users_create() {
    tui_prompt "Nombre del usuario nuevo (minúsculas, sin espacios)"
    local u=$REPLY_TXT admin g groups=() sh gl
    users_valid_name "$u" || { tui_msg "Nombre inválido. Usa minúsculas, números, _ o - (máx. 32)."; return; }
    users_exists "$u" && { tui_msg "Ya existe un usuario llamado $u."; return; }
    tui_menu "Tipo de usuario" \
        "Administrador::Puede usar sudo (grupo wheel) y accede a sonido, video, red..." \
        "Normal::Sin permisos de administrador; sonido, video y red" || return
    admin=$((MENU_SEL == 0))
    users_pick_shell || return
    sh=$PICK_VALUE
    users_ask_password "$u" || return
    local hash=$PICK_VALUE
    local want=(audio video input network storage optical)
    ((admin)) && want=(wheel "${want[@]}")
    for g in "${want[@]}"; do
        grep -q "^$g:" "$(users_f group)" && groups+=("$g")
    done
    gl=$(IFS=,; echo "${groups[*]}")
    users_add "$u" "$hash" "$sh" "$gl"
    if users_exists "$u" && [[ -d $ROOTFS/home/$u ]]; then
        core_change "Usuario creado: $u ($( ((admin)) && echo administrador || echo normal ); grupos: ${gl:-ninguno})"
        tui_msg "Usuario $u creado.
 Carpeta: /home/$u · Shell: $sh
 Grupos: ${gl:-ninguno}$( ((admin)) && [[ ! -f $ROOTFS/etc/sudoers.d/10-voidmaker-wheel ]] &&
            printf '\n\n Para que sudo funcione, actívalo en: Usuarios > Permisos de administrador (sudo).')"
    else
        tui_msg "No se pudo crear el usuario. Revisa los permisos de $WORK."
    fi
}

users_password() {
    users_pick todos || return
    local u=$PICK_VALUE
    users_ask_password "$u" || return
    users_set_password "$u" "$PICK_VALUE"
    core_change "Contraseña cambiada: $u"
    tui_msg "Contraseña de $u cambiada."
}

users_group_desc() {
    case $1 in
    wheel) echo "Administrador (puede usar sudo)" ;;
    audio) echo "Sonido" ;;
    video) echo "Pantalla, cámara, aceleración gráfica" ;;
    input) echo "Teclado y ratón (Wayland)" ;;
    network) echo "Red" ;;
    storage) echo "Discos y USB" ;;
    optical) echo "CD/DVD" ;;
    cdrom) echo "Unidades de CD" ;;
    floppy) echo "Disquetera" ;;
    kvm) echo "Máquinas virtuales (KVM)" ;;
    lp) echo "Impresoras" ;;
    scanner) echo "Escáneres" ;;
    plugdev) echo "Dispositivos extraíbles" ;;
    dialout) echo "Puertos serie" ;;
    users) echo "Grupo general de usuarios" ;;
    *) echo "Grupo del sistema" ;;
    esac
}

users_groups_menu() {
    users_pick regular || return
    local u=$PICK_VALUE g items sel=0 known=(wheel audio video input network storage optical cdrom floppy kvm lp scanner plugdev dialout users) avail=()
    for g in "${known[@]}"; do grep -q "^$g:" "$(users_f group)" && avail+=("$g"); done
    ((${#avail[@]})) || { tui_msg "No se encontraron grupos."; return; }
    while true; do
        items=()
        for g in "${avail[@]}"; do
            if users_in_group "$u" "$g"; then
                items+=("[✔] $g::PERTENECE — $(users_group_desc "$g").  Enter = quitar")
            else
                items+=("[ ] $g::no pertenece — $(users_group_desc "$g").  Enter = añadir")
            fi
        done
        MENU_START=$sel
        tui_menu "Grupos de $u" "${items[@]}" || break
        sel=$MENU_SEL
        g=${avail[sel]}
        if users_in_group "$u" "$g"; then
            users_member_edit group del "$g" "$u"; users_member_edit gshadow del "$g" "$u"
            core_change "Grupo $g: quitado a $u"
        else
            users_member_edit group add "$g" "$u"; users_member_edit gshadow add "$g" "$u"
            core_change "Grupo $g: añadido a $u"
        fi
    done
}

users_sudo_set() { # pass|nopass
    local f="$ROOTFS/etc/sudoers.d/10-voidmaker-wheel" line='%wheel ALL=(ALL:ALL) ALL'
    [[ $1 == nopass ]] && line='%wheel ALL=(ALL:ALL) NOPASSWD: ALL'
    mkdir -p "$ROOTFS/etc/sudoers.d"
    printf '%s\n' "$line" >"$f"
    chmod 440 "$f"
    if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$f" >/dev/null 2>&1; then
        rm -f "$f"
        tui_msg "El archivo de sudo no pasó la validación; no se aplicó."
        return 1
    fi
    if [[ -f $ROOTFS/etc/sudoers ]] &&
        ! grep -Eqs '^[#@]includedir[[:space:]]+/etc/sudoers.d' "$ROOTFS/etc/sudoers"; then
        printf '\n@includedir /etc/sudoers.d\n' >>"$ROOTFS/etc/sudoers"
    fi
}

users_sudo_menu() {
    core_require_loaded || return
    local f="$ROOTFS/etc/sudoers.d/10-voidmaker-wheel" state has
    while true; do
        if [[ -f $f ]]; then
            grep -q NOPASSWD "$f" && state="ACTIVO sin contraseña" || state="ACTIVO pidiendo contraseña"
        else
            state="desactivado"
        fi
        [[ -x $ROOTFS/usr/bin/sudo ]] && has="instalado" || has="NO instalado"
        tui_menu "Sudo: $state · programa sudo: $has" \
            "Activar sudo (pide contraseña)::Los del grupo wheel podrán usar sudo" \
            "Activar sudo SIN contraseña::Cómodo, pero menos seguro" \
            "Desactivar sudo para wheel::Quita el permiso" \
            "Instalar el programa sudo::Necesita Internet" || break
        case $MENU_SEL in
        0) users_sudo_set pass && core_change "Sudo activado para wheel (con contraseña)" ;;
        1) users_sudo_set nopass && core_change "Sudo activado para wheel (sin contraseña)" ;;
        2) rm -f "$f"; core_change "Sudo desactivado para wheel" ;;
        3) pkg_need_net && tui_shell_out pkg_exec "xbps-install -Sy sudo" && core_change "Instalado: sudo" ;;
        esac
    done
}

users_shell() {
    users_pick todos || return
    local u=$PICK_VALUE
    users_pick_shell || return
    users_set_shell "$u" "$PICK_VALUE"
    core_change "Shell de $u: $PICK_VALUE"
    tui_msg "Shell de $u: $PICK_VALUE"
}

users_delete() {
    users_pick regular || return
    local u=$PICK_VALUE
    tui_confirm "¿Borrar al usuario $u?" || return
    local dh=0
    tui_confirm "¿Borrar también su carpeta /home/$u?" && dh=1
    users_remove "$u" "$dh"
    core_change "Usuario borrado: $u"
    tui_msg "Usuario $u borrado."
}

users_menu() {
    core_require_loaded || return
    local o=(
        "Ver usuarios::Lista con carpeta, shell y grupos"
        "Crear usuario nuevo::Administrador o normal, con contraseña"
        "Cambiar contraseña::root, anon o cualquier usuario"
        "Grupos y permisos de un usuario::Sonido, video, red, administrador..."
        "Permisos de administrador (sudo)::Activar sudo para el grupo wheel"
        "Cambiar shell de un usuario::bash, sh..."
        "Borrar usuario::Quita la cuenta y, si quieres, su carpeta")
    while tui_menu "Usuarios y contraseñas" "${o[@]}"; do
        case $MENU_SEL in
        0) users_show ;;
        1) users_create ;;
        2) users_password ;;
        3) users_groups_menu ;;
        4) users_sudo_menu ;;
        5) users_shell ;;
        6) users_delete ;;
        esac
    done
}
