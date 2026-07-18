#!/bin/bash

# Interactive PHPRunner Container Creator (Whiptail UI)
# Creates ready-to-use containers for PHPRunner applications
# Optimized for Ubuntu LTS systems only
#
# GitHub: https://github.com/wdbenj/proxmox-phprunner-lxc
# License: MIT
# Author: Billy Benjamin
# Version: 1.0.0 (Whiptail UI)

set -e

# Enable debug mode with: DEBUG=1 ./script.sh
DEBUG=${DEBUG:-0}

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Debug function
debug_log() {
    if [ "$DEBUG" = "1" ]; then
        print_color $PURPLE "DEBUG: $1"
    fi
}

# Function to show whiptail message box
show_message() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --msgbox "$message" 20 70
}

# Function to show whiptail input box
get_input() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local result
    
    if [ -n "$default" ]; then
        result=$(whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3)
    else
        result=$(whiptail --title "$title" --inputbox "$prompt" 10 60 3>&1 1>&2 2>&3)
    fi
    
    echo "$result"
}

# Function to show whiptail yes/no dialog
get_yes_no() {
    local title="$1"
    local message="$2"
    local default="$3"
    
    if [ "$default" = "yes" ]; then
        whiptail --title "$title" --yesno "$message" 10 60
    else
        whiptail --title "$title" --yesno "$message" 10 60
    fi
    
    return $?
}

# Function to show whiptail menu
get_menu_choice() {
    local title="$1"
    local message="$2"
    shift 2
    local options=("$@")
    
    local choice
    choice=$(whiptail --title "$title" --menu "$message" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3)
    echo "$choice"
}

# Function to show whiptail checklist
get_checklist() {
    local title="$1"
    local message="$2"
    shift 2
    local options=("$@")
    
    local choices
    choices=$(whiptail --title "$title" --checklist "$message" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3)
    echo "$choices"
}

# Function to check if container or VM ID already exists
check_id_exists() {
    local id=$1
    local container_exists=false
    local vm_exists=false
    
    # Check if container exists
    if pct status $id >/dev/null 2>&1; then
        container_exists=true
    fi
    
    # Check if VM exists
    if qm status $id >/dev/null 2>&1; then
        vm_exists=true
    fi
    
    if [ "$container_exists" = true ] || [ "$vm_exists" = true ]; then
        local error_msg=""
        if [ "$container_exists" = true ]; then
            error_msg="Container ID $id already exists!"
        fi
        if [ "$vm_exists" = true ]; then
            error_msg="${error_msg}VM ID $id already exists!"
        fi
        show_message "ID Conflict" "$error_msg\n\nPlease choose a different ID."
        return 1
    fi
    
    return 0
}

# Function to get available PHP versions
get_available_php_versions() {
    # Return well-known available versions - no complex detection
    echo "8.4 8.3 8.2 8.1 8.0 7.4"
} 

