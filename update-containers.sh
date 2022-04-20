
#!/bin/bash

#######################
#  update-containers.sh
#  by sam wozencroft
#
#  version 1.0
#######################

#Grep containers
containers=$(pct list | grep "running" | cut -f1 -d' ')

#Wrap function
function update_container() {
   container=$1
    echo "Updating $container..."
   pct exec $container -- bash -c "apt update && apt upgrade -y"
}

for container in $containers
 do
   update_container $container
 done
