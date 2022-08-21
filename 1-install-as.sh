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

function error() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "${RED}[ERROR][$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*${NC}\n" >&2
  #exit 1
}

function installPackages() {
  echo '--- Installing packages'
  echo '--- Installing packages'
  echo '--- Installing packages'
  dnf install -y epel-release
  dnf install -y compat-openssl10 httpd-tools nfs-utils
  echo '---!'
}

function updateSystem() {
  echo '--- Updating system'
  echo '--- Updating system'
  echo '--- Updating system'
  dnf -y update
  echo '---!'
}

function setupISCSI() {
  echo '--- Setting up iscsi'
  echo '--- Setting up iscsi'
  echo '--- Setting up iscsi'
  dnf --setopt=tsflags=noscripts install iscsi-initiator-utils
  systemctl enable iscsid
  systemctl start iscsid
  echo '---!'
}

function updateNetwork() {
  echo '--- Updating networking & hosts'
  echo '--- Updating networking & hosts'
  echo '--- Updating networking & hosts'
  NETFILE="/etc/sysconfig/network-scripts/ifcfg-$NETDEVICE"

  if [ -f "$NETFILE" ]; then
    if grep -q 'BOOTPROTO=dhcp' "$NETFILE"; then
      echo "Switching to Static IP address."
      sed -i 's/BOOTPROTO=dhcp/BOOTPROTO=static/g' /etc/sysconfig/network-scripts/ifcfg-$NETDEVICE
      sed -i 's/DHCP_VENDOR_CLASS_IDENTIFIER=anaconda-Linux//g' /etc/sysconfig/network-scripts/ifcfg-$NETDEVICE
      sed -i 's/IPV4_DHCP_TIMEOUT=90//g' /etc/sysconfig/network-scripts/ifcfg-$NETDEVICE
    fi

    cat << EOF >> $NETFILE
IPADDR=$IP
NETMASK=$SUBNET
GATEWAY=$GATEWAY
DNS1=$DNS
EOF

  fi

  hostnamectl set-hostname "$HOSTNAME.$DOMAIN"

  if grep -q "$DOMAIN" "/etc/hosts"; then
    echo "Hosts already up-2-date."
  else
    echo "$IP   $DOMAIN" >> /etc/hosts
  fi

  systemctl restart NetworkManager
  echo '---!'
}

function installkKubectl() {
  echo '--- Installing kubectl'
  echo '--- Installing kubectl'
  echo '--- Installing kubectl'
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  echo '---!'
}

function installSQL() {
  echo '--- Installing Microsoft SQL Server'
  echo '--- Installing Microsoft SQL Server'
  echo '--- Installing Microsoft SQL Server'
  if [[ $(systemctl list-units --all -t service --full --no-legend "mssql-server.service" | sed 's/^\s*//g' | cut -f1 -d' ') == "mssql-server.service" ]]; then
    systemctl stop mssql-server
  fi
  
  curl -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/8/mssql-server-2019.repo
  dnf install -y mssql-server
  ACCEPT_EULA='Y' MSSQL_PID='Developer' MSSQL_LCID='1033' MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD MSSQL_TCP_PORT=1433 /opt/mssql/bin/mssql-conf setup
  systemctl status mssql-server
  systemctl start firewalld
  firewall-cmd --zone=public --add-port=1433/tcp --permanent
  firewall-cmd --reload
  dnf install -y mssql-server-fts
  systemctl restart mssql-server
  echo '---!'
}

function setupASInstaller() {
  echo '--- Setting up UiPathAutomationSuite installer'
  echo '--- Setting up UiPathAutomationSuite installer'
  echo '--- Setting up UiPathAutomationSuite installer'
  rm -rf "$UIPATHDIR/installer"
  mkdir -p $UIPATHDIR

  wget -O $UIPATHDIR/installer.zip https://download.uipath.com/automation-suite/$VERSION/installer-$VERSION.zip
  unzip $UIPATHDIR/installer.zip -d $UIPATHDIR/installer
  chmod -R 755 $UIPATHDIR/installer
  chmod +x $UIPATHDIR/installer/installUiPathAS.sh
  echo '---!'
}

function updateASFiles() {
  echo '--- Updating files'
  echo '--- Updating files'
  echo '--- Updating files'
  # Utils
  sed -i 's/OS_ID=$(source \/etc\/os-release ; echo "$ID")/OS_ID=rhel/g' $UIPATHDIR/installer/Modules/utils.sh
  # Default settings - Still need a bit of work
  #sed -i 's/"cluster_cpu": 32/"cluster_cpu": 16/g' $UIPATHDIR/installer/defaults.json
  #sed -i 's/"cpu": 32/"cpu": 16/g' $UIPATHDIR/installer/defaults.json
  echo '---!'
}

