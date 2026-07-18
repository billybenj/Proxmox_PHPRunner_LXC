#!/bin/bash

# Interactive PHPRunner Container Creator
# Creates ready-to-use containers for PHPRunner applications
# Optimized for Ubuntu LTS systems only
#
# GitHub: https://github.com/billybenj/Proxmox_PHPRunner_LXC
# License: MIT
# Author: Billy Benjamin
# Version: 1.0.0

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

# Function to prompt for yes/no
prompt_yn() {
    local prompt=$1
    local default=${2:-"y"}
    while true; do
        if [ "$default" = "y" ]; then
            read -p "$prompt [Y/n]: " yn
            yn=${yn:-y}
        else
            read -p "$prompt [y/N]: " yn
            yn=${yn:-n}
        fi
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to prompt for input with default
prompt_input() {
    local prompt=$1
    local default=$2
    local variable_name=$3
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        input=${input:-$default}
    else
        read -p "$prompt: " input
    fi
    
    eval "$variable_name='$input'"
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
        if [ "$container_exists" = true ]; then
            print_color $RED "❌ Container ID $id already exists!"
        fi
        if [ "$vm_exists" = true ]; then
            print_color $RED "❌ VM ID $id already exists!"
        fi
        echo
        print_color $YELLOW "Please choose a different ID."
        echo
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
    local counter=1
    
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
            local display_name="🟠 Ubuntu $version LTS (downloadable)"
            
            templates+=("$display_name")
            template_paths+=("download:$template_name")
            
            debug_log "Added downloadable template: $display_name -> download:$template_name"
            echo "  $counter) $display_name"
            ((counter++))
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
                        local display_name="🟠 Ubuntu $version LTS (installed)"
                        
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
                        found_local=true
                        
                        debug_log "Added local template: $display_name -> $full_path"
                        echo "  $counter) $display_name"
                        ((counter++))
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
        
        if prompt_yn "Would you like to download Ubuntu 24.04 LTS template now?"; then
            download_ubuntu_lts_template
            # Restart template detection after download
            list_ubuntu_lts_templates
            return
        else
            print_color $RED "Cannot proceed without an Ubuntu LTS template."
            print_color $YELLOW "To manually download templates:"
            echo "  pveam update"
            echo "  pveam download local ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
            echo "  pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
            exit 1
        fi
    fi
    
    echo
    prompt_input "Select template number (1-$((counter-1)))" "1" TEMPLATE_CHOICE
    
    # Validate choice
    if [[ ! "$TEMPLATE_CHOICE" =~ ^[0-9]+$ ]] || [ "$TEMPLATE_CHOICE" -lt 1 ] || [ "$TEMPLATE_CHOICE" -gt $((counter-1)) ]; then
        print_color $RED "Invalid selection. Please choose a number between 1 and $((counter-1))."
        list_ubuntu_lts_templates
        return
    fi
    
    # Set selected template
    local selected_path="${template_paths[$((TEMPLATE_CHOICE-1))]}"
    SELECTED_TEMPLATE_NAME="${templates[$((TEMPLATE_CHOICE-1))]}"
    
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
                print_color $RED "❌ Failed to download template. Please check your internet connection."
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
        print_color $RED "❌ No storage found that supports templates (vztmpl content type)!"
        print_color $YELLOW "Please configure storage for templates in Proxmox web UI"
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
        print_color $RED "❌ Failed to download template. Please check your internet connection."
        exit 1
    fi
}

# Function to list bridges / SDN VNets available on this host and pick one
select_bridge() {
    print_color $CYAN "📋 Scanning for available bridges and SDN VNets..."

    local bridges=()
    local descs=()

    # Real bridges on the host. SDN VNets show up here too, because Proxmox
    # materialises each VNet as a bridge once the SDN config is applied.
    while IFS= read -r br; do
        [ -z "$br" ] && continue
        bridges+=("$br")
        descs+=("")
    done < <(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | sort -u)

    # Annotate anything that is an SDN VNet, and show the VLAN tag it applies.
    if [ -f /etc/pve/sdn/vnets.cfg ]; then
        local vnet=""
        while IFS= read -r line; do
            if [[ $line =~ ^vnet:[[:space:]]*([^[:space:]]+) ]]; then
                vnet="${BASH_REMATCH[1]}"
                for i in "${!bridges[@]}"; do
                    [ "${bridges[i]}" = "$vnet" ] && descs[i]="SDN VNet"
                done
            elif [[ $line =~ ^[[:space:]]+tag[[:space:]]+([0-9]+) ]] && [ -n "$vnet" ]; then
                for i in "${!bridges[@]}"; do
                    [ "${bridges[i]}" = "$vnet" ] && descs[i]="SDN VNet, VLAN tag ${BASH_REMATCH[1]}"
                done
                vnet=""
            fi
        done < /etc/pve/sdn/vnets.cfg
    fi

    if [ ${#bridges[@]} -eq 0 ]; then
        print_color $RED "❌ No bridges detected on this host!"
        prompt_input "Enter bridge name manually" "" BRIDGE
        if [ -z "$BRIDGE" ]; then
            print_color $RED "A bridge is required. Exiting."
            exit 1
        fi
        return
    fi

    echo
    print_color $CYAN "Available bridges:"
    for i in "${!bridges[@]}"; do
        if [ -n "${descs[i]}" ]; then
            echo "  $((i+1))) ${bridges[i]}  (${descs[i]})"
        else
            echo "  $((i+1))) ${bridges[i]}"
        fi
    done
    echo

    while true; do
        prompt_input "Select bridge number (1-${#bridges[@]})" "" BRIDGE_CHOICE
        if [[ "$BRIDGE_CHOICE" =~ ^[0-9]+$ ]] && [ "$BRIDGE_CHOICE" -ge 1 ] && [ "$BRIDGE_CHOICE" -le ${#bridges[@]} ]; then
            BRIDGE="${bridges[$((BRIDGE_CHOICE-1))]}"
            break
        fi
        print_color $RED "Invalid selection. Please choose 1-${#bridges[@]}."
    done

    print_color $GREEN "✅ Selected bridge: $BRIDGE"
}

# Main setup function
main() {
    print_color $BLUE "==================================================="
    print_color $BLUE "   Interactive PHPRunner LXC Creator"
    print_color $BLUE "            Ubuntu LTS Only"
    print_color $BLUE "==================================================="
    print_color $CYAN "   GitHub: https://github.com/billybenj/Proxmox_PHPRunner_LXC"
    print_color $CYAN "   Version: 1.0.0 | License: MIT"
    print_color $BLUE "==================================================="
    echo

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
    echo

    # Container ID with existence check
    while true; do
        prompt_input "Enter container ID (100 or higher, must be unused)" "" CONTAINER_ID

        # No default on purpose: the user must consciously choose an ID so we can
        # never propose one that belongs to a live container/VM.
        if ! [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
            print_color $RED "❌ Container ID must be a number (e.g. 210)."
            echo
            continue
        fi
        if [ "$CONTAINER_ID" -lt 100 ]; then
            print_color $RED "❌ Container ID must be 100 or higher (Proxmox reserves 1-99)."
            echo
            continue
        fi
        
        if check_id_exists $CONTAINER_ID; then
            break
        else
            echo
            if ! prompt_yn "Would you like to try a different ID?"; then
                print_color $RED "Exiting..."
                exit 1
            fi
        fi
    done

    # Basic container settings
    prompt_input "Container hostname" "phprunner-template" HOSTNAME
    prompt_input "Memory (MB)" "1024" MEMORY
    prompt_input "CPU cores" "2" CORES
    
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
        for i in "${!all_storages[@]}"; do
            echo "  $((i+1))) ${all_storages[i]}"
        done
        echo
        print_color $YELLOW "💡 Choose 'Storage' or 'local-zfs' as you mentioned they support containers"
        prompt_input "Select storage number manually (1-${#all_storages[@]})" "2" MANUAL_STORAGE_CHOICE
        
        if [[ ! "$MANUAL_STORAGE_CHOICE" =~ ^[0-9]+$ ]] || [ "$MANUAL_STORAGE_CHOICE" -lt 1 ] || [ "$MANUAL_STORAGE_CHOICE" -gt ${#all_storages[@]} ]; then
            print_color $RED "Invalid selection."
            exit 1
        fi
        
        STORAGE="${all_storages[$((MANUAL_STORAGE_CHOICE-1))]}"
        print_color $YELLOW "⚠️  Using manually selected storage: $STORAGE"
        print_color $YELLOW "If container creation fails, this storage may not support containers."
    elif [ ${#container_storages[@]} -eq 1 ]; then
        STORAGE="${container_storages[0]}"
        print_color $GREEN "✅ Auto-selected storage: $STORAGE"
    else
        echo
        print_color $CYAN "Available container storage options:"
        for i in "${!container_storages[@]}"; do
            echo "  $((i+1))) ${container_storages[i]}"
        done
        echo
        prompt_input "Select storage number (1-${#container_storages[@]})" "1" STORAGE_CHOICE
        
        if [[ ! "$STORAGE_CHOICE" =~ ^[0-9]+$ ]] || [ "$STORAGE_CHOICE" -lt 1 ] || [ "$STORAGE_CHOICE" -gt ${#container_storages[@]} ]; then
            print_color $RED "Invalid selection."
            exit 1
        fi
        
        STORAGE="${container_storages[$((STORAGE_CHOICE-1))]}"
        print_color $GREEN "✅ Selected storage: $STORAGE"
    fi
    
    prompt_input "Root filesystem size (GB)" "16" ROOTFS_SIZE
    
    # Network configuration
    print_color $CYAN "\nNetwork Configuration:"
    select_bridge

    echo
    echo "1) DHCP (automatic IP)"
    echo "2) Static IP"
    prompt_input "Choose network type (1-2)" "1" NET_TYPE

    if [ "$NET_TYPE" = "2" ]; then
        prompt_input "Static IP with CIDR (e.g. 10.0.30.16/24)" "" STATIC_IP
        prompt_input "Gateway IP (e.g. 10.0.30.1)" "" GATEWAY
        NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=$STATIC_IP,gw=$GATEWAY"

        # DNS defaults to the gateway on purpose. On an isolated/DMZ VLAN the
        # container must resolve via that VLAN's own gateway - inheriting the
        # host's resolver points at another subnet, which an isolation rule will
        # block, and DNS then fails silently (apt, certbot, etc).
        prompt_input "DNS nameserver for the container" "$GATEWAY" NAMESERVER
    else
        NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=dhcp"
        prompt_input "DNS nameserver for the container (blank = inherit host)" "" NAMESERVER
    fi

    # Web server selection
    print_color $CYAN "\nWeb Server Selection:"
    echo "1) Apache2 (full .htaccess support, better PHPRunner compatibility)"
    echo "2) Nginx (lightweight, high performance)"
    prompt_input "Choose web server (1-2)" "1" WEB_SERVER_CHOICE
    
    case $WEB_SERVER_CHOICE in
        1) WEB_SERVER="apache2";;
        2) WEB_SERVER="nginx";;
        *) WEB_SERVER="apache2";;
    esac
    
    print_color $GREEN "✅ Selected web server: $WEB_SERVER"

    # PHP version selection with dynamic lookup
    print_color $CYAN "\nPHP Version Selection:"
    
    # Get available PHP versions
    local available_versions=$(get_available_php_versions)
    local version_array=($available_versions)
    
    echo "Available PHP versions:"
    for i in "${!version_array[@]}"; do
        local version="${version_array[i]}"
        local status=""
        case $version in
            "8.4") status=" (Latest)";;
            "8.3") status=" (Stable)";;
            "8.2") status=" (LTS)";;
            "8.1") status=" (Legacy)";;
        esac
        echo "  $((i+1))) PHP $version$status"
    done
    
    prompt_input "Choose PHP version (1-${#version_array[@]})" "1" PHP_CHOICE
    
    if [[ ! "$PHP_CHOICE" =~ ^[0-9]+$ ]] || [ "$PHP_CHOICE" -lt 1 ] || [ "$PHP_CHOICE" -gt ${#version_array[@]} ]; then
        print_color $RED "Invalid PHP version selection, using default 8.4"
        PHP_VERSION="8.4"
    else
        PHP_VERSION="${version_array[$((PHP_CHOICE-1))]}"
    fi
    
    print_color $GREEN "✅ Selected PHP $PHP_VERSION"

    # Additional components
    print_color $CYAN "\nAdditional Components:"
    INSTALL_REDIS=$(prompt_yn "Install Redis?" "n" && echo "yes" || echo "no")
    INSTALL_COMPOSER=$(prompt_yn "Install Composer?" "n" && echo "yes" || echo "no")
    INSTALL_MYSQL=$(prompt_yn "Install MySQL/MariaDB server (not just client)?" "n" && echo "yes" || echo "no")

    # SSL Configuration
    print_color $CYAN "\nSSL Configuration:"
    SETUP_SSL=$(prompt_yn "Prepare SSL infrastructure?" && echo "yes" || echo "no")
    
    if [ "$SETUP_SSL" = "yes" ]; then
        prompt_input "Default email for SSL certificates" "admin@example.com" SSL_EMAIL
    fi

    # Timezone
    print_color $CYAN "\nTimezone Configuration:"
    echo "Current system timezone: $(timedatectl show --property=Timezone --value)"
    prompt_input "PHP timezone" "America/Edmonton" TIMEZONE

    # Always use production settings (no prompt)
    OPTIMIZATION="2"  # Production
    
    # SSH Configuration
    print_color $CYAN "\nSSH Configuration:"
    ENABLE_SSH=$(prompt_yn "Enable SSH access to container?" "n" && echo "yes" || echo "no")

	    # Container root password setup (always required)
    print_color $CYAN "\nRoot Password Configuration:"
    while true; do
        echo
        read -s -p "Enter root password for container: " ROOT_PASSWORD
        echo
        read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
        echo

        if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
            if [ ${#ROOT_PASSWORD} -lt 6 ]; then
                print_color $RED "Password too short. Please use at least 6 characters."
                continue
            fi
            SET_ROOT_PASSWORD="yes"
            break
        else
            print_color $RED "Passwords do not match. Please try again."
        fi
    done

    echo
    read -p "Paste SSH public key for root login (or press Enter to skip): " SSH_PUB_KEY
    SET_ROOT_SSH_KEY="$SSH_PUB_KEY"

    # Confirm settings
    print_color $YELLOW "\n=== Configuration Summary ==="
    echo "Template: $SELECTED_TEMPLATE_NAME"
    echo "Container ID: $CONTAINER_ID"
    echo "Hostname: $HOSTNAME"
    echo "Memory: ${MEMORY}MB"
    echo "CPU cores: $CORES"
    echo "Storage: $STORAGE:${ROOTFS_SIZE}GB"
    echo "Bridge: $BRIDGE"
    echo "Network: $NET_CONFIG"
    echo "Nameserver: ${NAMESERVER:-<inherit host>}"
    echo "Web Server: $WEB_SERVER"
    echo "PHP Version: $PHP_VERSION"
    echo "Redis: $INSTALL_REDIS"
    echo "Composer: $INSTALL_COMPOSER"
    echo "MySQL Server: $INSTALL_MYSQL"
    echo "SSL Ready: $SETUP_SSL"
    echo "SSH Access: $ENABLE_SSH"
    echo "Root Password: $SET_ROOT_PASSWORD"
    echo "Timezone: $TIMEZONE"
    echo "Profile: Production (optimized)"
    echo

    if ! prompt_yn "Proceed with container creation?"; then
        print_color $RED "Aborted by user."
        exit 1
    fi

    # Create container
    create_container

	# Set root password and enable login, add SSH Key if needed
	if [ "$SET_ROOT_PASSWORD" = "yes" ]; then
		# Piped via stdin so the password never appears in the process list.
		printf 'root:%s\n' "$ROOT_PASSWORD" | pct exec $CONTAINER_ID -- chpasswd
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
        --cores $CORES \
        --rootfs $STORAGE:$ROOTFS_SIZE \
        --net0 $NET_CONFIG \
        ${NAMESERVER:+--nameserver "$NAMESERVER"} \
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

echo '📋 Adding repositories...'

# Web server PPA. Optional - if it is unavailable the Ubuntu archive version
# is perfectly usable, so a failure here is only a warning.
if [ "$WEB_SERVER" = "apache2" ]; then
    echo "🌐 Adding Apache2 repository..."
    if ! add-apt-repository ppa:ondrej/apache2 -y; then
        echo "⚠️  Could not add ppa:ondrej/apache2 - using the Ubuntu archive version instead."
    fi
else
    echo "🌐 Adding Nginx repository..."
    if ! add-apt-repository ppa:ondrej/nginx -y; then
        echo "⚠️  Could not add ppa:ondrej/nginx - using the Ubuntu archive version instead."
    fi
fi

# PHP comes from ppa:ondrej/php.
#
# There is deliberately NO packages.sury.org fallback here. Sury is a DEBIAN
# archive, so on Ubuntu "deb https://packages.sury.org/php/ $(lsb_release -sc)"
# resolves to an Ubuntu codename that does not exist in that archive. It writes
# an apt source that 404s, which converts a clear "the PPA is unavailable"
# failure into a confusing one several steps later.
#
# If the PPA is unavailable we check whether the requested PHP version happens
# to be in the Ubuntu archive, and otherwise stop with an actionable message.
echo "🐘 Adding PHP repository..."
if ! add-apt-repository ppa:ondrej/php -y; then
    echo "⚠️  Could not add ppa:ondrej/php."
    echo "    This normally means the PPA does not build for this Ubuntu release yet."
    apt-get update -y || true

    if apt-cache show "php$PHP_VERSION-cli" >/dev/null 2>&1; then
        echo "✅ PHP $PHP_VERSION is available from the Ubuntu archive - continuing without the PPA."
    else
        echo "❌ PHP $PHP_VERSION is not in the Ubuntu archive either, so this build cannot continue."
        echo
        echo "   Options:"
        echo "     - Rebuild on an Ubuntu LTS that the PPA supports (24.04 is a safe choice)"
        echo "     - Or select the PHP version this Ubuntu release ships by default"
        echo
        echo "   Supported releases: https://launchpad.net/~ondrej/+archive/ubuntu/php"
        exit 1
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
    
    # Ensure PHP-FPM pool is properly configured
    echo "🔧 Configuring PHP-FPM pool..."
    cat > /etc/php/$PHP_VERSION/fpm/pool.d/www.conf << 'POOLEOF'
[www]
user = www-data
group = www-data
listen = /run/php/php$PHP_VERSION-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
clear_env = no
security.limit_extensions = .php
env[HOSTNAME] = $HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
POOLEOF
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

    # date.timezone must be set explicitly. PHP falls back to UTC when it is
    # unset, regardless of the system timezone, so setting /etc/localtime alone
    # is not enough. Appended rather than written inside the heredoc above
    # because that heredoc is quoted and would not expand $TIMEZONE.
    echo "date.timezone = $TIMEZONE" >> /etc/php/$PHP_VERSION/apache2/conf.d/99-phprunner.ini
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

    # See the note above: date.timezone must be set explicitly or PHP uses UTC.
    echo "date.timezone = $TIMEZONE" >> /etc/php/$PHP_VERSION/fpm/conf.d/99-phprunner.ini
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
    # restart, not start: the package postinst already started Apache before the
    # PHP ini above was written, and 'start' on a running unit is a no-op, so the
    # new PHP settings would never be loaded by mod_php.
    echo "🔄 Restarting Apache2 to apply configuration..."
    systemctl restart apache2

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
        add_header Cache-Control 'public, immutable';
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
    # restart, not start: PHP-FPM was already started by its package postinst
    # before the PHP ini above was written, and 'start' on a running unit is a
    # no-op, so the new settings would never be loaded.
    echo "🔄 Restarting PHP-FPM to apply configuration..."
    systemctl restart php$PHP_VERSION-fpm
    if ! systemctl is-active php$PHP_VERSION-fpm; then
        echo "❌ PHP-FPM is not running! Check PHP-FPM installation."
        exit 1
    fi
    
    # Verify PHP-FPM socket exists
    echo "🔍 Checking PHP-FPM socket..."
    if [ ! -S "/run/php/php$PHP_VERSION-fpm.sock" ]; then
        echo "❌ PHP-FPM socket not found! Creating default pool..."
        # Create default pool if it doesn't exist
        cat > /etc/php/$PHP_VERSION/fpm/pool.d/www.conf << 'POOLEOF'
[www]
user = www-data
group = www-data
listen = /run/php/php$PHP_VERSION-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
POOLEOF
        systemctl restart php$PHP_VERSION-fpm
        sleep 3
    fi
    
    # Test PHP-FPM socket
    if [ -S "/run/php/php$PHP_VERSION-fpm.sock" ]; then
        echo "✅ PHP-FPM socket found and working"
    else
        echo "❌ PHP-FPM socket still not available"
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
    
    # Test PHP processing
    echo "🧪 Testing PHP processing..."
    if curl -s http://localhost/test.php >/dev/null 2>&1; then
        echo "✅ PHP processing test passed"
    else
        echo "⚠️  PHP processing test failed - checking configuration"
        # Check Nginx error logs
        echo "Nginx error log:"
        tail -5 /var/log/nginx/error.log 2>/dev/null || echo "No error log found"
        # Check PHP-FPM status
        echo "PHP-FPM status:"
        systemctl status php$PHP_VERSION-fpm --no-pager -l
    fi
fi

echo "✅ Container configuration completed successfully!"

EOF

    # Transfer variables and run configuration
    pct push $CONTAINER_ID /tmp/container_config.sh /tmp/config.sh
    pct exec $CONTAINER_ID -- chmod +x /tmp/config.sh
    if ! pct exec $CONTAINER_ID -- bash -c \
        "export PHP_VERSION='$PHP_VERSION'; \
         export WEB_SERVER='$WEB_SERVER'; \
         export INSTALL_MYSQL='$INSTALL_MYSQL'; \
         export INSTALL_REDIS='$INSTALL_REDIS'; \
         export INSTALL_COMPOSER='$INSTALL_COMPOSER'; \
         export SETUP_SSL='$SETUP_SSL'; \
         export TIMEZONE='$TIMEZONE'; \
         /tmp/config.sh"; then
        print_color $RED "\n❌ Container configuration failed - see the output above for the cause."
        print_color $YELLOW "Container $CONTAINER_ID has been left in place so you can inspect it:"
        echo "  pct enter $CONTAINER_ID"
        echo "  pct destroy $CONTAINER_ID   # once you are done with it"
        exit 1
    fi

    print_color $GREEN "✅ Container configuration complete!"

    if [ "$SETUP_SSL" = "yes" ]; then
        create_ssl_script
    fi
}

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
            <li><a href=\"test.php\">PHP Test Page</a></li>
            <li><a href=\"health.php\">System Health Check</a></li>
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

        # NOTE: info.php (phpinfo) is deliberately NOT created. It leaks the full
        # server configuration - paths, extensions, environment - and nothing in
        # this script uses it. Run 'php -i' on the container if you need it.

        # Create debug.php - used by the PHP processing self-test in
        # finalize_setup(), then deleted there so it is not left web-accessible.
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

        # Create a simple PHP test file to verify processing
        cat > /var/www/html/php-test.php << 'PHPEOF'
<?php
echo \"<h1>PHP Processing Test</h1>\";
echo \"<p>If you can see this, PHP is working correctly with Nginx!</p>\";
echo \"<p>PHP Version: \" . PHP_VERSION . \"</p>\";
echo \"<p>Current Time: \" . date('Y-m-d H:i:s') . \"</p>\";
echo \"<p>Server: \" . \$_SERVER['SERVER_SOFTWARE'] . \"</p>\";
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

# NOTE: <Directory>, <DirectoryMatch> and AllowOverride are server/vhost-only
# directives. Apache aborts every request with a 500 ("<X> not allowed here")
# if it finds them in a .htaccess, so they must never be added here.
#
# Those protections already live in the vhost, which denies /config, /logs,
# /cache, /temp and /vendor as well as dotfiles and .htaccess itself.
#
# To stop PHP executing inside an uploads directory, put a .htaccess *in that
# directory* containing:
#     <FilesMatch "\.php$">
#         Require all denied
#     </FilesMatch>
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

        # Remove the diagnostic pages now the self-test has run. They expose
        # server internals and are of no use once the container is serving.
        rm -f /var/www/html/debug.php /var/www/html/php-test.php /var/www/html/info.php
        echo 'Removed diagnostic pages (debug.php, php-test.php)'
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