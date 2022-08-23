#!/bin/bash

shell_join() {
    local arg
    printf "%s" "$1"
    shift
    for arg in "$@"; do
        printf " "
        printf "%s" "${arg// /\ }"
    done
}

chomp() {
    printf "%s" "${1/"$'\n'"/}"
}

ohai() {
    printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
    printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

# Search for the given executable in PATH (avoids a dependency on the `which` command)
which() {
    # Alias to Bash built-in command `type -P`
    type -P "$@"
}

# Search PATH for the specified program
# function which is set above
find_tool() {
    if [[ $# -ne 1 ]]; then
        return 1
    fi

    local executable
    while read -r executable; do
        if "test_$1" "${executable}"; then
            echo "${executable}"
            break
        fi
    done < <(which -a "$1")
}

execute() {
    if ! "$@"; then
        abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
    fi
}

function save_var() {
    local key="${1}"
    local value="${2}"

    echo "${key}=${value}" >>.env
    export ${key}="${value}"
}

function update_var() {
    local key="${1}"
    local value="${2}"

    sed -i "s/^${key}=.*/${key}=${value}/" .env
    export ${key}="${value}"
}

function print_header() {
    local messages=("${@}")

    echo
    echo "-------------------------------------------------"
    for message in "${messages[@]}"; do
        echo "${message}"
    done
    echo "-------------------------------------------------"
    echo
}

function reboot_after_delay() {
    local delay="${1}"

    ohai "Rebooting in ${delay} seconds..." "Press CTRL+C to cancel the reboot"
    for i in {1..${delay}}; do
        ohai "Rebooting in ${delay} seconds ..."
        sleep 1
        delay=$((delay - 1))
    done

    reboot now
}

function cleanup() {
    unset ISO
    unset PKGS
    unset SERVICES
    unset DE_PKGS
    unset DE_SERVICES
    unset DE
}

have_sudo_access() {
    unset HAVE_SUDO_ACCESS

    if [[ ! -x "/usr/bin/sudo" ]]; then
        return 1
    fi

    local -a SUDO=("/usr/bin/sudo")
    if [[ -n "${SUDO_ASKPASS-}" ]]; then
        SUDO+=("-A")
    elif [[ -n "${NONINTERACTIVE-}" ]]; then
        SUDO+=("-n")
    fi

    if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
        if [[ -n "${NONINTERACTIVE-}" ]]; then
            "${SUDO[@]}" -l mkdir &>/dev/null
        else
            "${SUDO[@]}" -v && "${SUDO[@]}" -l mkdir &>/dev/null
        fi
        HAVE_SUDO_ACCESS="$?"
    fi

    return "${HAVE_SUDO_ACCESS}"
}

execute_sudo() {
    local -a args=("$@")
    if have_sudo_access; then
        if [[ -n "${SUDO_ASKPASS-}" ]]; then
            args=("-A" "${args[@]}")
        fi
        ohai "/usr/bin/sudo" "${args[@]}"
        execute "/usr/bin/sudo" "${args[@]}"
    else
        ohai "${args[@]}"
        execute "${args[@]}"
    fi
}

getc() {
    local save_state
    save_state="$(/bin/stty -g)"
    /bin/stty raw -echo
    IFS='' read -r -n 1 -d '' "$@"
    /bin/stty "${save_state}"
}

wait_for_user() {
    local c
    echo
    echo "Press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
    getc c
    # we test for \r and \n because some stuff does \r instead
    if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]; then
        exit 1
    fi
}
