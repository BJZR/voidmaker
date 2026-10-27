#!/usr/bin/env bash
# Pantalla de ayuda.

help_run() {
    tui_pager "$(cat <<'TXT'
QUÉ PUEDES MODIFICAR CON VOIDMAKER

  Programas            Lista de programas editable en un txt (borra líneas para quitar,
                       añade líneas para instalar), paquetes listos (XFCE, i3, Firefox...),
                       instalar/quitar/buscar/actualizar y limpiar descargas.
  Usuarios             Crear (administrador o normal), cambiar contraseñas, grupos,
                       permisos de sudo, shell y borrar usuarios.
  Servicios            Elegir qué arranca solo (runit): red, SSH, escritorio...
  Configuración        Teclado, idioma, zona horaria, reloj, nombre del equipo,
                       repositorios (mirror/nonfree/multilib), mensajes de bienvenida
                       y módulos del kernel.
  Menú de arranque     Nombres del menú, parámetros del kernel (nomodeset, quiet...),
                       edición manual de grub/isolinux y restaurar el original.
  Archivos             Añadir, editar o borrar cualquier archivo del sistema.
  Terminal             Entrar al sistema de la ISO para hacer cualquier cosa.

CÓMO TRABAJAR

  1. Carga una ISO de Void (Cargar ISO).
  2. Personaliza lo que quieras (cada cambio se anota).
  3. Crea la ISO nueva. Pruébala primero en una máquina virtual:
       qemu-system-x86_64 -m 2G -enable-kvm -cdrom tu-iso.iso

LISTA DE PROGRAMAS (Programas > Lista de programas)

  Se abre un txt con los programas instalados. Borra las líneas de lo que
  no quieras y escribe los nombres de lo que quieras añadir. Al cerrar el
  editor verás un resumen (QUITAR / INSTALAR) y confirmas antes de aplicar.

TECLAS

  ↑/↓ o j/k moverse · Enter elegir · q o Esc volver · 1-9 saltar a una opción

NOTAS

  · Tu trabajo se guarda en /var/tmp/voidmaker; puedes cerrar y volver luego.
  · "Descartar todos los cambios" vuelve a la ISO original.
  · Instalar programas necesita Internet.
  · La ISO original debe seguir en su lugar al crear la nueva.
  · Solo funciona con ISOs live de Void Linux.
TXT
)"
}
