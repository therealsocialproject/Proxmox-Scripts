
#!/bin/bash

#######################
#  post-install.sh
#  by sam wozencroft
#
#  version 1.0
#######################

umask 022

#RegConsts
RED='\033[0;31m'
BRED='\033[0;31m\033[1m'
GRN='\033[92m'
WARN='\033[93m'
BOLD='\033[1m'
REG='\033[0m'
CHECKMARK='\033[0;32m\xE2\x9C\x94\033[0m'

TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"
SCRIPTPATH="${SCRIPTDIR}$(basename "${BASH_SOURCE[0]}")"

OFFLINEDIR="${SCRIPTDIR}offline"

REPO=${REPO:-"samwozencroft/Proxmox-Scripts/"}
DEFAULT_TAG="post-install.sh"
TAG=${TAG:-$DEFAULT_TAG}
BASE_URL="https://raw.githubusercontent.com/$REPO/$TAG"

OFFLINE=false
#EndConsts

#Pre-Req
if [[ $EUID -ne 0 ]]; then
    echo -e >&2 "${BRED}Root privileges are required to perform this operation${REG}";
    exit 1
fi

hash sed 2>/dev/null || { 
    echo -e >&2 "${BRED}sed is required but missing from your system${REG}";
    exit 1;
}

hash pveversion 2>/dev/null || { 
    echo -e >&2 "${BRED}PVE installation required but missing from your system${REG}";
    exit 1;
}

if test -d "$OFFLINEDIR"; then
    echo "Offline directory detected, entering offline mode."
    OFFLINE=true
else
    hash curl 2>/dev/null || { 
        echo -e >&2 "${BRED}cURL is required but missing from your system${REG}";
        exit 1;
    }
fi

if [ "$OFFLINE" = false ]; then
    curl -sSf -f https://github.com/robots.txt &> /dev/null || {
        echo -e >&2 "${BRED}Could not establish a connection to GitHub (github.com)${REG}";
        exit 1;
    }

    if [ $TAG != $DEFAULT_TAG ]; then
        if !([[ $TAG =~ [0-9] ]] && [ ${#TAG} -ge 7 ] && (! [[ $TAG =~ ['!@#$%^&*()_+.'] ]]) ); then 
            echo -e "${WARN}It appears like you are using a non-default tag. For security purposes, please use the SHA-1 hash of said tag instead${REG}"
        fi
    fi
fi
#EndPre-Req

echo -e "\e[1;33m This script will Setup Repositories and attempt the No-Nag fix. PVE 7, 8, & 9 \e[0m"
while true; do
    read -p "Start the PVE Post Install Script (y/n)? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

pve_major=$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}' | awk -F'.' '{print $1}')
if [ "$pve_major" -ne 7 ] && [ "$pve_major" -ne 8 ] && [ "$pve_major" -ne 9 ]; then
        echo -e "This script requires Proxmox Virtual Environment 7, 8, or 9."
        echo -e "Exiting..."
        sleep 2
        exit
fi

case "$pve_major" in
  7) CODENAME="bullseye" ;;
  8) CODENAME="bookworm" ;;
  9) CODENAME="trixie" ;;
esac

clear
echo -e "\e[1;33m Disable Enterprise Repository...  \e[0m"
sleep 1
sed -i "s/^deb/#deb/g" /etc/apt/sources.list.d/pve-enterprise.list
echo -e "\e[1;33m Setup Repositories for PVE $pve_major ($CODENAME)...  \e[0m"
sleep 1
cat <<EOF > /etc/apt/sources.list
deb http://ftp.debian.org/debian $CODENAME main contrib
deb http://ftp.debian.org/debian $CODENAME-updates main contrib
deb http://security.debian.org/debian-security $CODENAME-security main contrib
deb http://download.proxmox.com/debian/pve $CODENAME pve-no-subscription
# deb http://download.proxmox.com/debian/pve $CODENAME pvetest
EOF
echo -e "\e[1;33m Disable Subscription Nag...  \e[0m"
echo "DPkg::Post-Invoke { \"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ \$? -eq 1 ]; then { echo 'Removing subscription nag from UI...'; sed -i '/data.status/{s/\!//;s/Active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi\"; };" > /etc/apt/apt.conf.d/no-nag-script
apt --reinstall install proxmox-widget-toolkit &>/dev/null
echo -e "\e[1;33m Finished....Please Update Proxmox \e[0m"

