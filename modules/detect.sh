#!/usr/bin/env bash
# Comprueba que la ISO extraída es de Void Linux.

detect_void() {
    local d=$ISO_DIR
    [[ -f $d/LiveOS/squashfs.img ]] || return 1
    grep -rqi void "$d/boot" 2>/dev/null
}
