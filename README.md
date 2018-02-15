# nVidia Update

The simplest way to install nVidia drivers on macOS.

# How?

Simply copy and paste the following in a terminal:

```
bash <(curl -s https://raw.githubusercontent.com/Benjamin-Dobell/nvidia-update/master/nvidia-update.sh)
```

# How does it work?

This script installs the _best_ (not necessarily the latest) official nVidia web drivers for your system.

Specifically, it does the following:

 * Checks for official driver updates for your version of macOS.
 * Cross-references against a list of blacklisted drivers, that it'll avoid installing (by default).
 * Properly uninstalls old drivers.
 * Downloads and installs the latest non-blacklisted drivers.
 * On-the-fly patches driver packages so they can be installed on your version of macOS (if necessary).
 * Patches drivers that you've already installed, if they no longer match your macOS version i.e. post macOS update.

## Why not always install the latest drivers?

Sometimes nVidia releases drivers that have bugs or performance issues. This script maintains a blacklist of "bad" drivers that it won't install by default.

## Why does it sometimes need to patch drivers?

Presently, each nVidia driver release is tied to an exact version of macOS. However, as described above, sometimes it's desirable to install a different release. This script will download the official drivers and patch them on-the-fly so that they can be loaded on your system.

Patching does not involve changing the driver binaries, just a couple of configuration options in some text files.

## Do I need to disable [SIP](https://support.apple.com/en-au/HT204899)?

_No!_

Unlike other alternative approaches that manually mess around with your file system, this tool uses official installers and drivers. Even after patching (where necessary) they install flawlessly on systems with SIP enabled.

## Does this work on real Macs?

_Yes!_

No need to disable SIP, it just works.

## What do I do after updating macOS to a new version?

Simply run the script again, it'll take care of the rest, updating and/or patching drivers as necessary.

# Install a specific driver version

```
bash <(curl -s https://raw.githubusercontent.com/Benjamin-Dobell/nvidia-update/master/nvidia-update.sh) <revision>
```

Where `<revision>` is a driver version e.g. `378.10.10.10.25.106`

# Downloading the script

You can clone this repository or download the script with the following command:

```
curl -O https://raw.githubusercontent.com/Benjamin-Dobell/nvidia-update/master/nvidia-update.sh
chmod 755 nvidia-update.sh
```

## Usage

```
Usage: ./nvidia-update.sh [--force|-f] [revision]
```

If `revision` is not supplied, the latest non-blacklisted driver will be used.

`--force`/`-f` will allow you to reinstall a revision that is already installed.

