#!/bin/bash

# Prompt for the container ID or template
read -p "Enter the container ID or template to clone: " container_id

# Prompt for the ID range for new cloned containers
read -p "Enter the range of IDs for new cloned containers (e.g., 100-110): " id_range

# Extract the start and end IDs from the range input
start_id=$(echo "$id_range" | cut -d'-' -f1)
end_id=$(echo "$id_range" | cut -d'-' -f2)

# Determine if the provided ID is a template and convert it to a VM/CT ID
if echo "$container_id" | grep -q "template"; then
    container_id=$(pvesh get /cluster/nextid)
fi

# Get the name/hostname of the template container
template_name=$(pct config ${container_id} | grep hostname | cut -d':' -f2 | xargs)
if [ -z "$template_name" ]; then
    template_name="lxc"
fi

# Loop to create clones
for (( current_id=$start_id; current_id<=$end_id; current_id++ ))
do
    new_hostname="${template_name}-${current_id}"
    echo "Cloning container ${container_id} to ${current_id} with hostname ${new_hostname}..."
    pct clone ${container_id} ${current_id} --full --hostname "${new_hostname}"
done

echo "Cloning process completed."
