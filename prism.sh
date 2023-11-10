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
ACTION="${1:-}"
shift
if [ -n "${1:-}" ]
then
  ACTION="$ACTION $1"
  shift
fi
if [ "$ACTION" = "" ]
then
  echo "Usage: $0 <action>"
  echo ""
  echo "Possible actions:"
  echo "   set version <ver>  Sets the firmware release version"
  echo "   feeds update       Update all feeds"
  echo "   feeds files        Update the local 'files' folder"
  echo "   feeds install      Install all feed packages available"
  echo "   feeds              Alias: feeds update, feeds files, feeds install"
  echo "   config load [sdk]  Apply 'prism.config' onto '.config'"
  echo "   config save        Generate 'prism.config' from current '.config'"
  echo "   config             Alias: config load, config save"
  echo "   build              Perform packages download and compilation"
  echo "   full build         Alias: feeds, config, build"
  echo ""
  exit 1
fi

##############################################################################

BKEY_REFERENCE="../prism-build-key-v1"
BKEY_OFFICIAL_PUB="RWTvWnhpt6nreEvB1GaxAgH/wFarbDqtpbhLxyFvZNU3VR1awUdS+vU/"

if [ ! -e "key-build" ]
then
  if [ -e "$BKEY_REFERENCE" ]
  then
    out "Importing '$BKEY_REFERENCE' as 'key-build'"
    cp "$BKEY_REFERENCE" key-build
    cp "$BKEY_REFERENCE.pub" key-build.pub
    cp "$BKEY_REFERENCE.ucert" key-build.ucert
    cp "$BKEY_REFERENCE.ucert.revoke" key-build.ucert.revoke
  else
    out " !!! WARNING !!! No 'key-build', generated packages won't be official!"
  fi
else
  BKEY_ACTUAL_PUB=$(tail -n 1 key-build.pub)
  if [ "$BKEY_OFFICIAL_PUB" != "$BKEY_ACTUAL_PUB" ]
  then
    out " !!! WARNING !!! Wrong 'key-build', generated packages won't be official!"
  fi
fi

##############################################################################
# Applies the version to the config files and exits

if [ "$ACTION" = "set version" ]
then
  NEW_VERSION=${1:-}
  if [ -z "$NEW_VERSION" ]
  then
    echo "Usage: $0 set version <ver>" >&2
    echo "" >&2
    echo "Current version:" $(sed -n -e 's/^CONFIG_VERSION_NUMBER="\(.*\)"/\1/p' .config)
    exit 1
  fi

  # Validates versions and extracts the prefix (major.minor) in one shot!
  NEW_VER_PREFIX=$(echo $NEW_VERSION | sed -n -e 's/^\([0-9]\+\.[0-9]\+\)\.\([0-9]\+\)\(-.\+\)\?$/\1/p')
  [ -n "$NEW_VER_PREFIX" ] || err "Invalid version number syntax (major.minor.patch[-variant])!"

  NEW_VER_FULL="$NEW_VERSION"
  sed -i -e '
s/^\(CONFIG_VERSION_NUMBER="\).*"/\1'$NEW_VER_FULL'"/;
s/^\(CONFIG_VERSION_REPO=".*\/prism-\).*"/\1'$NEW_VER_PREFIX'"/;
' .config.prism prism.config

  NEW_VER_FULL="$NEW_VERSION-sdk"
  sed -i -e '
s/^\(CONFIG_VERSION_NUMBER="\).*"/\1'$NEW_VER_FULL'"/;
s/^\(CONFIG_VERSION_REPO=".*\/prism-\).*"/\1'$NEW_VER_PREFIX'"/;
' .config.prism.sdk prism.config.sdk

  out "Version updated to $NEW_VERSION."
  exit 0
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
[ -e "files/etc/prism/prismfiles-version" ] || err "Missing 'files' version, please run \"feeds files\" next"

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
  if [ "x$@" = "xsdk" ]
  then
    _XCONFIG_EXPANDED=".config.prism.sdk"
    _XCONFIG_COMPACT="prism.config.sdk"
  else
    _XCONFIG_EXPANDED=".config.prism"
    _XCONFIG_COMPACT="prism.config"
  fi
  rm -f .config
  ln -sf $_XCONFIG_EXPANDED .config
  out "3/5) Applying '$_XCONFIG_COMPACT' to '.config'"
  cat $_XCONFIG_COMPACT > .config
  make defconfig
fi

# At this point, '.config' must exist and must be a symlink
[ -L ".config" ] || err "Missing or invalid '.config', please run 'config load' next"
case $(readlink .config) in
  ".config.prism")      _XCONFIG_COMPACT="prism.config"; ;;
  ".config.prism.sdk")  _XCONFIG_COMPACT="prism.config.sdk"; ;;
  *) err "Invalid '.config', that is not what we expected"
esac

# Create the 'prism.config' shrinked config
if [ "$ACTION" = "config save" -o "$ACTION" = "config" -o "$ACTION" = "full build" ]
then
  out "Saving current config onto '$_XCONFIG_COMPACT'"
  ./scripts/diffconfig.sh > $_XCONFIG_COMPACT
fi

# Repack all expanded configs to their compact version
if [ "$ACTION" = "config repack" ]
then
  _saved_config=$(readlink .config)

  out "Repacking '.config.prism' onto 'prism.config'"
  ln -sf .config.prism .config && make defconfig &&
    ./scripts/diffconfig.sh > prism.config

  out "Repacking '.config.prism.sdk' onto 'prism.config.sdk'"
  ln -sf .config.prism.sdk .config && make defconfig &&
    ./scripts/diffconfig.sh > prism.config.sdk

  ln -sf $_saved_config .config
fi

# Verify that the files we have are the ones we expect
# _XCONFIG_VERSION=$(sed -ne 's/^CONFIG_VERSION_NUMBER="\([0-9]\+\.[0-9]\+\).*"/\1/p' .config)
# _XFILES_VERSION=$(sed -ne 's/^\([0-9.]\+\).*/\1/p' files/etc/prism/prismfiles-version)
# [ "$_XFILES_VERSION" = "$_XCONFIG_VERSION" ] || \
#   err "Local 'files' base version (\"$_XFILES_VERSION\")" \
#       "mismatches config base version (\"$_XCONFIG_VERSION\")" >&2

##############################################################################
RETRY_COUNTER=0
if [ "$ACTION" = "build" -o "$ACTION" = "full build" ]
then
  out "4/5) Downloading packages"
  make download
  out "5/5) Starting build process"
  set +e
  make world
  if [ $? -ne 0 ]; then
    set -e
    make -j1 V=s world
  fi
  
fi

##############################################################################

out "DONE."
