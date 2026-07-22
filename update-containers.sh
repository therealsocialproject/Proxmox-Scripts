#!/bin/bash

#######################
#  update-containers.sh
#  by sam wozencroft
#
#  version 1.1
#######################

set -e
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
CM='\xE2\x9C\x94\033'
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
while true; do
    read -p "This Will Update All LXC Containers. Proceed(y/n)?" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
clear
function header_info {
echo -e "${BL}
 __  __     ______   _____     ______     ______   __     __   __     ______        __         __  __     ______     ______    
/\ \/\ \   /\  == \ /\  __-.  /\  __ \   /\__  _\ /\ \   /\ "-.\ \   /\  ___\      /\ \       /\_\_\_\   /\  ___\   /\  ___\   
\ \ \_\ \  \ \  _-/ \ \ \/\ \ \ \  __ \  \/_/\ \/ \ \ \  \ \ \-.  \  \ \ \__ \     \ \ \____  \/_/\_\/_  \ \ \____  \ \___  \  
 \ \_____\  \ \_\    \ \____-  \ \_\ \_\    \ \_\  \ \_\  \ \_\\"\_\  \ \_____\     \ \_____\   /\_\/\_\  \ \_____\  \/\_____\ 
  \/_____/   \/_/     \/____/   \/_/\/_/     \/_/   \/_/   \/_/ \/_/   \/_____/      \/_____/   \/_/\/_/   \/_____/   \/_____/ 
                                                                                                                               

${CL}"
}
header_info

containers=$(pct list | tail -n +2 | cut -f1 -d' ')

function update_container() {
  container=$1
  clear
  header_info
  echo -e "${BL}[Info]${GN} Updating${BL} $container ${CL} \n"

  # Get OS type from container config
  os=$(pct config "$container" | awk '/^ostype/ {print $2}')

  case "$os" in
    ubuntu|debian|devuan)
      # Check Ubuntu/Debian codename inside container
      if pct exec "$container" -- [ -f /etc/os-release ]; then
        codename=$(pct exec $container -- bash -c "source /etc/os-release && echo \$VERSION_CODENAME")
        if [[ "$codename" == "oracular" || "$codename" == "groovy" || "$codename" == "eoan" || "$codename" == "hirsute" ]]; then
          echo -e "${BL}[Info]${RD} $codename is EOL. Rewriting sources.list to use old-releases.ubuntu.com...${CL}"
          pct exec $container -- bash -c "sed -i 's|http://archive.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list"
        fi
      fi
      pct exec $container -- bash -c "apt-get update && apt-get dist-upgrade -y && apt-get autoremove -y"
      ;;
    alpine)
      echo -e "${BL}[Info]${GN} Alpine Linux detected. Running apk update/upgrade...${CL}"
      pct exec $container -- apk update
      pct exec $container -- apk upgrade
      ;;
    centos|almalinux|rocky|fedora)
      echo -e "${BL}[Info]${GN} RedHat-based distro ($os) detected. Running dnf/yum upgrade...${CL}"
      if pct exec $container -- hash dnf 2>/dev/null; then
        pct exec $container -- dnf upgrade -y
      else
        pct exec $container -- yum update -y
      fi
      ;;
    archlinux)
      echo -e "${BL}[Info]${GN} Arch Linux detected. Running pacman system upgrade...${CL}"
      pct exec $container -- pacman -Syu --noconfirm
      ;;
    *)
      echo -e "${BL}[Info]${RD} Unknown OS type '$os'. Attempting generic apt update...${CL}"
      pct exec $container -- bash -c "apt-get update && apt-get dist-upgrade -y" || true
      ;;
  esac
}
read -p "Skip stopped containers? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    skip=no
else
    skip=yes
fi

for container in $containers
do
  status=`pct status $container`
 if [ "$skip" == "no" ]; then 
  if [ "$status" == "status: stopped" ]; then
    echo -e "${BL}[Info]${GN} Starting${BL} $container ${CL} \n"
    pct start $container
    echo -e "${BL}[Info]${GN} Waiting For${BL} $container${CL}${GN} To Start ${CL} \n"
    sleep 5
    update_container $container
    echo -e "${BL}[Info]${GN} Shutting down${BL} $container ${CL} \n"
    pct shutdown $container &
  elif [ "$status" == "status: running" ]; then
    update_container $container
  fi
 fi 
 if [ "$skip" == "yes" ]; then
  if [ "$status" == "status: running" ]; then
    update_container $container
  fi
 fi 
done; wait

echo -e "${GN} Finished, All Containers Updated. ${CL} \n"
