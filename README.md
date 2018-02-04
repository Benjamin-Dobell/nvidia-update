# nVidia Update

The simplest way to install nVidia drivers on macOS.

# How?

Simply copy and paste the following in a terminal:

```
bash <(curl -s https://raw.githubusercontent.com/Benjamin-Dobell/nvidia-update/master/nvidia-update.sh)
```

# How does it work?

This script installs the _best_ (not necessarily the latest) official nVidia web drivers for your system.

## Why not the latest?

Sometimes nVidia releases drivers that have bugs or performance issues. This script maintains a blacklist of "bad" drivers that it won't install by default.

## Why does it sometimes need to patch drivers?

Presently, each nVidia driver release is tied to an exact version of macOS. However, as described above, sometimes it's desirable to install a different release. This script will download the official drivers and patch them on-the-fly so that they can be loaded on your system.

Patching does not involve changing the driver binaries, just a couple of configuration options in some text files.

# Install a specific driver version

If you want to install a specific driver version, you must first download the script.

# Downloading the script

You can clone this repository or download the script with the following command:

```
curl -O https://raw.githubusercontent.com/Benjamin-Dobell/nvidia-update/master/nvidia-update.sh
```

## Usage

```
Usage: sudo ./nvidia-update.sh [--force|-f] [revision]

If revision is not supplied, the latest whitelisted driver will be downloaded.
```

`-f`/`--force` will allow you to reinstall a revision that is already installed.

