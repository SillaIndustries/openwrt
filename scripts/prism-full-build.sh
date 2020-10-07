#!/bin/bash

set -eu

out() {
  echo -en "\n\n\n\e[36;1m[+] $1\e[m\n\n"
  sleep 1
}

cpus=$(($(nproc) + 1))
out "Starting FULL build process using $cpus processes"

##############################################################################

out "1/5) Updating feeds"
./scripts/feeds update

if [ -e "files" ]
then
  out "Skipping 'files' directory creation (already existing)"
else
  FILES_PACK=$(cat feeds/prism/prism/prism-files/CURRENT)
  out "Creating 'files' directory from '$FILES_PACK'..."
  tar zxvf feeds/prism/prism/prism-files/src/$FILES_PACK.tar.gz
  ln -sf $FILES_PACK files
fi

##############################################################################

out "2/5) Installing feeds"
./scripts/feeds install -a

##############################################################################

out "3/5) Applying Prism config"
cp prism.config .config
make defconfig

##############################################################################

out "4/5) Downloading packages"
make download

##############################################################################

out "5/5) Building..."
make -j$cpus world

##############################################################################

out "DONE."
