#!/bin/sh

set -e

PLISTBUDDY=/usr/libexec/PlistBuddy

BLACKLIST_URL=https://raw.githubusercontent.com/Benjamin-Dobell/nvidia-update/master/BLACKLIST
UPDATE_URL=https://gfe.nvidia.com/mac-update

SYSTEM_BUILD=$(system_profiler SPSoftwareDataType | grep 'System Version:' | cut -d '(' -f 2 | cut -d ')' -f 1)

CURRENT_INFO_PATH=/Library/Extensions/NVDAStartupWeb.kext/Contents/Info.plist
CURRENT_BUNDLE_STRING=
CURRENT_REQUIRED_OS=

if [ -f "$CURRENT_INFO_PATH" ]; then
	CURRENT_BUNDLE_STRING=$($PLISTBUDDY -c "Print CFBundleGetInfoString" $CURRENT_INFO_PATH)
	CURRENT_REQUIRED_OS=$($PLISTBUDDY -c "Print IOKitPersonalities:NVDAStartup:NVDARequiredOS" $CURRENT_INFO_PATH)
fi

FORCE=false
REVISION=

function usage() {
	printf "Usage: ./$(basename "$0") [--force|-f] [revision]\n"
	printf "\nIf revision is not supplied, the latest non-blacklisted driver will be used.\n"
	exit
}

function temp_pkg_path() {
	echo "$TMPDIR/$(uuidgen).pkg"
}

function realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

function patch_installed() {
	if [[ "$CURRENT_REQUIRED_OS" != "$SYSTEM_BUILD" ]]; then
		printf "\n"
		read -p "Your existing drivers need patching to run. Patch them? [Y/n] " -n 1 -r
		printf "\n"

		if [[ $REPLY =~ ^[Yy]$ ]]; then
			sudo $PLISTBUDDY -c "Set IOKitPersonalities:NVDAStartup:NVDARequiredOS $SYSTEM_BUILD" $CURRENT_INFO_PATH
			printf "\nDone.\nPlease restart your system.\n"
		fi
	fi
}

