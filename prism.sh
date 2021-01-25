#!/bin/bash

set -eu

# Make sure we are running with a proper umask, this is critical for the
# files folder, which carries the file attributes inside the squashfs.
umask 0022

out() {
  echo -en "\n\n\n\e[36;1m[+] $@\e[m\n\n"
  sleep 1
}
err() {
  echo -en "\n\n\n\e[31;1m[!] Error: $@\e[m\n\n"
  exit 1
}

# Check that we are in the right directory
[ -e "feeds.conf.default" ] || err "You must run this script from the correct directory!"

# Acquire the available cpus for parallel building
cpus=$(($(nproc) + 1))

# Determine the action or show help text
ACTION="$@"
if [ "$ACTION" = "" ]
then
  echo "Usage: $0 <action>"
  echo ""
  echo "Possible actions:"
  echo "   feeds update     Update all feeds"
  echo "   feeds files      Update the local 'files' folder"
  echo "   feeds install    Install all feed packages available"
  echo "   feeds            Alias: feeds update, feeds files, feeds install"
  echo "   config load      Apply 'prism.config' onto '.config'"
  echo "   config save      Generate 'prism.config' from current '.config'"
  echo "   config           Alias: config load, config save"
  echo "   build            Perform packages download and compilation"
  echo "   full build       Alias: feeds, config, build"
  echo ""
  exit 1
fi

##############################################################################

BKEY_REFERENCE="../prism-build-key-v1"
BKEY_PUB="RWTvWnhpt6nreEvB1GaxAgH/wFarbDqtpbhLxyFvZNU3VR1awUdS+vU/"

if [ ! -e "key-build" ]
then
  if [ -e "$BKEY_REFERENCE" ]
  then
    out "Importing '$BKEY_REFERENCE' as 'key-build'"
    cp "$BKEY_REFERENCE" key-build
    cp "$BKEY_REFERENCE.pub" key-build.pub
  else
    out " !!! WARNING !!! No 'key-build', generated packages won't be official!"
  fi
else
  BKEY_ACTUAL_PUB=$(tail -n 1 key-build.pub)
  if [ "$BKEY_PUB" != "$BKEY_ACTUAL_PUB" ]
  then
    out " !!! WARNING !!! Wrong 'key-build', generated packages won't be official!"
  fi
fi

##############################################################################
# Updating the feeds creates all the data needed in 'feeds/<feedname>'

if [ "$ACTION" = "feeds update" -o "$ACTION" = "feeds" -o "$ACTION" = "full build" ]
then
  out "1/5) Updating feeds"
  ./scripts/feeds update
fi

# At this point, out feed must exist
[ -e feeds/prism/prism/prism-files/REPO_URL ] || err "Cannot find prism feed, please run \"feeds update\" next"

##############################################################################

if [ "$ACTION" = "feeds files" -o "$ACTION" = "feeds" -o "$ACTION" = "full build" ]
then
  _FILES_REPO_URL=$(cat feeds/prism/prism/prism-files/REPO_URL)
  _FILES_REPO_VERSION=$(cat feeds/prism/prism/prism-files/REPO_VERSION)
  _FILES_LOCAL_REPO="files-repo"

  if [ -e "files" ]
  then
    out "Skipping 'files' directory creation (already existing)"
  else
    if [ ! -e "$_FILES_LOCAL_REPO" ]
    then
      out "Cloning files repository from $_FILES_REPO_URL"
      git clone "$_FILES_REPO_URL" "$_FILES_LOCAL_REPO"
    else
      (cd "$_FILES_LOCAL_REPO" && git fetch origin)
    fi

    out "Checking out files repository version $_FILES_REPO_VERSION and symlinking to 'files'"
    (cd "$_FILES_LOCAL_REPO" && git checkout "$_FILES_REPO_VERSION")
    ln -s "$_FILES_LOCAL_REPO/prism-files" files
  fi
fi

# At this point, the files folder must exist
[ -e "files/etc/prism/version" ] || err "Missing 'files' version, please run \"feeds files\" next"

##############################################################################
# Installing the feeds creates symlinks under 'package/feeds/<feed>/<packagename>'

if [ "$ACTION" = "feeds install" -o "$ACTION" = "feeds" -o "$ACTION" = "full build" ]
then
  out "2/5) Installing feeds"
  ./scripts/feeds install -a
fi

# At this point, feeds must be installed
[ -e "package/feeds" ] || err "Missing 'package/feeds', please run \"feeds install\" next"

##############################################################################

# Expand 'prism.config' into the full regular '.config'
if [ "$ACTION" = "config load" -o "$ACTION" = "config" -o "$ACTION" = "full build" ]
then
  out "3/5) Applying 'prism.config' to '.config'"
  cp prism.config .config
  make defconfig
fi

# At this point, '.config' must exist
[ -e ".config" ] || err "Missing '.config', please run 'config load' next"

# Create the 'prism.config' shrinked config
if [ "$ACTION" = "config save" -o "$ACTION" = "config" -o "$ACTION" = "full build" ]
then
  out "Saving current config onto 'prism.config'"
  ./scripts/diffconfig.sh > "prism.config"
fi

# Verify that the files we have are the ones we expect
_XCONFIG_VERSION=$(sed -ne 's/^CONFIG_VERSION_NUMBER="\(.*\)"/\1/p' .config)
_XFILES_VERSION="$(cat files/etc/prism/version)"
[ "$_XFILES_VERSION" == "$_XCONFIG_VERSION" ] || \
  err "Local 'files' version (\"$_XFILES_VERSION\")" \
      "mismatches config version (\"$_XCONFIG_VERSION\")" >&2

##############################################################################

if [ "$ACTION" = "build" -o "$ACTION" = "full build" ]
then
  out "4/5) Downloading packages"
  make download

  out "5/5) Starting build process using $cpus cpu(s)..."
  make -j$cpus world
fi

##############################################################################

out "DONE."