# Function to list available Ubuntu LTS templates only
list_ubuntu_lts_templates() {
    print_color $CYAN "📋 Scanning for Ubuntu LTS container templates..."
    
    local templates=()
    local template_paths=()
    local menu_options=()
    
    debug_log "Starting Ubuntu LTS template scan..."
    
    # First check pveam available for downloadable templates
    print_color $YELLOW "🔍 Checking downloadable Ubuntu LTS templates..."
    mapfile -t AVAILABLE_TEMPLATES < <(pveam available 2>/dev/null | grep -E 'ubuntu-([0-9]{2})\.04-standard' | while read -r line; do
        # Extract version number and check if it's even (LTS)
        if [[ $line =~ ubuntu-([0-9]{2})\.04 ]]; then
            version="${BASH_REMATCH[1]}"
            # Only include even-numbered years (LTS releases)
            if (( version % 2 == 0 )); then
                echo "$line"
            fi
        fi
    done | sort -r || true)
    
    if [ ${#AVAILABLE_TEMPLATES[@]} -gt 0 ]; then
        print_color $GREEN "Found ${#AVAILABLE_TEMPLATES[@]} downloadable Ubuntu LTS templates"
        for template_line in "${AVAILABLE_TEMPLATES[@]}"; do
            local template_name=$(echo "$template_line" | awk '{print $2}')
            local version=$(echo "$template_name" | grep -oP 'ubuntu-\K[0-9]{2}\.[0-9]{2}')
            local display_name="Ubuntu $version LTS (downloadable)"
            
            templates+=("$display_name")
            template_paths+=("download:$template_name")
            menu_options+=("$display_name" "Download from repository")
            
            debug_log "Added downloadable template: $display_name -> download:$template_name"
        done
    fi
    
    # Get storages that support templates for local check
    local template_storages=()
    while IFS= read -r line; do
        if [[ $line =~ ^([^[:space:]]+)[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
            local storage_name="${BASH_REMATCH[1]}"
            local content_types="${BASH_REMATCH[2]}"
            
            # Check if storage supports vztmpl (templates)
            if [[ $content_types == *"vztmpl"* ]]; then
                template_storages+=("$storage_name")
                debug_log "Found template storage: $storage_name"
            fi
        fi
    done < <(pvesm status | tail -n +2)
    
    # Check each template storage for existing Ubuntu templates
    local found_local=false
    for storage in "${template_storages[@]}"; do
        debug_log "Checking storage: $storage"
        
        # Get templates from this storage
        local storage_output
        storage_output=$(pvesm list "$storage" 2>/dev/null | tail -n +2 || true)
        
        debug_log "Storage $storage output:"
        if [ "$DEBUG" = "1" ]; then
            echo "$storage_output"
        fi
        
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                debug_log "Processing line: $line"
                
                # Check if line contains Ubuntu template
                if [[ $line == *"ubuntu"* ]] && ([[ $line == *".tar"* ]] || [[ $line == *"vztmpl"* ]]); then
                    # Extract the filename/ID from different possible formats
                    local template_file=$(echo "$line" | awk '{print $1}')
                    local template_name=""
                    
                    # Handle different template path formats
                    if [[ $template_file == *":"* ]]; then
                        # Already includes storage, extract just the filename
                        template_name=$(basename "$template_file")
                    else
                        template_name="$template_file"
                    fi
                    
                    debug_log "Extracted template name: $template_name"
                    
                    # Only process Ubuntu LTS versions (xx.04 where xx is even)
                    if [[ $template_name == *"ubuntu"* ]] && [[ $template_name =~ ubuntu-([0-9]{2})\.04 ]]; then
                        local version_num="${BASH_REMATCH[1]}"
                        # Only include even-numbered years (LTS releases)
                        if (( version_num % 2 == 0 )); then
                        local version="${BASH_REMATCH[1]}.04"
                        local display_name="Ubuntu $version LTS (installed)"
                        
                        # Construct full template path
                        local full_path
                        if [[ $template_file == *":"* ]]; then
                            # Already has storage prefix
                            full_path="$template_file"
                        elif [[ $template_name == *".tar"* ]]; then
                            # Template file in vztmpl directory
                            full_path="$storage:vztmpl/$template_name"
                        else
                            # Might be in a different format
                            full_path="$storage:$template_name"
                        fi
                        
                        templates+=("$display_name")
                        template_paths+=("$full_path")
                        menu_options+=("$display_name" "Already installed")
                        found_local=true
                        
                        debug_log "Added local template: $display_name -> $full_path"
                        fi
                    else
                        debug_log "Skipping non-LTS Ubuntu template: $template_name"
                    fi
                fi
            fi
        done <<< "$storage_output"
    done
    
    # If no templates found, offer to download latest Ubuntu LTS
    if [ ${#templates[@]} -eq 0 ]; then
        print_color $RED "❌ No Ubuntu LTS container templates found!"
        echo
        print_color $YELLOW "💡 Troubleshooting tips:"
        echo "1. Check if templates exist: ls -la /var/lib/vz/template/cache/"
        echo "2. List all templates: pveam list"
        echo "3. Update template list: pveam update"
        echo "4. Enable debug mode: DEBUG=1 ./script.sh"
        echo "5. Check storage content types: pvesm status"
        echo
        
        if get_yes_no "Download Template" "Would you like to download Ubuntu 24.04 LTS template now?"; then
            download_ubuntu_lts_template
            # Restart template detection after download
            list_ubuntu_lts_templates
            return
        else
            show_message "Error" "Cannot proceed without an Ubuntu LTS template.\n\nTo manually download templates:\n  pveam update\n  pveam download local ubuntu-24.04-standard_24.04-1_amd64.tar.zst\n  pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
            exit 1
        fi
    fi
    
    # Show template selection menu
    local choice
    choice=$(get_menu_choice "Template Selection" "Choose an Ubuntu LTS template:" "${menu_options[@]}")
    
    if [ -z "$choice" ]; then
        show_message "Cancelled" "Template selection was cancelled."
        exit 1
    fi
    
    # Find the selected template index
    local selected_index=-1
    for i in "${!templates[@]}"; do
        if [ "${templates[$i]}" = "$choice" ]; then
            selected_index=$i
            break
        fi
    done
    
    if [ $selected_index -eq -1 ]; then
        show_message "Error" "Invalid template selection."
        exit 1
    fi
    
    # Set selected template
    local selected_path="${template_paths[$selected_index]}"
    SELECTED_TEMPLATE_NAME="${templates[$selected_index]}"
    
    # Handle download vs existing template
    if [[ $selected_path == download:* ]]; then
        # Download the template
        local template_name="${selected_path#download:}"
        
        # Check if template already exists
        local template_exists=false
        for storage in "${template_storages[@]}"; do
            if pveam list "$storage" 2>/dev/null | grep -q "$template_name"; then
                template_exists=true
                SELECTED_TEMPLATE="$storage:vztmpl/$template_name"
                print_color $GREEN "✅ Template already exists: $template_name"
                break
            fi
        done
        
        if [ "$template_exists" = false ]; then
            print_color $YELLOW "📥 Downloading template: $template_name"
            
            # Find a storage that supports templates for download
            local template_storage=""
            for storage in "${template_storages[@]}"; do
                template_storage="$storage"
                break
            done
            
            if [ -z "$template_storage" ]; then
                template_storage="local"  # Fallback to local
            fi
            
            # Update template list first
            pveam update
            
            # Download the template
            if pveam download "$template_storage" "$template_name"; then
                SELECTED_TEMPLATE="$template_storage:vztmpl/$template_name"
                print_color $GREEN "✅ Template downloaded successfully!"
            else
                show_message "Error" "Failed to download template. Please check your internet connection."
                exit 1
            fi
        fi
    else
        # Use existing template
        SELECTED_TEMPLATE="$selected_path"
    fi
    
    print_color $GREEN "✅ Selected: $SELECTED_TEMPLATE_NAME"
    print_color $CYAN "📁 Template path: $SELECTED_TEMPLATE"
    
    # Set OS type for Ubuntu
    OS_TYPE="ubuntu"
    PKG_MANAGER="apt"
    PKG_UPDATE="apt update && apt dist-upgrade -y"
    PKG_INSTALL="apt install -y"
    WEB_USER="www-data"
    print_color $GREEN "🟠 Ubuntu system selected"
}

# Function to download Ubuntu LTS template
download_ubuntu_lts_template() {
    # Find a storage that supports templates
    local template_storage=""
    while IFS= read -r line; do
        if [[ $line =~ ^([^[:space:]]+)[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
            local storage_name="${BASH_REMATCH[1]}"
            local content_types="${BASH_REMATCH[2]}"
            
            if [[ $content_types == *"vztmpl"* ]]; then
                template_storage="$storage_name"
                break
            fi
        fi
    done < <(pvesm status | tail -n +2)
    
    if [ -z "$template_storage" ]; then
        show_message "Error" "No storage found that supports templates (vztmpl content type)!\n\nPlease configure storage for templates in Proxmox web UI"
        exit 1
    fi
    
    print_color $YELLOW "📥 Updating template list..."
    pveam update
    
    print_color $YELLOW "📥 Downloading Ubuntu 24.04 LTS template to storage: $template_storage..."
    if pveam download "$template_storage" ubuntu-24.04-standard_24.04-1_amd64.tar.zst; then
        print_color $GREEN "✅ Ubuntu 24.04 LTS template downloaded successfully!"
        SELECTED_TEMPLATE="$template_storage:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
        SELECTED_TEMPLATE_NAME="🟠 Ubuntu 24.04 LTS"
    else
        show_message "Error" "Failed to download template. Please check your internet connection."
        exit 1
    fi
}

# Main setup function
main() {
    # Check if whiptail is available
    if ! command -v whiptail >/dev/null 2>&1; then
        print_color $RED "❌ whiptail is not installed. Please install it first:"
        echo "  apt-get install whiptail"
        exit 1
    fi

    # Show welcome screen
    show_message "Welcome" "Interactive PHPRunner Container Creator\n\nThis script will help you create a ready-to-use LXC container for PHPRunner applications.\n\nPress OK to continue."

    # Detect host system locale for container
    HOST_LOCALE=$(locale | grep LANG= | cut -d'=' -f2 | head -1)
    if [ -z "$HOST_LOCALE" ] || [ "$HOST_LOCALE" = "C" ]; then
        HOST_LOCALE="en_US.UTF-8"
        print_color $YELLOW "⚠️  No locale detected, using default: $HOST_LOCALE"
    else
        print_color $CYAN "🌐 Detected host locale: $HOST_LOCALE"
    fi

    # Ubuntu LTS template selection only
    list_ubuntu_lts_templates

    # Container ID with existence check
    while true; do
        CONTAINER_ID=$(get_input "Container ID" "Enter container ID (100 or higher, must be unused):" "")

        # No default on purpose: the user must consciously choose an ID so we can
        # never propose one that belongs to a live container/VM.
        if [ -z "$CONTAINER_ID" ]; then
            show_message "Error" "Container ID cannot be empty."
            continue
        fi

        if ! [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
            show_message "Error" "Container ID must be a number (e.g. 210)."
            continue
        fi

        if [ "$CONTAINER_ID" -lt 100 ]; then
            show_message "Error" "Container ID must be 100 or higher (Proxmox reserves 1-99)."
            continue
        fi

        if check_id_exists $CONTAINER_ID; then
            break
        else
            if ! get_yes_no "Try Again" "Would you like to try a different ID?"; then
                show_message "Cancelled" "Container creation cancelled."
                exit 1
            fi
        fi
    done

    # Basic container settings
    HOSTNAME=$(get_input "Hostname" "Enter container hostname:" "phprunner-template")
    if [ -z "$HOSTNAME" ]; then
        HOSTNAME="phprunner-template"
    fi
    
    MEMORY=$(get_input "Memory" "Enter memory in MB:" "1024")
    if [ -z "$MEMORY" ]; then
        MEMORY="1024"
    fi
    
    # Storage selection
    print_color $CYAN "📋 Checking available storage for containers..."
    local container_storages=()
    
    # Read storage configuration from Proxmox config file
    if [ -f "/etc/pve/storage.cfg" ]; then
        debug_log "Reading storage config from /etc/pve/storage.cfg"
        
        # Parse storage configuration
        local current_storage=""
        while IFS= read -r line; do
            debug_log "Config line: $line"
            
            # New storage section
            if [[ $line =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                local storage_type="${BASH_REMATCH[1]}"
                local storage_name="${BASH_REMATCH[2]}"
                current_storage="$storage_name"
                debug_log "Found storage: $storage_name (type: $storage_type)"
            fi
            
            # Content line for current storage
            if [[ $line =~ ^[[:space:]]*content[[:space:]]+(.+)$ ]] && [ -n "$current_storage" ]; then
                local content_types="${BASH_REMATCH[1]}"
                debug_log "Storage $current_storage content: $content_types"
                
                # Check if content includes rootdir or images
                if [[ $content_types == *"rootdir"* ]] || [[ $content_types == *"images"* ]]; then
                    container_storages+=("$current_storage")
                    print_color $GREEN "  ✅ $current_storage - supports containers ($content_types)"
                else
                    print_color $YELLOW "  ⚠️  $current_storage - no container support ($content_types)"
                fi
            fi
            
            # Reset current storage on empty line or new section
            if [[ $line =~ ^[[:space:]]*$ ]] || [[ $line =~ ^[^[:space:]] ]]; then
                if [[ ! $line =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    current_storage=""
                fi
            fi
        done < /etc/pve/storage.cfg
    else
        print_color $YELLOW "⚠️  Could not read /etc/pve/storage.cfg"
    fi
    
    # If no storages found or detection failed, show manual selection
    if [ ${#container_storages[@]} -eq 0 ]; then
        print_color $RED "❌ Storage auto-detection failed!"
        echo
        print_color $CYAN "Available storage (manual selection):"
        local all_storages=($(pvesm status | awk 'NR>1 {print $1}'))
        
        local storage_menu_options=()
        for i in "${!all_storages[@]}"; do
            storage_menu_options+=("${all_storages[i]}" "Storage option $((i+1))")
        done
        
        STORAGE=$(get_menu_choice "Storage Selection" "Select storage manually:" "${storage_menu_options[@]}")
        
        if [ -z "$STORAGE" ]; then
            show_message "Error" "Storage selection is required."
            exit 1
        fi
        
        print_color $YELLOW "⚠️  Using manually selected storage: $STORAGE"
        print_color $YELLOW "If container creation fails, this storage may not support containers."
    elif [ ${#container_storages[@]} -eq 1 ]; then
        STORAGE="${container_storages[0]}"
        print_color $GREEN "✅ Auto-selected storage: $STORAGE"
    else
        local storage_menu_options=()
        for i in "${!container_storages[@]}"; do
            storage_menu_options+=("${container_storages[i]}" "Container storage option $((i+1))")
        done
        
        STORAGE=$(get_menu_choice "Storage Selection" "Choose container storage:" "${storage_menu_options[@]}")
        
        if [ -z "$STORAGE" ]; then
            show_message "Error" "Storage selection is required."
            exit 1
        fi
        
        print_color $GREEN "✅ Selected storage: $STORAGE"
    fi
    
    ROOTFS_SIZE=$(get_input "Root Filesystem Size" "Enter root filesystem size in GB:" "100")
    if [ -z "$ROOTFS_SIZE" ]; then
        ROOTFS_SIZE="100"
    fi
    
    # Network configuration
    local net_options=("DHCP" "Automatic IP assignment" "Static" "Manual IP configuration")
    NET_TYPE=$(get_menu_choice "Network Configuration" "Choose network type:" "${net_options[@]}")
    
    if [ "$NET_TYPE" = "Static" ]; then
        STATIC_IP=$(get_input "Static IP" "Enter static IP (e.g., 192.168.1.100/24):" "")
        if [ -z "$STATIC_IP" ]; then
            show_message "Error" "Static IP is required for static network configuration."
            exit 1
        fi
        
        GATEWAY=$(get_input "Gateway" "Enter gateway IP:" "192.168.1.1")
        if [ -z "$GATEWAY" ]; then
            GATEWAY="192.168.1.1"
        fi
        
        NET_CONFIG="name=eth0,bridge=vmbr0,ip=$STATIC_IP,gw=$GATEWAY"
    else
        NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
    fi

    # Web server selection
    local web_server_options=("Apache2" "Full .htaccess support, better PHPRunner compatibility" "Nginx" "Lightweight, high performance")
    WEB_SERVER_CHOICE=$(get_menu_choice "Web Server Selection" "Choose web server:" "${web_server_options[@]}")
    
    case $WEB_SERVER_CHOICE in
        "Apache2") WEB_SERVER="apache2";;
        "Nginx") WEB_SERVER="nginx";;
        *) WEB_SERVER="apache2";;
    esac
    
    print_color $GREEN "✅ Selected web server: $WEB_SERVER"

    # PHP version selection
    local available_versions=$(get_available_php_versions)
    local version_array=($available_versions)
    local php_menu_options=()
    
    for i in "${!version_array[@]}"; do
        local version="${version_array[i]}"
        local status=""
        case $version in
            "8.4") status=" (Latest)";;
            "8.3") status=" (Stable)";;
            "8.2") status=" (LTS)";;
            "8.1") status=" (Legacy)";;
        esac
        php_menu_options+=("PHP $version" "Version $version$status")
    done
    
    PHP_CHOICE=$(get_menu_choice "PHP Version Selection" "Choose PHP version:" "${php_menu_options[@]}")
    
    if [ -z "$PHP_CHOICE" ]; then
        PHP_VERSION="8.4"
    else
        PHP_VERSION=$(echo "$PHP_CHOICE" | grep -oP 'PHP \K[0-9]+\.[0-9]+')
    fi
    
    print_color $GREEN "✅ Selected PHP $PHP_VERSION"

    # Additional components
    local component_options=("Redis" "Install Redis server" "Composer" "Install Composer package manager" "MySQL" "Install MySQL/MariaDB server")
    COMPONENTS=$(get_checklist "Additional Components" "Select additional components to install:" "${component_options[@]}")
    
    INSTALL_REDIS="no"
    INSTALL_COMPOSER="no"
    INSTALL_MYSQL="no"
    
    if [[ "$COMPONENTS" == *"Redis"* ]]; then
        INSTALL_REDIS="yes"
    fi
    if [[ "$COMPONENTS" == *"Composer"* ]]; then
        INSTALL_COMPOSER="yes"
    fi
    if [[ "$COMPONENTS" == *"MySQL"* ]]; then
        INSTALL_MYSQL="yes"
    fi

    # SSL Configuration
    if get_yes_no "SSL Configuration" "Prepare SSL infrastructure?"; then
        SETUP_SSL="yes"
        SSL_EMAIL=$(get_input "SSL Email" "Enter email for SSL certificates:" "admin@example.com")
        if [ -z "$SSL_EMAIL" ]; then
            SSL_EMAIL="admin@example.com"
        fi
    else
        SETUP_SSL="no"
        SSL_EMAIL=""
    fi

    # Timezone
    TIMEZONE=$(get_input "Timezone" "Enter PHP timezone:" "America/Edmonton")
    if [ -z "$TIMEZONE" ]; then
        TIMEZONE="America/Edmonton"
    fi

    # Always use production settings (no prompt)
    OPTIMIZATION="2"  # Production
    
    # SSH Configuration
    if get_yes_no "SSH Configuration" "Enable SSH access to container?" "no"; then
        ENABLE_SSH="yes"
    else
        ENABLE_SSH="no"
    fi

    # Container root password setup (always required)
    print_color $CYAN "\nRoot Password Configuration:"
    while true; do
        ROOT_PASSWORD=$(get_input "Root Password" "Enter root password for container:" "")
        if [ -z "$ROOT_PASSWORD" ]; then
            show_message "Error" "Root password cannot be empty."
            continue
        fi
        
        ROOT_PASSWORD_CONFIRM=$(get_input "Confirm Password" "Confirm root password:" "")
        
        if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
            if [ ${#ROOT_PASSWORD} -lt 6 ]; then
                show_message "Error" "Password too short. Please use at least 6 characters."
                continue
            fi
            SET_ROOT_PASSWORD="yes"
            break
        else
            show_message "Error" "Passwords do not match. Please try again."
        fi
    done

    SSH_PUB_KEY=$(get_input "SSH Public Key" "Paste SSH public key for root login (or press Enter to skip):" "")
    SET_ROOT_SSH_KEY="$SSH_PUB_KEY"

    # Confirm settings
    local summary="Configuration Summary:\n\n"
    summary+="Template: $SELECTED_TEMPLATE_NAME\n"
    summary+="Container ID: $CONTAINER_ID\n"
    summary+="Hostname: $HOSTNAME\n"
    summary+="Memory: ${MEMORY}MB\n"
    summary+="Storage: $STORAGE:${ROOTFS_SIZE}GB\n"
    summary+="Network: $NET_CONFIG\n"
    summary+="Web Server: $WEB_SERVER\n"
    summary+="PHP Version: $PHP_VERSION\n"
    summary+="Redis: $INSTALL_REDIS\n"
    summary+="Composer: $INSTALL_COMPOSER\n"
    summary+="MySQL Server: $INSTALL_MYSQL\n"
    summary+="SSL Ready: $SETUP_SSL\n"
    summary+="SSH Access: $ENABLE_SSH\n"
    summary+="Root Password: $SET_ROOT_PASSWORD\n"
    summary+="Timezone: $TIMEZONE\n"
    summary+="Profile: Production (optimized)"

    show_message "Configuration Summary" "$summary"

    if ! get_yes_no "Proceed" "Proceed with container creation?"; then
        show_message "Cancelled" "Container creation cancelled by user."
        exit 1
    fi

    # Create container
    create_container

    # Set root password and enable login, add SSH Key if needed
    if [ "$SET_ROOT_PASSWORD" = "yes" ]; then
        echo "$ROOT_PASSWORD" | pct exec $CONTAINER_ID -- bash -c "passwd --stdin root 2>/dev/null || (echo 'root:$ROOT_PASSWORD' | chpasswd)"
    fi

    if [ -n "$SET_ROOT_SSH_KEY" ]; then
        pct exec $CONTAINER_ID -- bash -c "
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
            sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            mkdir -p /root/.ssh
            chmod 700 /root/.ssh
        "
        echo "$SET_ROOT_SSH_KEY" > /tmp/authorized_keys
        pct push $CONTAINER_ID /tmp/authorized_keys /root/.ssh/authorized_keys
        pct exec $CONTAINER_ID -- bash -c "chmod 600 /root/.ssh/authorized_keys"
        rm -f /tmp/authorized_keys
        print_color $GREEN "✅ SSH public key added to root"
    fi

    if [ "$SET_ROOT_PASSWORD" = "yes" ] || [ -n "$SET_ROOT_SSH_KEY" ]; then
        pct exec $CONTAINER_ID -- bash -c "systemctl restart ssh || systemctl restart sshd"
    fi
    
    # Configure container
    configure_container

    # Configure SSH access if enabled
    if [ "$ENABLE_SSH" = "yes" ]; then
        print_color $YELLOW "🔧 Configuring SSH access..."
        pct exec $CONTAINER_ID -- bash -c "
            # Install SSH server if not already installed
            if ! command -v sshd >/dev/null 2>&1; then
                apt-get install -y openssh-server
            fi
            
            # Enable and start SSH service
            systemctl enable ssh
            systemctl start ssh
            
            # Configure SSH for security
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
            sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
            sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            
            # Restart SSH to apply changes
            systemctl restart ssh
        "
        print_color $GREEN "✅ SSH access configured"
    fi
    
    # Create web content
    create_web_content

    # Final steps
    finalize_setup
} 

create_container() {
    print_color $GREEN "\n📦 Creating container with $SELECTED_TEMPLATE_NAME..."

    # Create container with progress indication
    if pct create $CONTAINER_ID $SELECTED_TEMPLATE \
        --hostname $HOSTNAME \
        --memory $MEMORY \
        --rootfs $STORAGE:$ROOTFS_SIZE \
        --net0 $NET_CONFIG \
        --unprivileged 1 \
        --onboot 1 \
        --password "$ROOT_PASSWORD"; then
        print_color $GREEN "✅ Container created successfully!"
    else
        print_color $RED "❌ Failed to create container. Please check your configuration."
        exit 1
    fi

    print_color $YELLOW "🚀 Starting container..."
    if pct start $CONTAINER_ID; then
        print_color $GREEN "✅ Container started successfully!"
    else
        print_color $RED "❌ Failed to start container."
        exit 1
    fi

    print_color $YELLOW "⏳ Waiting for container to be ready..."
    sleep 10
    
    # Verify container is running
    if pct status $CONTAINER_ID | grep -q "running"; then
        print_color $GREEN "✅ Container is running and ready!"
    else
        print_color $RED "❌ Container failed to start properly."
        exit 1
    fi
}

configure_container() {
    print_color $GREEN "\n🔧 Configuring container..."

    # Create configuration script
    cat > /tmp/container_config.sh << 'EOF'
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo '🔄 Starting container configuration...'

# Wait for container to be fully ready
sleep 5

# Set locale environment variables to C initially to avoid warnings
export LANG=C
export LC_ALL=C
export LANGUAGE=C

echo '📦 Updating package lists...'
# Fix potential package manager issues
apt-get clean
rm -rf /var/lib/apt/lists/*

# Update with retries
for i in {1..3}; do
    echo "Attempt $i of 3 to update packages..."
    if apt-get update -y; then
        echo "✅ Package update successful"
        break
    else
        echo "⚠️  Package update failed, retrying..."
        sleep 10
    fi
done

echo '🌐 Setting up locale first...'
# Install and configure locale
apt-get install -y locales
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Now switch to UTF-8 locale after it's been generated
if locale -a | grep -q en_US.UTF-8; then
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANGUAGE=en_US.UTF-8
    echo "✅ Locale setup completed successfully"
else
    echo "⚠️  UTF-8 locale not available, keeping C locale"
fi

echo '🔧 Installing basic packages...'
apt-get install -y --no-install-recommends \
    tzdata \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    nano \
    git \
    unzip \
    software-properties-common \
    gnupg \
    net-tools

echo '⏰ Setting up timezone...'
ln -fs /usr/share/zoneinfo/$TIMEZONE /etc/localtime
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive tzdata

echo '📋 Adding PHP repository...'
# Add PHP repo with error handling based on web server selection
if [ "$WEB_SERVER" = "apache2" ]; then
    echo "🌐 Adding Apache2 and PHP repositories..."
    # Add Apache2 PPA first
    if ! add-apt-repository ppa:ondrej/apache2 -y; then
        echo "⚠️  Failed to add Apache2 repository, continuing..."
    fi
    # Add PHP PPA
    if ! add-apt-repository ppa:ondrej/php -y; then
        echo "⚠️  Failed to add PHP repository, trying alternative..."
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg
        echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury-php.list
    fi
else
    echo "🌐 Adding Nginx and PHP repositories..."
    # Add Nginx PPA first
    if ! add-apt-repository ppa:ondrej/nginx -y; then
        echo "⚠️  Failed to add Nginx repository, continuing..."
    fi
    # Add PHP PPA
    if ! add-apt-repository ppa:ondrej/php -y; then
        echo "⚠️  Failed to add PHP repository, trying alternative..."
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg
        echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury-php.list
    fi
fi

echo '🔄 Updating package lists after adding repository...'
apt-get update -y

echo "Selected web server: $WEB_SERVER"

# Install web server based on selection
if [ "$WEB_SERVER" = "apache2" ]; then
    echo "🌐 Installing Apache2 and PHP module..."
    
    # Install Apache2 first
    apt-get install -y apache2
    
    # Install PHP and Apache2 module
    apt-get install -y \
        php$PHP_VERSION \
        php$PHP_VERSION-cli \
        libapache2-mod-php$PHP_VERSION \
        php$PHP_VERSION-mysql \
        php$PHP_VERSION-curl \
        php$PHP_VERSION-gd \
        php$PHP_VERSION-zip \
        php$PHP_VERSION-mbstring \
        php$PHP_VERSION-xml \
        php$PHP_VERSION-imagick \
        php$PHP_VERSION-intl \
        php$PHP_VERSION-opcache \
        php$PHP_VERSION-readline
    
    # Enable required Apache modules
    a2enmod rewrite
    a2enmod php$PHP_VERSION
    a2enmod ssl
    a2enmod headers
    
    echo "✅ Apache2 installation completed"
    
    # Make sure nginx is not installed or running
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    
else
    echo "🌐 Installing Nginx and PHP-FPM..."
    
    # Stop any existing web server that might be using port 80
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
    
    # Install Nginx and PHP-FPM
    apt-get install -y nginx-light
    
    # Install PHP-FPM and packages
    apt-get install -y \
        php$PHP_VERSION-fpm \
        php$PHP_VERSION-cli \
        php$PHP_VERSION-mysql \
        php$PHP_VERSION-curl \
        php$PHP_VERSION-gd \
        php$PHP_VERSION-zip \
        php$PHP_VERSION-mbstring \
        php$PHP_VERSION-xml \
        php$PHP_VERSION-imagick \
        php$PHP_VERSION-intl \
        php$PHP_VERSION-opcache \
        php$PHP_VERSION-readline

    echo "✅ Nginx installation completed"
fi

# MariaDB (optional)
if [ "$INSTALL_MYSQL" = "yes" ]; then
    echo "🗄️  Installing MariaDB..."
    apt-get install -y mariadb-server mariadb-client
    systemctl enable mariadb
    systemctl start mariadb
fi

# Redis (optional)
if [ "$INSTALL_REDIS" = "yes" ]; then
    echo "🔴 Installing Redis..."
    apt-get install -y redis-server
    if [ "$WEB_SERVER" != "apache2" ]; then
        apt-get install -y php$PHP_VERSION-redis
    fi
    systemctl enable redis-server
    systemctl start redis-server
fi

# Composer (optional)
if [ "$INSTALL_COMPOSER" = "yes" ]; then
    echo "🎼 Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

# SSL Tools (optional)
if [ "$SETUP_SSL" = "yes" ]; then
    echo "🔒 Installing SSL tools..."
    apt-get install -y certbot
    if [ "$WEB_SERVER" = "apache2" ]; then
        apt-get install -y python3-certbot-apache
    else
        apt-get install -y python3-certbot-nginx
    fi
fi

echo '🐘 Configuring PHP...'
# Configure PHP settings
if [ "$WEB_SERVER" = "apache2" ]; then
    PHP_INI_PATH="/etc/php/$PHP_VERSION/apache2/php.ini"
else
    PHP_INI_PATH="/etc/php/$PHP_VERSION/fpm/php.ini"
fi

if [ -f "$PHP_INI_PATH" ]; then
    sed -i "s|;cgi.fix_pathinfo=1|cgi.fix_pathinfo=0|" $PHP_INI_PATH
    sed -i "s|memory_limit = .*|memory_limit = 256M|" $PHP_INI_PATH
    sed -i "s|upload_max_filesize = .*|upload_max_filesize = 64M|" $PHP_INI_PATH
    sed -i "s|post_max_size = .*|post_max_size = 64M|" $PHP_INI_PATH
    sed -i "s|max_execution_time = .*|max_execution_time = 300|" $PHP_INI_PATH
fi

# Production PHP optimizations
if [ "$WEB_SERVER" = "apache2" ]; then
    cat > /etc/php/$PHP_VERSION/apache2/conf.d/99-phprunner.ini << 'PHPEOF'
; PHPRunner Production optimizations
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 300
memory_limit = 256M
max_input_vars = 3000
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

; OPCache optimizations
opcache.enable = 1
opcache.memory_consumption = 64
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 4000
PHPEOF
else
    cat > /etc/php/$PHP_VERSION/fpm/conf.d/99-phprunner.ini << 'PHPEOF'
; PHPRunner Production optimizations
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 300
memory_limit = 256M
max_input_vars = 3000
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

; OPCache optimizations
opcache.enable = 1
opcache.memory_consumption = 64
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 4000

; FPM specific settings
pm.status_path = /status
ping.path = /ping
PHPEOF
fi

echo '🌐 Configuring web server...'
# Configure web server
if [ "$WEB_SERVER" = "apache2" ]; then
    # Configure Apache2 virtual host
    cat > /etc/apache2/sites-available/000-default.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    LogLevel warn
    
    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        Header always set X-Content-Type-Options nosniff
        Header always set X-Frame-Options DENY
        Header always set X-XSS-Protection "1; mode=block"
        
        DirectoryIndex index.php index.html index.htm
    </Directory>
    
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
    
    <DirectoryMatch "/(config|logs|cache|temp|vendor)/">
        Require all denied
    </DirectoryMatch>
    
    <Files ".htaccess">
        Require all denied
    </Files>
    
    <Directory /var/www/html/.well-known>
        Require all granted
    </Directory>
</VirtualHost>
APACHEEOF

    a2ensite 000-default
    systemctl enable apache2
    echo "🔄 Starting Apache2..."
    systemctl start apache2

else
    # Configure Nginx site
    cat > /etc/nginx/sites-available/default << NGINXEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.php index.html index.htm;
    server_name _;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
    
    client_max_body_size 50M;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
        fastcgi_param REQUEST_URI \$request_uri;
        fastcgi_param DOCUMENT_URI \$document_uri;
        fastcgi_param DOCUMENT_ROOT \$document_root;
        fastcgi_param SERVER_PROTOCOL \$server_protocol;
        fastcgi_param REQUEST_SCHEME \$scheme;
        fastcgi_param HTTPS \$https if_not_empty;
        fastcgi_param GATEWAY_INTERFACE CGI/1.1;
        fastcgi_param SERVER_SOFTWARE nginx/\$nginx_version;
        fastcgi_param REMOTE_ADDR \$remote_addr;
        fastcgi_param REMOTE_PORT \$remote_port;
        fastcgi_param SERVER_ADDR \$server_addr;
        fastcgi_param SERVER_PORT \$server_port;
        fastcgi_param SERVER_NAME \$server_name;
        fastcgi_param QUERY_STRING \$query_string;
        fastcgi_param REQUEST_METHOD \$request_method;
        fastcgi_param CONTENT_TYPE \$content_type;
        fastcgi_param CONTENT_LENGTH \$content_length;
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 60s;
        fastcgi_read_timeout 60s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_intercept_errors on;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
    
    location ~ ^/(status|ping)\$ {
        access_log off;
        allow 127.0.0.1;
        allow ::1;
        deny all;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~* (composer\.json|composer\.lock|\.env|\.git|\.htaccess|\.htpasswd|web\.config|phpunit\.xml|artisan|env\.example)\$ {
        deny all;
        access_log off;
        log_not_found off;
    }

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location ~* /uploads/.*\.php\$ {
        deny all;
    }

    location ~* /(config|logs|cache|temp|vendor)/ {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|zip|woff|woff2|ttf|eot|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
NGINXEOF

    systemctl enable php$PHP_VERSION-fpm
    systemctl enable nginx
    echo "🔄 Starting PHP-FPM..."
    systemctl start php$PHP_VERSION-fpm
    if ! systemctl is-active php$PHP_VERSION-fpm; then
        echo "❌ PHP-FPM is not running! Check PHP-FPM installation."
        exit 1
    fi
    echo "🔄 Starting Nginx..."
    # Check if port 80 is in use and handle gracefully
    if netstat -tlnp 2>/dev/null | grep -q ':80 '; then
        echo "⚠️  Port 80 is in use, stopping conflicting service..."
        systemctl stop apache2 2>/dev/null || true
        sleep 2
    fi
    systemctl start nginx
fi

echo "✅ Container configuration completed successfully!"

EOF

    # Transfer variables and run configuration
    pct push $CONTAINER_ID /tmp/container_config.sh /tmp/config.sh
    pct exec $CONTAINER_ID -- chmod +x /tmp/config.sh
    pct exec $CONTAINER_ID -- bash -c \
        "export PHP_VERSION='$PHP_VERSION'; \
         export WEB_SERVER='$WEB_SERVER'; \
         export INSTALL_MYSQL='$INSTALL_MYSQL'; \
         export INSTALL_REDIS='$INSTALL_REDIS'; \
         export INSTALL_COMPOSER='$INSTALL_COMPOSER'; \
         export SETUP_SSL='$SETUP_SSL'; \
         export TIMEZONE='$TIMEZONE'; \
         /tmp/config.sh"

    print_color $GREEN "✅ Container configuration complete!"

    if [ "$SETUP_SSL" = "yes" ]; then
        create_ssl_script
    fi
}

# Function to create SSL script
create_ssl_script() {
    print_color $YELLOW "🔒 Creating SSL setup script..."

    pct exec $CONTAINER_ID -- bash -c "
        mkdir -p /etc/nginx/ssl
        mkdir -p /var/www/html/.well-known/acme-challenge

        cat > /root/setup-ssl.sh << 'EOL'
#!/bin/bash
if [ -z \"\\\$1\" ]; then
    echo \"Usage: ./setup-ssl.sh your-domain.com\"
    exit 1
fi

DOMAIN=\\\$1
EMAIL=\"$SSL_EMAIL\"

echo \"Setting up SSL for domain: \\\$DOMAIN\"

if systemctl is-active apache2 >/dev/null 2>&1; then
    sed -i \"s/ServerName .*/ServerName \\\$DOMAIN/\" /etc/apache2/sites-available/000-default.conf
    certbot --apache -d \\\$DOMAIN --non-interactive --agree-tos --email \\\$EMAIL
elif systemctl is-active nginx >/dev/null 2>&1; then
    sed -i \"s/server_name _;/server_name \\\$DOMAIN;/\" /etc/nginx/sites-available/default
    certbot --nginx -d \\\$DOMAIN --non-interactive --agree-tos --email \\\$EMAIL
else
    echo \"Error: No supported web server found\"
    exit 1
fi

systemctl enable certbot.timer
echo \"SSL setup complete for \\\$DOMAIN\"
EOL

        chmod +x /root/setup-ssl.sh
    "
}

# Function to create web content
create_web_content() {
    print_color $YELLOW "🌐 Creating web content..."

    # Create web content directly inside the container
    WEB_SERVER_DISPLAY="$WEB_SERVER"
    if [ "$WEB_SERVER_DISPLAY" = "apache2" ]; then
        WEB_SERVER_DISPLAY="Apache2"
    elif [ "$WEB_SERVER_DISPLAY" = "nginx" ]; then
        WEB_SERVER_DISPLAY="Nginx"
    fi

    pct exec $CONTAINER_ID -- bash -c "
        # Clean up any existing web content
        rm -rf /var/www/html/*
        
        # Create index.html
        cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>PHPRunner Container Ready</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .status { padding: 10px; margin: 10px 0; border-radius: 4px; background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        ul { list-style: none; padding: 0; }
        li { margin: 10px 0; }
    </style>
</head>
<body>
    <div class=\"container\">
        <h1>PHPRunner Container Ready</h1>
        <div class=\"status\">Container successfully configured</div>
        
        <h2>Test Links</h2>
        <ul>
            <li><a href=\"info.php\">PHP Information</a></li>
            <li><a href=\"test.php\">PHP Test Page</a></li>
            <li><a href=\"health.php\">System Health Check</a></li>
            <li><a href=\"debug.php\">Debug Information</a></li>
        </ul>
        
        <h2>Installed Components</h2>
        <ul>
            <li>PHP (with web server module/FPM)</li>
            <li>Web Server ($WEB_SERVER_DISPLAY)</li>
            <li>MariaDB Client</li>
        </ul>
    </div>
</body>
</html>
HTMLEOF

        # Create test.php
        cat > /var/www/html/test.php << 'PHPEOF'
<?php
echo '<h2>PHP Test</h2>';
echo '<p><strong>PHP Version:</strong> ' . PHP_VERSION . '</p>';
echo '<p><strong>Server Time:</strong> ' . date('Y-m-d H:i:s T') . '</p>';
echo '<p><strong>Timezone:</strong> ' . date_default_timezone_get() . '</p>';
echo '<p><strong>Memory Limit:</strong> ' . ini_get('memory_limit') . '</p>';
echo '<p><strong>Upload Max:</strong> ' . ini_get('upload_max_filesize') . '</p>';
echo '<p><strong>MySQL Extension:</strong> ' . (extension_loaded('mysqli') ? 'Available' : 'Not Available') . '</p>';
if (extension_loaded('redis')) {
    echo '<p><strong>Redis Extension:</strong> Available</p>';
}
echo '<hr>';
echo '<p><strong>Ready for PHPRunner applications!</strong></p>';
?>
PHPEOF

        # Create health.php
        cat > /var/www/html/health.php << 'PHPEOF'
<?php
header('Content-Type: application/json');
echo json_encode([
    'status' => 'ok',
    'timestamp' => date('c'),
    'php_version' => PHP_VERSION
], JSON_PRETTY_PRINT);
?>
PHPEOF

        # Create info.php
        cat > /var/www/html/info.php << 'PHPEOF'
<?php phpinfo(); ?>
PHPEOF

        # Create debug.php
        cat > /var/www/html/debug.php << 'PHPEOF'
<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

echo \"<h1>PHP Debug Test</h1>\";
echo \"<p>PHP Version: \" . PHP_VERSION . \"</p>\";
echo \"<p>Server Time: \" . date('Y-m-d H:i:s') . \"</p>\";
echo \"<p>Document Root: \" . \$_SERVER['DOCUMENT_ROOT'] . \"</p>\";
echo \"<p>Script Name: \" . \$_SERVER['SCRIPT_NAME'] . \"</p>\";

\$test_var = \"Hello from PHP!\";
echo \"<p>Test Variable: \" . \$test_var . \"</p>\";

echo \"<h2>PHP Extensions</h2>\";
echo \"<p>MySQL: \" . (extension_loaded('mysqli') ? 'Available' : 'Not Available') . \"</p>\";
echo \"<p>cURL: \" . (extension_loaded('curl') ? 'Available' : 'Not Available') . \"</p>\";

if (php_sapi_name() !== 'cli') {
    echo \"<p>SAPI: \" . php_sapi_name() . \"</p>\";
    echo \"<p>Web Server: \" . \$_SERVER['SERVER_SOFTWARE'] . \"</p>\";
}

echo \"<p style='color: green; font-weight: bold;'>PHP is working correctly!</p>\";
?>
PHPEOF

        # Set proper permissions
        chown -R www-data:www-data /var/www/html
        chmod -R 644 /var/www/html/*
        chmod 755 /var/www/html
        
        echo 'Web content created successfully!'
    "

    if [ "$WEB_SERVER" = "apache2" ]; then
        pct exec $CONTAINER_ID -- bash -c '
cat > /var/www/html/.htaccess << "HTACCESS"
# --- PHPRunner Default Security .htaccess ---
# Disable directory listing
Options -Indexes

# Deny access to hidden files and directories (starting with .)
<FilesMatch "^\.">
    Require all denied
</FilesMatch>

# Protect sensitive files
<FilesMatch "(composer\.json|composer\.lock|\.env|\.git|\.htaccess|\.htpasswd|web\.config|phpunit\.xml|artisan|env\.example)$">
    Require all denied
</FilesMatch>

# Set security headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "no-referrer-when-downgrade"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains" env=HTTPS
</IfModule>

# Prevent script execution in uploads (if uploads dir exists)
<IfModule mod_php7.c>
    <Directory "/var/www/html/uploads">
        php_flag engine off
    </Directory>
</IfModule>
<IfModule mod_php8.c>
    <Directory "/var/www/html/uploads">
        php_flag engine off
    </Directory>
</IfModule>

# Disable .htaccess override for certain folders
<DirectoryMatch "/(config|logs|cache|temp|vendor)/">
    AllowOverride None
</DirectoryMatch>
HTACCESS
'
    fi
}

finalize_setup() {
    print_color $GREEN "\n🎉 Finalizing setup..."

    # Get container IP
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 2>/dev/null || echo "DHCP")

    # Final verification
    print_color $YELLOW "🔍 Running verification checks..."
    
    pct exec $CONTAINER_ID -- bash -c "
        echo '=== Service Status Check ==='
        if [ '$WEB_SERVER' = 'apache2' ]; then
            echo -n 'Apache2: '; systemctl is-active apache2 || echo 'FAILED'
        else
            echo -n 'Nginx: '; systemctl is-active nginx || echo 'FAILED'
            echo -n 'PHP-FPM: '; systemctl is-active php$PHP_VERSION-fpm || echo 'FAILED'
        fi
        
        echo
        echo '=== Web Server Test ==='
        if timeout 10 curl -s localhost >/dev/null 2>&1; then
            echo 'HTTP connection: OK'
        else
            echo 'HTTP connection: FAILED'
        fi
        
        echo
        echo '=== PHP Processing Test ==='
        if curl -s localhost/debug.php | grep -q 'PHP is working correctly' 2>/dev/null; then
            echo '✅ PHP processing: SUCCESS'
        else
            echo '❌ PHP processing: FAILED'
        fi
    "

    print_color $GREEN "\n✅ Container setup complete!"
    print_color $CYAN "\n📋 Container Details:"
    echo "  Template: $SELECTED_TEMPLATE_NAME"
    echo "  OS Type: Ubuntu LTS"
    echo "  ID: $CONTAINER_ID"
    echo "  Hostname: $HOSTNAME"
    echo "  IP Address: $CONTAINER_IP"
    echo "  Web Server: $WEB_SERVER"
    echo "  PHP Version: $PHP_VERSION"
    echo "  Root Password: $SET_ROOT_PASSWORD"
    
    if [ "$CONTAINER_IP" != "DHCP" ]; then
        echo "  Web Access: http://$CONTAINER_IP/"
        echo "  Test Page: http://$CONTAINER_IP/test.php"
    fi

    print_color $YELLOW "\n📝 Next Steps:"
    echo "1. Test the web server: Browse to the container IP"
    echo "2. Deploy your PHPRunner application to /var/www/html/"
    if [ "$SETUP_SSL" = "yes" ]; then
        echo "3. Setup SSL: pct exec $CONTAINER_ID -- /root/setup-ssl.sh your-domain.com"
    fi

    print_color $GREEN "\n🎉 Container setup completed successfully!"
}

# Run main function
main "$@" 