if [[ $# -gt 2 ]]; then
	usage
elif [[ $# -gt 1 ]]; then
	if [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
		FORCE=true
		REVISION=$2
	else
		usage
	fi
elif [[ $# -gt 0 ]]; then
	if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
		usage
	elif [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
		FORCE=true
	else
		REVISION=$1
	fi
fi

function update() {
	printf "Downloading driver blacklist...\n"

	BLACKLIST=
	while read -r version; do BLACKLIST+=("$version"); done <<<$(curl $BLACKLIST_URL)

	printf "\nDownloading driver list...\n"

	UPDATE_PLIST="$(mktemp)"

	curl $UPDATE_URL -o "$UPDATE_PLIST"

	VERSIONS=$($PLISTBUDDY -c "Print updates: " "$UPDATE_PLIST" | grep "version" | awk -v N=3 '{print $N}')
	VERSION_COUNT=$(echo "$VERSIONS" | wc -l | xargs)

	found_os=false
	LATEST_VERSION=
	LATEST_URL=

	for ((i=0; i<VERSION_COUNT; i++)); do
		version=$($PLISTBUDDY -c "Print updates:$i:version" "$UPDATE_PLIST")
		os=$($PLISTBUDDY -c "Print updates:$i:OS" "$UPDATE_PLIST")
		url=$($PLISTBUDDY -c "Print updates:$i:downloadURL" "$UPDATE_PLIST")

		if [[ -z "$REVISION" ]]; then
			blacklisted=false

			if [[ " ${BLACKLIST[@]} " =~ " ${version} " ]]; then
				blacklisted=true
			elif [[ -z "$LATEST_VERSION" ]]; then
				LATEST_VERSION=$version
				LATEST_URL=$url
			fi

			if [[ "$found_os" == "true" ]] || [[ "$os" == "$SYSTEM_BUILD" ]]; then
				found_os=true

				if [[ "$blacklisted" != "true" ]]; then
					REVISION=$version
					PKG_URL=$url
					PKG_OS=$os
					printf "\nThe latest driver revision is $REVISION\n"
					break
				fi
			fi
		else
			if [[ "$version" == "$REVISION" ]]; then
				PKG_URL=$url
				PKG_OS=$os
				break
			fi
		fi
	done

	rm "$UPDATE_PLIST"

	if [[ "$CURRENT_BUNDLE_STRING" =~ "$REVISION" ]] && [[ "$FORCE" != "true" ]]; then
		printf "\n$REVISION is already installed.\n"
		patch_installed
		exit
	fi

	if [[ -z "$PKG_URL" ]]; then
		if [[ -z "$REVISION" ]]; then
			printf "\nCould not find a release for your OS.\n\nThe latest recommended release is:\n $LATEST_VERSION\n"

			if [[ "$CURRENT_BUNDLE_STRING" =~ "$LATEST_VERSION" ]] && [[ "$FORCE" != "true" ]]; then
				printf "which is already installed.\n"
				patch_installed
				exit
			else
				printf "\n"
				read -p "Do you want to install that now? [Y/n] " -n 1 -r
				printf "\n"

				if [[ $REPLY =~ ^[Yy]$ ]]; then
					REVISION=$LATEST_VERSION
					PKG_URL=$LATEST_URL
				else
					patch_installed
					exit
				fi
			fi
		else
			printf "\nUnknown revision: $REVISION\n"
			exit
		fi
	fi

	PKG_PATH="$(temp_pkg_path)"

	printf "\nDownloading $REVISION drivers...\n"
	curl $PKG_URL -o "$PKG_PATH"

	if [[ "$PKG_OS" != "$SYSTEM_BUILD" ]]; then
		printf "\nPatching package...\n"

		TEMP_DIR="$(mktemp -d)"
		EXPANDED_DIR="$TEMP_DIR/expanded"

		sudo pkgutil --expand "$PKG_PATH" "$EXPANDED_DIR"

		rm "$PKG_PATH"

		sudo cat "$EXPANDED_DIR/Distribution" | sed '/installation-check/d' | sudo tee "$EXPANDED_DIR/DistributionTEMP" > /dev/null
		sudo mv "$EXPANDED_DIR/DistributionTEMP" "$EXPANDED_DIR/Distribution"

		printf "Patched install requirements.\n"

		WEB_DRIVERS_PATH="$EXPANDED_DIR/$(ls "$EXPANDED_DIR" | grep NVWebDrivers.pkg)"
		PAYLOAD_PATH="$(realpath "$WEB_DRIVERS_PATH/Payload")"
		BOM_PATH="$(realpath "$WEB_DRIVERS_PATH/Bom")"

		PAYLOAD_TEMP_DIR="$(mktemp -d)"

		(cd "$PAYLOAD_TEMP_DIR"; sudo cat "$PAYLOAD_PATH" | gunzip -dc | cpio -i --quiet)
		$PLISTBUDDY -c "Set IOKitPersonalities:NVDAStartup:NVDARequiredOS $SYSTEM_BUILD" "$PAYLOAD_TEMP_DIR/Library/Extensions/NVDAStartupWeb.kext/Contents/Info.plist"
		sudo chown -R root:wheel "$PAYLOAD_TEMP_DIR/"*
		printf "Patched extension.\n"

		printf "\nRepackaging...\n"

		(cd "$PAYLOAD_TEMP_DIR"; sudo find . | sudo cpio -o --quiet | gzip -c | sudo tee "$PAYLOAD_PATH" > /dev/null)
		(cd "$PAYLOAD_TEMP_DIR"; sudo mkbom . "$BOM_PATH")

		sudo rm -rf "$PAYLOAD_TEMP_DIR"

		PKG_PATH="$(temp_pkg_path)"

		sudo pkgutil --flatten "$EXPANDED_DIR" "$PKG_PATH"
		sudo chown "$(id -un):$(id -gn)" "$PKG_PATH"

		sudo rm -rf "$TEMP_DIR"
	fi

	UNINSTALL_PKG_PATH="/Library/PreferencePanes/NVIDIA Driver Manager.prefPane/Contents/MacOS/NVIDIA Web Driver Uninstaller.app/Contents/Resources/NVUninstall.pkg"

	if [[ -f "$UNINSTALL_PKG_PATH" ]]; then
		printf "\nUninstalling previous drivers...\n"
		sudo installer -pkg "$UNINSTALL_PKG_PATH" -target /
	fi

	# Try remove NVidia user-mode left-overs. Only possible if SIP is disabled.
	sudo rm -rf /Library/GPUBundles/GeForce*Web.bundle > /dev/null 2>&1 || true

	printf "\nInstalling new drivers...\n"
	sudo installer -pkg "$PKG_PATH" -allowUntrusted -target /
	rm "$PKG_PATH"

	printf "\nDone.\nPlease restart your system.\n"
}

update
