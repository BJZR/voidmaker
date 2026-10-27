#!/usr/bin/env bash
# TUI amigable en bash puro (ANSI + read).

MENU_SEL=-1
MENU_START=0
REPLY_TXT=""
PICK_VALUE=""

tui_init() { tput smcup; tput civis; stty -echo; }

tui_exit() {
    stty echo 2>/dev/null
    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
}

tui_header() {
    printf '\e[H\e[J'
    printf '\e[1;32m  ▌VOIDMAKER\e[0m \e[2m· %s\e[0m\n' "$1"
    declare -F ui_status >/dev/null && ui_status
    printf '\e[2m%*s\e[0m\n\n' "$(tput cols)" '' | tr ' ' '─'
}

# tui_menu "titulo" "Etiqueta::descripción" ...  -> MENU_SEL ; retorna 1 con q / Esc
tui_menu() {
    local title=$1
    shift
    local labels=() descs=() it
    for it in "$@"; do
        labels+=("${it%%::*}")
        if [[ $it == *::* ]]; then descs+=("${it#*::}"); else descs+=(""); fi
    done
    local n=${#labels[@]} sel=${MENU_START:-0} top=0 key i rows view
    MENU_START=0
    ((sel >= n)) && sel=0
    while true; do
        rows=$(tput lines)
        view=$((rows - 10))
        ((view < 3)) && view=3
        ((sel < top)) && top=$sel
        ((sel >= top + view)) && top=$((sel - view + 1))
        tui_header "$title"
        for ((i = top; i < top + view && i < n; i++)); do
            if ((i == sel)); then
                printf ' \e[1;30;42m ▶ %s \e[0m\n' "${labels[i]}"
            else
                printf '     %s\n' "${labels[i]}"
            fi
        done
        printf '\e[%d;1H\e[36m %s\e[0m' $((rows - 3)) "${descs[sel]}"
        printf '\e[%d;1H\e[2m ↑/↓ moverse   Enter elegir   q volver   (1-9 saltar)\e[0m' $((rows - 1))
        IFS= read -rsn1 key
        case $key in
        $'\e')
            if read -rsn2 -t 0.05 key; then
                case $key in
                '[A') ((sel = (sel - 1 + n) % n)) ;;
                '[B') ((sel = (sel + 1) % n)) ;;
                esac
            else
                MENU_SEL=-1
                return 1
            fi
            ;;
        k) ((sel = (sel - 1 + n) % n)) ;;
        j) ((sel = (sel + 1) % n)) ;;
        [1-9]) ((key <= n)) && sel=$((key - 1)) ;;
        q)
            MENU_SEL=-1
            return 1
            ;;
        '')
            MENU_SEL=$sel
            return 0
            ;;
        esac
    done
}

# ui_pick "titulo" valores nombres -> PICK_VALUE (arrays por nombre); 1 si cancela
ui_pick() {
    local title=$1
    local -n _vals=$2 _names=$3
    local items=() i
    for i in "${!_vals[@]}"; do items+=("${_names[i]}::código: ${_vals[i]}"); done
    items+=("Otro (escribirlo a mano)::Escribe tú el valor")
    tui_menu "$title" "${items[@]}" || return 1
    if ((MENU_SEL < ${#_vals[@]})); then
        PICK_VALUE=${_vals[MENU_SEL]}
    else
        tui_prompt "Valor"
        PICK_VALUE=$REPLY_TXT
    fi
    [[ -n $PICK_VALUE ]]
}

# tui_prompt "etiqueta" ["valor por defecto"] -> REPLY_TXT
tui_prompt() {
    tput cnorm
    stty echo
    printf '\n'
    read -e -r -p "  $1: " -i "${2:-}" REPLY_TXT
    stty -echo
    tput civis
    REPLY_TXT=${REPLY_TXT/#\~/$HOME}
}

# tui_secret "etiqueta" -> REPLY_TXT (sin eco)
tui_secret() {
    tput cnorm
    printf '\n  %s: ' "$1"
    read -rs REPLY_TXT
    printf '\n'
    tput civis
}

tui_ok() { printf '\e[32m ✔ %s\e[0m\n' "$*"; }
tui_warn() { printf '\e[33m ! %s\e[0m\n' "$*"; }
tui_err() { printf '\e[31m ✘ %s\e[0m\n' "$*"; }

tui_msg() {
    printf '\n %s\n\n\e[2m [Enter para continuar]\e[0m' "$1"
    IFS= read -rsn1 _
}

tui_confirm() {
    local k
    printf '\n %s \e[2m[s/N]\e[0m ' "$1"
    IFS= read -rsn1 k
    [[ $k == [sSyY] ]]
}

tui_pager() {
    tput cnorm
    stty echo
    if command -v less >/dev/null 2>&1; then
        printf '%s\n' "$1" | less -R
    else
        printf '%s\n' "$1"
        read -r -p ' [Enter]' _
    fi
    stty -echo
    tput civis
}

# Sale de la pantalla de la TUI, ejecuta y vuelve.
tui_shell_out() {
    tput rmcup
    tput cnorm
    stty echo
    "$@"
    local rc=$?
    stty -echo
    tput civis
    tput smcup
    return $rc
}

tui_wait() { printf '\n\e[2m [Enter para volver]\e[0m'; read -r _; }