function createASConfig() {
  echo '--- Creating AS config'
  echo '--- Creating AS config'
  echo '--- Creating AS config'
  rm -rf $CONFIGLOCATION/cluster-config-input.json
  cp cluster-config-master.json $CONFIGLOCATION/cluster-config-input.json

  ADMIN_PWD=$(cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 16)
  DOCKER_PASSWORD=$(cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 16)
  if [ $RKE_TOKEN = "<rke_token>" ]; then
    RKE_TOKEN=$(cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 16)
    sed -i "s/<rke_token>/$RKE_TOKEN/g" settings.cfg
  fi

  sed -i "s/<rke_token>/$RKE_TOKEN/g" $CONFIGLOCATION/cluster-config-input.json
  sed -i "s/<fqdn>/$HOSTNAME.$DOMAIN/g" $CONFIGLOCATION/cluster-config-input.json
  sed -i "s/<rke_token>/$RKE_TOKEN/g" $CONFIGLOCATION/cluster-config-input.json
  sed -i "s/<admin_pwd>/$ADMIN_PWD/g" $CONFIGLOCATION/cluster-config-input.json
  sed -i "s/<docker_password>/$DOCKER_PASSWORD/g" $CONFIGLOCATION/cluster-config-input.json
  sed -i "s/<ip>/$IP/g" $CONFIGLOCATION/cluster-config-input.json
  sed -i "s/<sql_password>/$MSSQL_SA_PASSWORD/g" $CONFIGLOCATION/cluster-config-input.json


  if [ $INSTALLTYPE = 'full' ]; then
    echo "Setting up a full install."
    sed -i "s/<full>/true/g" $CONFIGLOCATION/cluster-config-input.json
  else
    echo "Setting up a basic install."
    sed -i "s/<full>/false/g" $CONFIGLOCATION/cluster-config-input.json
  fi
  echo '---!'
}

function installAS() {
  echo '--- Installing AS'
  echo '--- Installing AS'
  echo '--- Installing AS'
  # Due to Istio bugs, we need to attempt the install twice.
  $UIPATHDIR/installer/install-uipath.sh -i $CONFIGLOCATION/cluster-config-input.json -o $CONFIGLOCATION/cluster-config-output.json -a --accept-license-agreement || $UIPATHDIR/installer/install-uipath.sh -i $CONFIGLOCATION/cluster-config-input.json -o $CONFIGLOCATION/cluster-config-output.json -a --accept-license-agreement
  
  echo 'export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"' >> /root/.bash_profile
  echo 'export PATH="$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin"' >> /root/.bash_profile
  
  echo '---!'
}

function enableCockpit() {
  echo '--- Enabling remote admin cockpit'
  echo '--- Enabling remote admin cockpit'
  echo '--- Enabling remote admin cockpit'
  if [[ $(systemctl list-units --all -t service --full --no-legend "cockpit.service" | sed 's/^\s*//g' | cut -f1 -d' ') == "cockpit.service" ]]; then
    echo 'Cockpit already installed.'
  else
    echo 'Installing Cockpit'
    dnf install -y cockpit
    COCKPITDIR='/etc/systemd/system/cockpit.socket.d'
    mkdir $COCKPITDIR
    touch "$COCKPITDIR/listen.conf"

    cat << EOF >> "$COCKPITDIR/listen.conf"
[Socket]
ListenStream=
ListenStream=45500
EOF

  fi

  systemctl daemon-reload
  systemctl restart cockpit.socket
  systemctl enable cockpit.socket
  echo '---!'
}

function setupCRONSSLJob() {
  echo '--- Setting up CRON job to update certs every month'
  echo '--- Setting up CRON job to update certs every month'
  echo '--- Setting up CRON job to update certs every month'
  #write out current crontab
  crontab -l > sslUpdateCron
  #echo new cron into cron file
  echo "1 2 28 * * \"$DIR/2-update-ssl.sh\" --cron --home \"$DIR\" > /dev/null" >> sslUpdateCron
  #install new cron file
  crontab sslUpdateCron
  rm -f sslUpdateCron
  echo '---!'
}

function setupSSL() {
  echo '--- Setting up SSL certs'
  echo '--- Setting up SSL certs'
  echo '--- Setting up SSL certs'

  dnf install -y socat

  if [ ! -d "/root/.acme.sh" ]; then
    echo 'Installing SSL ACME software'
    wget -O -  https://get.acme.sh | sh -s email=$EMAIL
  else
    echo 'SSL ACME software already installed'
  fi

  if [[ $DNSPROVIDER != "" && $DNSKEY != "" ]]; then
    echo 'Requesting SSL certs'
    if [ $DNSKEY != "" ]; then
      export $DNSKEY
    fi

    if [ $DNSSECRET != "" ]; then
      export $DNSSECRET
    fi

    if [ $DNSIP != "" ]; then
      export $DNSIP
    fi

    /root/.acme.sh/acme.sh --debug --issue --dns $DNSPROVIDER -d "$HOSTNAME.$DOMAIN" -d "*.$HOSTNAME.$DOMAIN" -d "*.$DOMAIN"

    echo 'Updating cert file locations'
    ACMEDIR="\/root\/.acme.sh\/$HOSTNAME.$DOMAIN"
    sed -i "s/<CACERT>/$ACMEDIR\/ca.cer/g" $DIR/settings.cfg
    sed -i "s/<TLSCERT>/$ACMEDIR\/$HOSTNAME.$DOMAIN.cer/g" $DIR/settings.cfg
    sed -i "s/<TLSKEY>/$ACMEDIR\/$HOSTNAME.$DOMAIN.key/g" $DIR/settings.cfg

    echo 'Updating certs in AS'
    source $DIR/2-update-ssl.sh
    echo '---!'

    setupCRONSSLJob
  else
    echo 'Missing DNS information. SSL certs have not been requested or setup.'
  fi
}

function resetPWD() {
  echo '--- Time to rest root password'
  echo '--- Time to rest root password'
  echo '--- Time to rest root password'
  passwd root
  echo '---!'
}

function main() {
  if [ $EMAIL = 'you@youremail.com' ]; then
    echo "First update settings.cfg!"
    return
  fi

  installPackages
  setupISCSI
  updateNetwork
  installkKubectl
  installSQL
  setupASInstaller
  updateASFiles
  createASConfig
  installAS
  enableCockpit
  setupSSL
  updateSystem
  resetPWD

  reboot
}

main





