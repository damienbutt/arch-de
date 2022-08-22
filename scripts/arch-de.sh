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

# Download dependencies
curl -fsSL https://raw.githubusercontent.com/damienbutt/arch-de/HEAD/scripts/arch-de-utils.sh >arch-de-utils.sh
source arch-de-utils.sh

ISO=$(curl -s ifconfig.co/country-iso)

echo "-------------------------------------------------"
echo "Setting up the best mirrors for ${ISO}           "
echo "-------------------------------------------------"
sudo reflector -a 48 -c ${ISO} -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
paru -Syyy

# Start the actual installation
clear
ohai "Starting Arch-DE installation"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

ohai "Setting up firewall with sensible defaults"
sudo firewall-cmd --add-port=1025-65535/tcp --permanent
sudo firewall-cmd --add-port=1025-65535/udp --permanent
sudo firewall-cmd --reload

ohai "Installing common packages"
PKGS=(
    'xorg'
    'bluez'
    'bluez-utils'
    'cups'
    'hplip'
    'alsa-utils'
    'pipewire'
    'pipewire-alsa'
    'pipewire-pulse'
    'pipewire-jack'
    'firefox'
    'archlinux-wallpaper'
    'snapper-gui-git'
    'snapper-rollback'
    'gufw'
)

for PKG in "${PKGS[@]}"; do
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
    'gnu-free-fonts'
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
    'adobe-source-code-pro-fonts'
    'cantarell-fonts'
    'inter-font'
    'ttf-opensans'
    'gentium-plus-font'
    'ttf-junicode'
    'adobe-source-han-sans-otc-fonts'
    'adobe-source-han-serif-otc-fonts'
    'noto-fonts-cjk'
    'noto-fonts-emoji'
)

for PKG in "${PKGS[@]}"; do
    ohai "Installing: ${PKG}"
    paru -S "${PKG}" --noconfirm --needed
done

if lspci | grep -E "NVIDIA|GeForce"; then
    paru -S nvidia nvidia-settings nvidia-utils --noconfirm --needed
    nvidia-xconfig
elif lspci | grep -E "Radeon"; then
    paru -S xf86-video-amdgpu --noconfirm --needed
elif lspci | grep -E "Integrated Graphics Controller"; then
    paru -S libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils --needed --noconfirm
fi

PS3="Select desktop environment: "
select OPT in gnome kde cinnamon xfce quit; do
    case ${OPT} in
    gnome)
        ohai "Installing: gnome"
        PKGS=(
            'gdm'
            'gnome'
            'gnome-extra'
            'qgnomeplatform'
            'gnome-tweaks'
        )

        SERVICES=(
            'bluetooth'
            'cups'
            'gdm'
        )

        break
        ;;
    kde)
        ohai "Installing: kde"
        PKGS=(
            'sddm'
            'plasma'
            'kde-applications'
            'kde-runtime'
            'kde-plasma-desktop'
            'kde-plasma-workspace'
            'kde-plasma-addons'
        )

        SERVICES=(
            'bluetooth'
            'cups'
            'sddm'
        )

        break
        ;;
    cinnamon)
        ohai "Installing: cinnamon"
        PKGS=(
            'gdm'
            'cinnamon'
            'cinnamon-translations'
        )

        SERVICES=(
            'bluetooth'
            'cups'
            'gdm'
        )

        break
        ;;
    xfce)
        ohai "Installing: xfce"
        PKGS=(
            'xfce4'
            'xfce4-goodies'
            'lightdm'
        )

        SERVICES=(
            'bluetooth'
            'cups'
            'lightdm'
        )

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

for PKG in "${PKGS[@]}"; do
    ohai "Installing: ${PKG}"
    paru -S "${PKG}" --noconfirm --needed
done

ohai "Enabling services to start at boot"
for SERVICE in "${SERVICES[@]}"; do
    systemctl enable "${SERVICE}" &>/dev/null
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
