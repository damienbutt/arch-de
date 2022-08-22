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

# Check cURL is installed
if ! command -v curl &>/dev/null; then
    abort "$(
        cat <<EOABORT
You must install cURL before running this script. Run the following command:
  ${tty_underline}pacman -S curl${tty_reset}
EOABORT
    )"
fi

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
        )

        DE_SERVICES=(
            'sddm'
        )

        DE='kde'

        break
        ;;
    cinnamon)
        ohai "Selected cinnamon"
        PKGS=(
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
        PKGS=(
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

# Download dependencies
curl -fsSL https://raw.githubusercontent.com/damienbutt/arch-de/HEAD/scripts/arch-de-utils.sh >arch-de-utils.sh
source arch-de-utils.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "")" &>/dev/null && pwd)"

# Start the actual installation
clear
ohai "Starting Arch-DE installation"

ohai "Detecting your country"
ISO=$(curl -s ifconfig.co/country-iso)

ohai "Setting up the best mirrors for ${ISO}"
sudo reflector -a 48 -c ${ISO} -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null
paru -Syyy &>/dev/null

ohai "Setting up firewall with sensible defaults"
sudo firewall-cmd --add-port=1025-65535/tcp --permanent
sudo firewall-cmd --add-port=1025-65535/udp --permanent
sudo firewall-cmd --reload

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
    paru -S "${PKG}" --noconfirm --needed
done

ohai "Installing ${DE} packages"
for PKG in "${DE_PKGS[@]}"; do
    ohai "Installing: ${PKG}"
    paru -S "${PKG}" --noconfirm --needed
done

ohai "Installing fonts"
PKGS=(
    'dina-font'
    'tamsyn-font'
    'bdf-unifont'
    'ttf-bitstream-vera'
    'ttf-croscore'
    'ttf-dejavu'
    'ttf-droid'
    'ttf-ibm-plex'
    'ttf-liberation'
    'ttf-linux-libertine'
    'noto-fonts'
    'ttf-roboto'
    'tex-gyre-fonts'
    'ttf-ubuntu-font-family'
    'ttf-anonymous-pro'
    'ttf-cascadia-code'
    'ttf-fantasque-sans-mono'
    'ttf-fira-mono'
    'ttf-hack'
    'ttf-fira-code'
    'ttf-inconsolata'
    'ttf-jetbrains-mono'
    'ttf-monofur'
    'ttf-ms-fonts'
    'inter-font'
    'ttf-opensans'
    'gentium-plus-font'
    'ttf-junicode'
    'adobe-source-han-sans-otc-fonts'
    'adobe-source-han-serif-otc-fonts'
    'noto-fonts-cjk'
)

for PKG in "${PKGS[@]}"; do
    ohai "Installing: ${PKG}"
    paru -S "${PKG}" --noconfirm --needed
done

ohai "Detecting your video hardware"
if lspci | grep -E "NVIDIA|GeForce"; then
    ohai "Installing: nvidia drivers"
    paru -S nvidia nvidia-settings nvidia-utils --noconfirm --needed
    if [ ${DE} == 'kde' ]; then
        ohai "Installing: nvidia-settings-daemon"
        paru -S egl-wayland --noconfirm --needed
    fi
elif lspci | grep -E "Radeon"; then
    ohai "Installing: amd drivers"
    paru -S xf86-video-amdgpu --noconfirm --needed
elif lspci | grep -E "Integrated Graphics Controller"; then
    ohai "Installing: intel drivers"
    paru -S libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils --needed --noconfirm
else
    ohai "Installing: vm drivers"
    paru -S xf86-video-vmware open-vm-tools --needed --noconfirm
fi

ohai "Enabling services to start at boot"
SERVICES=(
    'bluetooth'
    'cups'
)

for SERVICE in "${SERVICES[@]}"; do
    sudo systemctl enable "${SERVICE}" &>/dev/null
done

for SERVICE in "${DE_SERVICES[@]}"; do
    sudo systemctl enable "${SERVICE}" &>/dev/null
done

ohai "Configuring AppArmor and Audit"
sudo groupadd -r audit
sudo gpasswd -a ${USER} audit

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

ohai "Arch-DE installation successful!"
