#! /usr/bin/env bash

set -eu

# Directory this script lives in, and the repo root one level up.
# Only used by --debug, which builds from this checkout instead of AUR.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ${1:-} == "remove" ]]; then
	if pacman -Qq xone-dkms &> /dev/null; then
		sudo pacman -Rcns xone-dkms
	elif [[ -x "$REPO_ROOT/uninstall.sh" ]] && [[ -n "$(dkms status xone 2> /dev/null)" ]]; then
		echo "xone-dkms pacman package not found, but a locally-built (debug) install is present."
		echo "Removing it via uninstall.sh instead..."
		"$REPO_ROOT/uninstall.sh" --no-firmware
	else
		echo "No xone installation found (checked pacman and dkms)." >&2
		exit 1
	fi

	echo ""
	echo ""
	echo "Done!"
	echo "Just reboot your Deck :)"

	exit 0
fi

DEBUG_BUILD=0
if [[ ${1:-} == "--debug" ]]; then
	DEBUG_BUILD=1

	# Unlike the normal AUR-based install, --debug builds the driver from
	# this checkout (so it must be run from a local clone, not piped
	# straight from curl) so you get exactly the source you're debugging,
	# built with -DDEBUG (enables dev_dbg()/pr_debug() output) and -Og -g3
	# (keeps symbols/line info usable in dmesg backtraces).
	if [[ ! -f "$REPO_ROOT/install.sh" ]]; then
		echo "--debug requires running this script from within a local clone of the xone repo" >&2
		echo "(expected to find install.sh at $REPO_ROOT/install.sh)." >&2
		echo "Clone the repo on the Deck first, e.g.:" >&2
		echo "  git clone https://github.com/dlundqvist/xone.git && cd xone" >&2
		echo "  sudo ./install/steam-deck-install.sh --debug" >&2
		exit 1
	fi
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

mkdir xone-install
cd xone-install || exit 1

AUR_LINK="https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h="

if [[ $DEBUG_BUILD -eq 0 ]]; then
	ITER=0
	while [[ ! -e PKGBUILD_XONE && "$ITER" -lt 5 ]]; do
		curl "${AUR_LINK}xone-dkms" -o PKGBUILD_XONE
		ITER=$(( ITER + 1 ))
	done

	if [[ $ITER -eq 5 ]]; then
		echo "Error when downloading PKGBUILD for xone. Exiting..."
		exit 1
	fi
fi

ITER=0
while [[ ! -e PKGBUILD_FIRMWARE && "$ITER" -lt 5 ]]; do
	curl "${AUR_LINK}xone-dongle-firmware" -o PKGBUILD_FIRMWARE
	ITER=$(( ITER + 1 ))
done

if [[ $ITER -eq 5 ]]; then
	echo "Error when downloading PKGBUILD for xone firmware. Exiting..."
	exit 1
fi

# to ABSOLUTELY make sure we have acces when running sudo -u deck
chown -R deck:deck .
chmod 777 .

echo ""
echo "Don't worry about \"error: command failed to execute correctly\""
echo ""

linux=$(pacman -Qsq linux-neptune | grep -e "[0-9]$" | tail -n 1)
pacman -Syu --noconfirm base-devel fakeroot glibc git \
    "$linux" "$linux-headers" linux-api-headers

# Install build dependencies manually
pacman -Syu --noconfirm --asdeps dkms w3m html-xml-utils

if [[ $DEBUG_BUILD -eq 0 ]]; then
	# build and install seaprately to avoid repeated password prompts
	sudo -u deck makepkg -Ccf -p PKGBUILD_XONE
fi
sudo -u deck makepkg -Ccf -p PKGBUILD_FIRMWARE

if [[ $DEBUG_BUILD -eq 0 ]]; then
	pacman -U --noconfirm xone-dkms-*.tar.zst
fi
pacman -U --noconfirm --asdeps xone-dongle-firmware-*.tar.zst

# Remove unneeded build dependencies
pacman -Rcns --noconfirm w3m html-xml-utils

echo ""
echo "Again, don't worry about this ^"

cd ..
rm -rf xone-install

if [[ $DEBUG_BUILD -eq 1 ]]; then
	echo ""
	echo "Building and installing the debug driver from $REPO_ROOT via DKMS..."
	(cd "$REPO_ROOT" && ./install.sh --debug)

	echo ""
	echo "Debug build installed. dev_dbg()/pr_debug() output will now show up in dmesg."
	echo "To capture logs across a sleep/wake cycle, start a live capture to disk before"
	echo "suspending, e.g.:"
	echo "  sudo dmesg -w -T >> ~/xone-debug.log &"
	echo "or:"
	echo "  sudo journalctl -k -f >> ~/xone-debug.log &"
	echo "so anything logged right up to the hang is flushed to storage, not just held in"
	echo "the kernel ring buffer."
fi

echo ""
echo ""
echo "Done!"
echo "Just reboot your Deck :)"
