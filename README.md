# uipath-automation-suite-home-server

# Table of Contents
  - [1. Background & Purpose](#1-background--purpose)
  - [2. Requirements](#2-requirements)
  - [3. Preparation](#3-preparation)
  - [4. Installation](#4-installation)
    - [4.1. OS Install](#41-os-install)
      - [4.1.1. Install Via Script](#411-install-via-script)
      - [4.1.2. Install Via GUI](#412-install-via-gui)
    - [4.2. Update Config](#42-update-config)
    - [4.3. Setting Up the OS, Packages, Automation Suite & SSL Certs](#43-setting-up-the-os-packages-automation-suite--ssl-certs)
  - [5. URLs & Login Info](#5-urls--login-info)


# 1. Background & Purpose
A guide and set of scripts to help automate the setup of a non-production home sever of UiPath's Automation Suite.

The following is installed and configured as part of this solution:
- Centos 8
- MS SQL Server (Dev license)
- Automation Suite (basic or full suite of products)
- Zero SSL domain specific certificates
- Cron Job to keep the SSL certificates up-2-date

---

# 2. Requirements
- (Host) PC with at least 16 CPUs, 32 Gib RAM and 1 TiB of HD
- USB drive of >= 16 GiB
- (Recommended) Set a static IP address on an ethernet card (instead of Wifi)
- Your own domain name (e.g. GoDaddy or Namecheap) and the ability to edit the DNS mappings
- N.B. You need API access to your DNS provider
- UiPath license key

---

# 3. Preparation
Ensure you have setup all the DNS details - e.g. A record mapping to your static <b>External</b> IP address. For example, if your server name is "suite", domain name is "automation.com" and external IP is 19.0.0.1, then your DNS records may look something like this:

```

*** A Records in GoDaddy ***

suite.automation.com >> 19.0.0.1
*.suite.automation.com >> 19.0.0.1
alm.suite.automation.com >> 19.0.0.1
monitoring.suite.automation.com >> 19.0.0.1
objectstore.suite.automation.com >> 19.0.0.1
registry.suite.automation.com >> 19.0.0.1
insights.suite.automation.com >> 19.0.0.1

```

For more information, please visit - https://docs.uipath.com/automation-suite/docs/single-node-configuring-the-dns.

---

# 4. Installation
## 4.1. OS Install
On a separate PC/laptop:
- Goto the Centos 8 homepage and download the latest ISO. e.g. https://mirror.aarnet.edu.au/pub/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-latest-dvd1.iso
- Then using a specialist tool such as <b>etcher</b> burn the iso to your USB. *TIP! - Use a Mac, Linux for Personal Windows machine, rather than a work Windows laptop that may have BitLocker enabled which will block you from using unencrypted USB drives.*

Then jumping to the host PC:
- In the BIOS (i.e. via ESC or Del), ensure you have the right boot order setup. Suggest having your main HD as 1 and the Bootable USB as 2. This way each time the PC restarts, it won't try and start another installation.
- Then restart and hold down <b>F7</b> or <b>shift</b> while booting to open the boot menu. Select the USB drive


**<span style="color:red">At this point there are 2 options for installing the OS, either via a script - [4.1.1. Install Via Script](#411-install-via-script) - or through the GUI - [4.1.2. Install Via GUI](#412-install-via-gui).</span>-**

### 4.1.1. Install Via Script
- Once the boot menu loads, select the USB option
- Then when the USB menu pops-up select the top item called "Install Centos Stream ..." <b>don't hit enter</b>, but rather type <b>e</b>
- It should now display something like the following:
```

setparams 'Install CentOS Stream 8-stream'

linuxefi /images/pxeboot/vmlinuz <INSERT HERE LOCATION> inst.stage2...

```

- Then insert the following into the 'INSERT HERE LOCATION':
  - inst.ks=https://bit.ly/3wfSiYw (N.B. this is a shortened bit.ly link)
  - If that doesn't work, then use the original full link (or create a new bit.ly) using https://raw.githubusercontent.com/ch-lukas/uipath-automation-suite-home-server/main/0-install-os.cfg 
  - It should look something like the below - 

```

setparams 'Install CentOS Stream 8-stream'

linuxefi /images/pxeboot/vmlinuz inst.ks=https://bit.ly/3QYgCWG inst.stage2...

```
- Press **ctrl-x** when done and the server will restart and the install begins.

**<span style="color:red">If there are any issues with the script, the GUI will ask you to fix those elements before proceeding. If that happens, try the GUI install option instead.</span>**

#### 4.1.2. Install Via GUI
After the USB has kicked in, select the first item from the menu and it should take you to the main GUI:
- Select <b>Language</b> (e.g. au)
- Set <b>Timezone</b> (e.g. Sydney)
- Set <b>Root password</b>
- In <b>User Creation</b>, setup a new user (i.e. name, password and set as administrator)
- Can leave <b>Installation Source</b> and <b>Software Selection</b> values as default
- For <b>Network & Host Name</b>:
  - Change host name (i.e. bottom left) to e.g. suite.yourdomain.com and apply
  - Suggest using a cable network card instead of Wifi - hence keep wireless disabled
- For <b>Installation Destination</b>:
  - Select disk and tick Custom under <b>Storage Configuration</b> as we are going to reformat the entire drive and create brand new partitions. (N.B. All previous data will be wiped)
  - Click done and enter the following:
    - If there are current partitions on the drive we need to select one and delete it by selecting the "-" symbol near the bottom left. When the popup asks you if you want to remove everything, tick yes.
    - Now click on <b>Click here to create them automatically</b> to help setup the initial partitions.
    - Select the /home partition and change the capacity to <b>20 Gib</b>
    - Using the "+" symbol create the following (case sensitive):
      - Mount Point: /var/lib/rancher  Capacity: 190 GiB
      - Mount Point: /var/lib/kubelet  Capacity: 56 GiB
      - Mount Point: /opt/UiPathAutomationSuite  Capacity: 10 GiB
      - Mount Point: /var/lib/rancher/rke2/server/db  Capacity: 16 GiB
      - Mount Point: /datadisk  Capacity: 512 GiB
  - Click done and accept changes
- Begin the installation process
- After logging in, reboot to ensure everything is finalised
- Now you are done with the host server

---

## 4.2. Update Config
Jumping back onto your laptop
- Open up <b>Terminal</b> (for Macs) or <b>PowerShell</b> for Windows
- Use SSH to connect to your host. i.e. ssh root@yourhostip example below -
  
```

ssh root@192.168.1.20
# Default password is "Uipath!!"

```

- Download this Git repo
  
```

git clone https://github.com/ch-lukas/uipath-automation-suite-home-server.git ~/uipath-automation-suite-home-server
chmod -R 755 ./uipath-automation-suite-home-server
cd ~/uipath-automation-suite-home-server

```
- At this point, if you haven't already cloned the repo and updated the <b>settings.cfg</b> file. Then do it now and ensure the settings match your needs. The default values are:
  
```

#############################
#
# Settings & configuration
#
#############################
VERSION='2022.4.0' # Add the UiPath Automation Suite version number you are trying to install. Ex: for 2022.4.0 Set VERSION='2022.4.0'
INSTALLTYPE='basic' # 'basic' excludes AiCenter / DU / Apps / TaskMining and 'full' has everything

# SSL
EMAIL='you@youremail.com' # Email to receive SSL update notificiations
DNSPROVIDER='dns_gd' # E.g. for GoDaddy. Other codes available from https://github.com/acmesh-official/acme.sh/wiki/dnsapi
DNSKEY="GD_Secret='abcd'" # Key or Token. Details in link above
DNSSECRET="GD_Key='abcd'" # Sometimes is blank. Details in link above
DNSIP="" # Source IP, Endpoint or sometimes is blank. Details in link above


# Network details
NETDEVICE='eno1' # Network device name you want to use - e.g. eno1 is typical for a ethernet card
HOSTNAME='suite' # Full name would then be suite.happipaths.com
DOMAIN='processes.com' # E.g. domain name registerd on GoDaddy
IP='192.168.1.20' # DHCP will be disabled and this static IP assigned
SUBNET='255.255.255.0'
GATEWAY='192.168.1.1' # Usually the IP of your wifi router
DNS='192.168.1.1' # Usually the IP of your wifi router

# MS SQL
MSSQL_SA_PASSWORD='Uipath!!' # Initial pwd, please change

# Below is automatically updated - don't manually change
RKE_TOKEN='<rke_token>'
CACERT='<CACERT>'
TLSCERT='<TLSCERT>'
TLSKEY='<TLSKEY>'
#############################

```

---

## 4.3. Setting Up the OS, Packages, Automation Suite & SSL Certs
- Navigate to cloned folder - e.g. cd /uipath-home-server - and run the first script.
  
```

./1-install-as.sh

```

- Keep an eye out for any errors.
- If successful, it will prompt you at the end to change the root password.

---

**<span style="color:green">Congrats!! You are all done.</span>**

# 5. URLs & Login Info

Using the suite.automation.com example again...

```

===============================================================================
                              Deployment summary
===============================================================================

To access the server's admin console whilste on your home network, navigate to:
https://yourIPaddress:45500

===============================================================================

Before running any kubectl commands run the following commands:
> sudo su -
> export KUBECONFIG="/etc/rancher/rke2/rke2.yaml" \
&& export PATH="$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin"

Continue to run the rest of the commands as root.

===============================================================================

To configure shared suite capabilities and start building automations, go to
the Portal:

- URL: https://suite.automation.com
- Switch to the "Default" organization
- Credentials: The username is "orgadmin". Run the following command to retrieve the password:
> kubectl get secrets/platform-service-secrets -n uipath \
-o "jsonpath={.data['identity\.hostAdminPassword']}" | echo $(base64 -d)

Using the same command to retrieve the org admin and the host admin passwords is by design -
the two passwords are initially the same. However, upon the first login, the org admin must
change their password.

===============================================================================

To access the Host organization:

- URL: https://suite.automation.com
- Switch to the "Host" organization
- Credentials: The username is "admin". Run the following command to retrieve the password:
> kubectl get secrets/platform-service-secrets -n uipath \
-o "jsonpath={.data['identity\.hostAdminPassword']}" | echo $(base64 -d)

Using the same command to retrieve the org admin and the host admin passwords is by design -
the two passwords are initially the same. However, upon the first login, the org admin must
change their password.

===============================================================================

To manage the Kubernetes cluster (monitoring & troubleshooting), go to the
Rancher console.

- URL: https://monitoring.suite.automation.com
- Credentials: The username is "admin". Run the following command to retrieve the password:
> kubectl get secrets/rancher-admin-password -n cattle-system \
-o "jsonpath={.data['password']}" | echo $(base64 -d)


===============================================================================

To manage the installed products (install/uninstall & configure) and certificates,
go to the ArgoCD console.

- URL: https://alm.suite.automation.com
- Credentials: The username is "argocdro". Run the following command to retrieve the password:
> kubectl get secrets/argocd-user-password -n argocd \
-o "jsonpath={.data['password']}" | echo $(base64 -d)

===============================================================================

About self-signed certificates and token signing

The auto generated self-signed certificate is valid for 90 days and is used for both secure
connection to the website as well as for signing the authentication tokens issued
by the Automation Suite identity server.

For production deployments we strongly recommend using a public/trusted certificate.
To replace the self-signed certificate and to learn more about the certificates used
by the Automation Suite, refer to the public documentation:
https://docs.uipath.com/automation-suite/docs


To retrieve the current certificate, run the following command:

> kubectl get secrets/istio-ingressgateway-certs -n istio-system \
-o "jsonpath={.data['tls\.crt']}" | echo $(base64 -d)

```





