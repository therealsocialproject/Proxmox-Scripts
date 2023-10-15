#!/bin/bash

# Prompt for VM ID or template
read -p "Enter the VM ID or template to clone: " vm_id

# Prompt for ID range for new cloned VMs (e.g., 201-204)
read -p "Enter the range of IDs for new cloned VMs (e.g., 201-204): " id_range

# Prompt to choose between full clone (1) or linked clone (2)
read -p "Choose the type of clone (1 for full, 2 for linked): " clone_type

# Validate the user's choice
if [[ "$clone_type" == "1" ]]; then
    clone_option="--full"
elif [[ "$clone_type" == "2" ]]; then
    clone_option="--linked"
else
    echo "Invalid choice. Please enter 1 for full clone or 2 for linked clone."
    exit 1
fi

# Extract the start and end IDs from the range input
start_id=$(echo "$id_range" | cut -d'-' -f1)
end_id=$(echo "$id_range" | cut -d'-' -f2)

# Get the name of the template VM
template_name=$(qm config ${vm_id} | grep name | cut -d':' -f2 | xargs)

# Check if the start and end IDs are numeric
if [[ "$start_id" =~ ^[0-9]+$ ]] && [[ "$end_id" =~ ^[0-9]+$ ]]; then
    # Loop to create clones
    for (( current_id=start_id; current_id<=end_id; current_id++ ))
    do
        new_vm_name="${template_name}"
        echo "Creating ${clone_option:2} clone of VM ${vm_id} with ID ${current_id} and name ${new_vm_name}..."
        qm clone ${vm_id} ${current_id} ${clone_option} --name ${new_vm_name}
    done
else
    echo "Invalid range. Start and end IDs must be numeric."
fi

echo "${clone_option:2} clone creation process completed."
