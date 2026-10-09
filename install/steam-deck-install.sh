#! /usr/bin/env bash

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run as root!' >&2
    exit 1
fi

if [ ! -f install.sh ] || [ ! -f install/firmware.sh ]; then
    echo 'This script must be run from the root of the xone repository!' >&2
    exit 1
fi

if [ "${1:-}" == remove ]; then
    ./uninstall.sh

    echo ""
    echo "Done!"
    echo "Just reboot your Deck :)"
    echo ""
    echo "Optionally, lock your deck and remove password:"
    echo "  steamos-readonly enable"
    echo "  passwd deck"

    exit 0
fi

ro_status=$(steamos-readonly status)
if [[ $ro_status == "enabled" ]]; then
    echo "Disabling readonly"
    echo ""
    steamos-readonly disable
fi

pacman-key --init
pacman-key --populate archlinux
pacman-key --populate holo

echo ""
echo "Don't worry about \"error: command failed to execute correctly\""
echo ""

# SteamOS ships its own kernel package, so the matching headers have to be
# resolved dynamically instead of depending on the generic "linux-headers"
linux=$(pacman -Qsq linux-neptune | grep -e "[0-9]$" | tail -n 1)
pacman -Syu --noconfirm base-devel dkms git curl libarchive \
    "$linux" "$linux-headers" linux-api-headers

echo ""
echo "Again, don't worry about this ^"
echo ""

./install.sh "$@"
./install/firmware.sh --skip-disclaimer

echo ""
echo ""
echo "Done!"
echo "Just reboot your Deck :)"
