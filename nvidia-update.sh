#!/bin/sh

set -e

PLISTBUDDY=/usr/libexec/PlistBuddy
SYSTEM_BUILD=$(system_profiler SPSoftwareDataType | grep 'System Version:' | cut -d '(' -f 2 | cut -d ')' -f 1)

BLACKLIST=(387.10.10.10.25.156 387.10.10.10.25.157)

UPDATE_URL=https://gfe.nvidia.com/mac-update

FORCE=false
REVISION=

function usage() {
	echo "Usage: sudo ./$(basename "$0") [--force|-f] [revision]"
	echo "If revision is not supplied, the latest whitelisted driver will be downloaded."
	exit
}

function mktemppkg() {
	echo "$(mktemp $TMPDIR/$(uuidgen).pkg)"
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

if [[ $(whoami) != "root" ]]; then
	echo "Must be run as root (sudo)."
	exit
fi

echo "Downloading driver list..."

UPDATE_PLIST=$(mktemp)

curl https://gfe.nvidia.com/mac-update -o $UPDATE_PLIST

VERSIONS=$($PLISTBUDDY -c "Print updates:" $UPDATE_PLIST | grep "version" | awk -v N=3 '{print $N}')
VERSION_COUNT=$(echo "$VERSIONS" | wc -l | xargs)

found_os=false
LATEST_VERSION=
LATEST_URL=

for ((i=0; i<VERSION_COUNT; i++)); do
	version=$($PLISTBUDDY -c "Print updates:$i:version" $UPDATE_PLIST)
	os=$($PLISTBUDDY -c "Print updates:$i:OS" $UPDATE_PLIST)
	url=$($PLISTBUDDY -c "Print updates:$i:downloadURL" $UPDATE_PLIST)

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

rm $UPDATE_PLIST

CURRENT_INFO_PATH=/Library/Extensions/NVDAStartupWeb.kext/Contents/Info.plist
CURRENT_BUNDLE_STRING=

if [ -f "$CURRENT_INFO_PATH" ]; then
	CURRENT_BUNDLE_STRING=$($PLISTBUDDY -c "Print CFBundleGetInfoString" $CURRENT_INFO_PATH)
fi

if [[ "$CURRENT_BUNDLE_STRING" =~ "$REVISION" ]] && [[ "$FORCE" != "true" ]]; then
	echo "$REVISION is already installed."
	exit
fi

if [[ -z "$PKG_URL" ]]; then
	if [[ -z "$REVISION" ]]; then
		echo "Could not find a release for your OS."
		echo "The latest recommended release is:"
		echo "$LATEST_VERSION"

		if [[ "$CURRENT_BUNDLE_STRING" =~ "$LATEST_VERSION" ]] && [[ "$FORCE" != "true" ]]; then
			echo "which is already installed."
			exit
		else
			read -p "Do you want to install that now? [Y/n]" -n 1 -r

			if [[ $REPLY =~ ^[Yy]$ ]]; then
				REVISION=$LATEST_VERSION
				PKG_URL=$LATEST_URL
			else
				exit
			fi
		fi
	else
		echo "Unknown revision: $REVISION"
		exit
	fi
fi

PKG_PATH=$(mktemppkg)

echo "Downloading $REVISION drivers..."
curl $PKG_URL -o $PKG_PATH

if [[ "$PKG_OS" != "$SYSTEM_BUILD" ]]; then
	echo "Patching package..."

	TEMP_DIR=$(mktemp -d)
	EXPANDED_DIR=$TEMP_DIR/expanded

	pkgutil --expand "$PKG_PATH" $EXPANDED_DIR

	rm $PKG_PATH

	pushd $EXPANDED_DIR > /dev/null

	cat Distribution | sed '/installation-check/d' > DistributionTEMP
	mv DistributionTEMP Distribution

	echo "Patched install requirements."

	pushd *-NVWebDrivers.pkg > /dev/null

	PAYLOAD_PATH=$(pwd)/Payload
	BOM_PATH=$(pwd)/Bom

	PAYLOAD_TEMP_DIR=$(mktemp -d)
	pushd $PAYLOAD_TEMP_DIR > /dev/null

	cat $PAYLOAD_PATH | gunzip -dc | cpio -i --quiet
	$PLISTBUDDY -c "Set IOKitPersonalities:NVDAStartup:NVDARequiredOS $SYSTEM_BUILD" Library/Extensions/NVDAStartupWeb.kext/Contents/Info.plist
	echo "Patched extension."

	echo "Repackaging..."

	find . | cpio -o --quiet | gzip -c > $PAYLOAD_PATH
	mkbom . $BOM_PATH

	popd > /dev/null
	rm -rf $PAYLOAD_TEMP_DIR

	popd > /dev/null
	popd > /dev/null

	PKG_PATH=$(mktemppkg)

	pkgutil --flatten $EXPANDED_DIR $PKG_PATH

	rm -rf $TEMP_DIR
fi

UNINSTALL_PKG_PATH="/Library/PreferencePanes/NVIDIA Driver Manager.prefPane/Contents/MacOS/NVIDIA Web Driver Uninstaller.app/Contents/Resources/NVUninstall.pkg"

if [[ -f "$UNINSTALL_PKG_PATH" ]]; then
	echo "Uninstalling previous drivers..."
	installer -pkg "$UNINSTALL_PKG_PATH" -target /
fi

# Clean up after misbehaved scripts that manually install things to the wrong location (e.g. webdriver.sh)
rm -rf /Library/GPUBundles/GeForce*Web.bundle

echo "Installing new drivers..."
installer -pkg $PKG_PATH -target /
rm $PKG_PATH

echo "Done."
echo "Please restart your system."

