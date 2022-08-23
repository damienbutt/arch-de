#!/bin/bash

set -u

abort() {
    printf "%s\n" "$@" >&2
    exit 1
}

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
if [ -z "${BASH_VERSION:-}" ]; then
    abort "Bash is required to interpret this script."
fi

if [[ -n "${INTERACTIVE-}" && -n "${NONINTERACTIVE-}" ]]; then
    abort 'Both `$INTERACTIVE` and `$NONINTERACTIVE` are set. Please unset at least one variable and try again.'
fi

# Check if script is run in POSIX mode
if [[ -n "${POSIXLY_CORRECT+1}" ]]; then
    abort 'Bash must not run in POSIX mode. Please unset POSIXLY_CORRECT and try again.'
fi

# Check cURL is installed
if ! command -v curl &>/dev/null; then
    abort "$(
        cat <<EOABORT
You must install cURL before running this script. Run the following command:
  ${tty_underline}pacman -S curl${tty_reset}
EOABORT
    )"
fi

# Check Paru is installed
if ! command -v paru &>/dev/null; then
    abort "$(
        cat <<EOABORT
You must install Paru before running this script. See:
${tty_underline}https://aur.archlinux.org/packages/paru-bin${tty_reset}
EOABORT
    )"
fi

# Download dependencies
curl -fsSL https://raw.githubusercontent.com/damienbutt/arch-de/HEAD/scripts/arch-de-utils.sh >~/arch-de-utils.sh
source ~/arch-de-utils.sh

# Check if script is run non-interactively (e.g. CI)
# If it is run non-interactively we should not prompt for passwords.
# Always use single-quoted strings with `exp` expressions
if [[ -z "${NONINTERACTIVE-}" ]]; then
    if [[ -n "${CI-}" ]]; then
        warn 'Running in non-interactive mode because `$CI` is set.'
        NONINTERACTIVE=1
    elif [[ ! -t 0 ]]; then
        if [[ -z "${INTERACTIVE-}" ]]; then
            warn 'Running in non-interactive mode because `stdin` is not a TTY.'
            NONINTERACTIVE=1
        else
            warn 'Running in interactive mode despite `stdin` not being a TTY because `$INTERACTIVE` is set.'
        fi
    fi
else
    ohai 'Running in non-interactive mode because `$NONINTERACTIVE` is set.'
fi

# USER isn't always set so provide a fall back for the installer and subprocesses.
if [[ -z "${USER-}" ]]; then
    USER="$(chomp "$(id -un)")"
    export USER
fi

# First check OS.
OS="$(uname)"
if [[ "${OS}" != "Linux" ]]; then
    abort "This script can only be run on Linux!"
fi

# String Formatters
if [[ -t 1 ]]; then
    tty_escape() { printf "\033[%sm" "$1"; }
else
    tty_escape() { :; }
fi

tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

ohai 'Checking for `sudo` access (which may request your password)...'
if ! have_sudo_access; then
    abort 'Insufficient permissions. You must have `sudo` access to run this script.'
fi

clear

PS3="Select desktop environment: "
select OPT in gnome kde cinnamon xfce quit; do
    case ${OPT} in
    gnome)
        ohai "Selected gnome"
        DE_PKGS=(
            'gdm'
            'gnome'
            'gnome-tweaks'
            'gnome-themes-extra'
            'gnome-software-packagekit-plugin'
            'gnome-browser-connector'
        )

        DE_SERVICES=(
            'gdm'
        )

        DE='gnome'

        break
        ;;
    kde)
        ohai "Selected kde"
        DE_PKGS=(
            'sddm'
            'plasma'
            'plasma-wayland-session'
            'kde-utilities'
        )

        DE_SERVICES=(
            'sddm'
        )

        DE='kde'

        break
        ;;
    cinnamon)
        ohai "Selected cinnamon"
        DE_PKGS=(
            'lightdm'
            'lightdm-gtk-greeter'
            'lightdm-gtk-greeter-settings'
            'cinnamon'
            'metacity'
            'gnome-shell'
        )

        DE_SERVICES=(
            'lightdm'
        )

        DE='cinnamon'

        break
        ;;
    xfce)
        ohai "Selected xfce"
        DE_PKGS=(
            'lightdm'
            'lightdm-gtk-greeter'
            'lightdm-gtk-greeter-settings'
            'xfce4'
        )

        DE_SERVICES=(
            'lightdm'
        )

        DE='xfce'

        break
        ;;
    quit)
        abort "Aborting installation"
        ;;
    *)
        echo "Invalid option. Try another one."
        ;;
    esac
done

