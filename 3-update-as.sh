#!/bin/bash
set +x
set -e

### Global ###
DIR="$(dirname "${BASH_SOURCE[0]}")"
DIR="$(realpath "${DIR}")"

source "$DIR/settings.cfg"
UIPATHDIR="/opt/UiPathAutomationSuite/$VERSION"
CONFIGLOCATION='/opt/UiPathAutomationSuite'
##############

function updateAS() {
  echo '--- Updating AS'
  echo '--- Updating AS'
  echo '--- Updating AS'
  $UIPATHDIR/installer/install-uipath.sh -i $CONFIGLOCATION/cluster-config-input.json -o $CONFIGLOCATION/cluster-config-output.json -a --accept-license-agreement
  echo '---!'
}

function main() {
  if [ $EMAIL = 'you@youremail.com' ]; then
    echo "First update settings.cfg!"
    return
  fi

 updateAS
}

main
