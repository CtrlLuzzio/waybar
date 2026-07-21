#!/usr/bin/env bash

SUPPORTED_TERMINALS="foot alacritty kitty konsole gnome-terminal xfce4-terminal"
OPENSUSE_ROLLING=("opensuse-tumbleweed", "opensuse-slowroll")
UPDATE_COMMAND=""
TXT_CLOSE="Press Enter to close the terminal..."
TXT_STARTING_UPDATES="Starting Updates..."
TXT_RUNNING="Running "
TXT_NO_TERMINAL="No supported terminal found"
TXT_FALLBACK_WARN="Running in the first supported terminal found"
TXT_FALLBACK_LIST="Supported terminal emulators:"
TXT_FALLBACK_HINT="To use a specific one, define the \$TERMINAL enviroment variable or configure xdg-terminal-exec"
TXT_PLEASE_USE="Please download one of the following terminal emulators"
TXT_NOT_FOUND="System package manager update command not found"
FLATPAK_UPDATES="Searching Flatpak updates..."
UNKNOWN_ZYPPER_DISTRO="Unknown Zypper-based distro. Not updating system packages for safety."
FORMATTED_LIST="\n  - ${SUPPORTED_TERMINALS// /\\n  - }"
SYS_LANG="${LANG:0:2}"

case "$SYS_LANG" in
    es)
        TXT_CLOSE="Presiona Enter para cerrar la terminal..."
        TXT_STARTING_UPDATES="Iniciando actualizaciones..."
        FLATPAK_UPDATES="Buscando actualizaciones de Flatpak..."
        TXT_RUNNING="Corriendo"
        TXT_NO_TERMINAL="No se encontró una terminal soportada por el script"
        TXT_PLEASE_USE="Por favor descargue uno de los siguientes emuladores de terminal:"
        TXT_NOT_FOUND="Comando de actualización del manejador de paquetes del sistema no encontrado"
        TXT_FALLBACK_WARN="Ejecutando en la primera terminal compatible encontrada"
        TXT_FALLBACK_HINT="Para usar una específica, define la variable de entorno \$TERMINAL o configura xdg-terminal-exec"
        TXT_FALLBACK_LIST="Emuladores de terminal soportados"
        UNKNOWN_ZYPPER_DISTRO="Distro basada en Zypper desconocida. No se actualizarán los paquetes del sistema por seguridad."
        ;;
esac

if command -v zypper &> /dev/null; then
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            "opensuse-tumbleweed"|"opensuse-slowroll")
                UPDATE_COMMAND="sudo zypper dup"
                ;;
            "opensuse-leap")
                UPDATE_COMMAND="sudo zypper up"
                ;;
            *)
                UPDATE_COMMAND=""
                TXT_NOT_FOUND="$UNKNOWN_ZYPPER_DISTRO"
                ;;
        esac
    fi
elif command -v dnf &> /dev/null; then
    UPDATE_COMMAND="sudo dnf upgrade"
elif command -v apt &> /dev/null; then
    UPDATE_COMMAND="sudo apt update && sudo apt upgrade"
elif command -v pacman &> /dev/null; then
    if command -v paru &> /dev/null; then
        UPDATE_COMMAND="paru -Syu"
    elif command -v yay &> /dev/null; then
        UPDATE_COMMAND="yay -Syu"
    elif command -v pikaur &> /dev/null; then
        UPDATE_COMMAND="pikaur -Syu"
    else
        UPDATE_COMMAND="sudo pacman -Syu"
    fi
fi

