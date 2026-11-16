#!/usr/bin/env bash
set -euo pipefail
# Run inside the project-local MSYS2 UCRT64 environment.
project=$(pwd)
export TMPDIR="$(cygpath -m -s /tmp)"
export TEMP="$TMPDIR" TMP="$TMPDIR"
mkdir -p /opt/wonky-src /opt/mercury
if [ ! -d /opt/wonky-src/mercury-srcdist-22.01.9 ]; then
  tar -xJf "$project/.cache/mercury.tar.xz" -C /opt/wonky-src
fi
cd /opt/wonky-src/mercury-srcdist-22.01.9
prefix=$(cygpath -m -s /opt/mercury)
if [[ "$prefix" == *" "* || "$TMPDIR" == *" "* ]]; then
  echo 'Mercury needs Windows short paths. Move the project to a path without spaces and retry setup.' >&2
  exit 1
fi
./configure --prefix="$prefix" --enable-minimal-install --disable-most-grades --with-llds-base-grade=none --with-cc=gcc > "$project/.cache/mercury-configure.log" 2>&1
make PARALLEL=-j8 > "$project/.cache/mercury-build.log" 2>&1
# The bootstrap grade already builds ordinary native applications. Install it
# without rebuilding a second standard library in an unused grade.
make PARALLEL=-j8 install_main > "$project/.cache/mercury-install.log" 2>&1
printf '22.01.9 hlc.gc.pregen\n' > /opt/mercury/.wonky-ready