# Start the actual installation
clear
ohai "Starting Arch-DE installation"

ohai "Detecting your country"
ISO=$(curl -s ifconfig.co/country-iso)

ohai "Setting up the best mirrors for ${ISO}"
execute_sudo "reflector" "-a" "48" "-c" "${ISO}" "-f" "5" "-l" "20" "--sort" "rate" "--save" "/etc/pacman.d/mirrorlist" &>/dev/null
execute "paru" "-Syyy" &>/dev/null

ohai "Setting up firewall with sensible defaults"
execute_sudo "firewall-cmd" "--add-port=1025-65535/tcp" "--permanent" &>/dev/null
execute_sudo "firewall-cmd" "--add-port=1025-65535/udp" "--permanent" &>/dev/null
execute_sudo "firewall-cmd" "--reload" &>/dev/null

ohai "Installing common packages"
PKGS=(
    # Display server
    'xorg'

    # Bluetooth support
    'bluez'
    'bluez-utils'

    # Printer support
    'cups'
    'hplip'

    # Audio support
    'alsa-utils'
    'pipewire'
    'pipewire-alsa'
    'pipewire-pulse'
    'pipewire-jack'

    # Misc.
    'firefox'
    'archlinux-wallpaper'

    # Snapshots
    'snapper-gui-git'
    'snapper-rollback'

    # Package management
    'flatpak'
    'packagekit'
)

for PKG in "${PKGS[@]}"; do
    ohai "Installing: ${PKG}"
    execute "paru" "-S" "${PKG}" "--noconfirm" "--needed"
done

ohai "Installing ${DE} packages"
for PKG in "${DE_PKGS[@]}"; do
    ohai "Installing: ${PKG}"
    execute "paru" "-S" "${PKG}" "--noconfirm" "--needed"
done

ohai "Detecting your video hardware"
if lspci | grep -E "NVIDIA|GeForce"; then
    ohai "Installing: nvidia drivers"
    execute "paru" "-S" "nvidia" "nvidia-settings" "nvidia-utils" "--noconfirm" "--needed"
    if [ ${DE} == 'kde' ]; then
        ohai "Installing: nvidia-settings-daemon"
        execute "paru" "-S" "egl-wayland" "--noconfirm" "--needed"
    fi
elif lspci | grep -E "Radeon"; then
    ohai "Installing: amd drivers"
    execute "paru" "-S" "xf86-video-amdgpu" "--noconfirm" "--needed"
elif lspci | grep -E "Integrated Graphics Controller"; then
    ohai "Installing: intel drivers"
    execute "paru" "-S" "libva-intel-driver" "libvdpau-va-gl" "lib32-vulkan-intel" "vulkan-intel" "libva-intel-driver" "libva-utils" "--needed" "--noconfirm"
else
    ohai "Installing: vm drivers"
    execute "paru" "-S" "xf86-video-vmware" "open-vm-tools" "--needed" "--noconfirm"
    VM='true'
fi

ohai "Enabling services to start at boot"
SERVICES=(
    'bluetooth'
    'cups'
)

for SERVICE in "${SERVICES[@]}"; do
    execute_sudo "systemctl" "enable" "${SERVICE}" &>/dev/null
done

for SERVICE in "${DE_SERVICES[@]}"; do
    execute_sudo "systemctl" "enable" "${SERVICE}" &>/dev/null
done

if [ ${VM} == 'true' ]; then
    SERVICES=(
        'vmtoolsd'
    )

    for SERVICE in "${SERVICES[@]}"; do
        execute_sudo "systemctl" "enable" "${SERVICE}" &>/dev/null
    done
fi

ohai "Configuring AppArmor and Audit"
execute_sudo "groupadd" "-r" "audit"
execute_sudo "gpasswd" "-a" ${USER} "audit"

ohai "Configuring audit log group"
cat <<EOS
    - This must be run as the ${tty_bold}ROOT${tty_reset} user
    - Please enter the ${tty_bold}ROOT${tty_reset} user password when prompted
EOS
su - root -c 'echo "log_group = audit" >> /etc/audit/auditd.conf'
mkdir ~/.config/autostart
cat >~/.config/autostart/apparmor-notify.desktop <<EOF
[Desktop Entry]
Type=Application
Name=AppArmor Notify
Comment=Receive on screen notifications of AppArmor denials
TryExec=aa-notify
Exec=aa-notify -p -s 1 -w 60 -f /var/log/audit/audit.log
StartupNotify=false
NoDisplay=true
EOF

ohai "Cleaning up"
rm ~/arch-de-utils.sh
cleanup

ohai "Arch-DE installation successful!"
