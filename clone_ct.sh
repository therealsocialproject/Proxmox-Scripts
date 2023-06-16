#!/bin/bash

# Prompt for the container ID
read -p "Enter the container ID to clone: " container_id

# Prompt for the number of copies
read -p "Enter the number of copies to make: " num_copies

# Loop to create clones
for ((i=1; i<=num_copies; i++))
do
    new_id="${container_id}_clone${i}"
    echo "Cloning container ${container_id} to ${new_id}..."
    pct clone ${container_id} ${new_id}
done

echo "Cloning process completed."