if command -v nix &> /dev/null || command -v nix-env &> /dev/null; then
    TARGET_FLAKE="${FLAKE_DIR:-/etc/nixos}"

    if [ -d "$TARGET_FLAKE" ] && [ -f "$TARGET_FLAKE/flake.nix" ]; then
        if command -v nixos-rebuild &> /dev/null; then
            HOST=$(hostname)
            REBUILD_CMD="sudo nixos-rebuild switch --flake $FLAKE_DIR#$HOST"
        elif command -v home-manager &> /dev/null; then
            REBUILD_CMD="home-manager switch --flake ."
        else
            REBUILD_CMD="nix profile upgrade '.*'"
        fi

        if [ -w "$TARGET_FLAKE/flake.nix" ]; then
            NIX_UPDATE_COMMAND="cd \"$TARGET_FLAKE\" && nix flake update && $REBUILD_CMD"
        else
            NIX_UPDATE_COMMAND="cd \"$TARGET_FLAKE\" && sudo nix flake update && $REBUILD_CMD"
        fi
    else
        if command -v nixos-rebuild &> /dev/null; then
            NIX_UPDATE_COMMAND="sudo nix-channel --update && sudo nixos-rebuild switch"
        elif command -v nix-env &> /dev/null; then
            NIX_UPDATE_COMMAND="nix-channel --update && nix-env -u"
        fi
    fi
fi

get_terminal() {
    if [ -n "$TERMINAL" ] && command -v "$TERMINAL" &> /dev/null; then
        echo "$TERMINAL"
        return
    fi

    if command -v xdg-terminal-exec &> /dev/null; then
        echo "xdg-terminal-exec"
        return
    fi

    for term in $SUPPORTED_TERMINALS; do
        if command -v "$term" &> /dev/null; then
            echo "$term"
            return
        fi
    done
}

TERM_EXEC=$(get_terminal)

if [ -z "$TERM_EXEC" ]; then
    if command -v notify-send &> /dev/null; then
        notify-send -u critical -i utilities-terminal "$TXT_NO_TERMINAL" "$(echo -e "$TXT_PLEASE_USE:$FORMATTED_LIST")"
    fi
    exit 1
fi

EXEC_PAYLOAD="echo '$TXT_STARTING_UPDATES'; echo '';"
if [ "$TERM_EXEC" != "$TERMINAL" ] && [ "$TERM_EXEC" != "xdg-terminal-exec" ]; then
    INFO_BLOCK="echo -e '\e[33m$TXT_FALLBACK_WARN ($TERM_EXEC).\e[0m'; echo -e '\e[33m$TXT_FALLBACK_LIST$FORMATTED_LIST\e[0m'; echo ''; echo -e '\e[33m$TXT_FALLBACK_HINT\e[0m'; echo '';"
    EXEC_PAYLOAD="$INFO_BLOCK $EXEC_PAYLOAD"
fi
if [ -n "$UPDATE_COMMAND" ]; then
    EXEC_PAYLOAD="$EXEC_PAYLOAD echo '$TXT_RUNNING $UPDATE_COMMAND'; echo ''; $UPDATE_COMMAND; echo '';"
elif [ -z "$NIX_UPDATE_COMMAND" ]; then
    EXEC_PAYLOAD="$EXEC_PAYLOAD echo '$TXT_NOT_FOUND'; echo '';"
fi
if [ -n "$NIX_UPDATE_COMMAND" ]; then
    EXEC_PAYLOAD="$EXEC_PAYLOAD echo '$TXT_RUNNING $NIX_UPDATE_COMMAND'; echo ''; $NIX_UPDATE_COMMAND; echo '';"
fi
if command -v flatpak &> /dev/null; then
    EXEC_PAYLOAD="$EXEC_PAYLOAD if [ \$(flatpak remote-ls --updates 2>/dev/null | wc -l) -gt 0 ]; then echo '$FLATPAK_UPDATES'; echo ''; flatpak update; echo ''; fi; "
fi
EXEC_PAYLOAD="$EXEC_PAYLOAD read -p '$TXT_CLOSE'"

if [ "$TERM_EXEC" = "xdg-terminal-exec" ]; then
    $TERM_EXEC bash -c "$EXEC_PAYLOAD"
else
    $TERM_EXEC -e bash -c "$EXEC_PAYLOAD"
fi
