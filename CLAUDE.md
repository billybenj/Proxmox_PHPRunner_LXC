# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a bash script suite for automating the creation of LXC containers optimized for PHPRunner applications on Proxmox VE. The project creates production-ready Ubuntu LTS containers with pre-configured web servers (Apache2 or Nginx), PHP, and optional components like MariaDB, Redis, and Composer.

## Key Scripts

### `lxc_setup.sh` (Main Script)
The primary interactive script with terminal-based prompts. This is the recommended script for most users.

**Usage:**
```bash
./lxc_setup.sh                    # Normal mode
DEBUG=1 ./lxc_setup.sh           # Debug mode with verbose output
```

### `lxc_setup_whiptail.sh` (Alternative UI)
Alternative version with whiptail-based GUI for terminal. Functionally identical to `lxc_setup.sh` but uses dialog boxes instead of simple prompts.

**Requirements:**
```bash
apt-get install whiptail
```

## Script Architecture

### Main Workflow
1. **Template Selection** - Detects and downloads Ubuntu LTS templates (only even-numbered releases: 20.04, 22.04, 24.04)
2. **Container Creation** - Creates unprivileged LXC container with specified resources
3. **Container Configuration** - Installs and configures packages inside the container
4. **Web Server Setup** - Configures Apache2 or Nginx with PHP
5. **Optional Components** - Installs Redis, Composer, MariaDB, SSL tools
6. **Web Content Creation** - Creates test files and security configurations
7. **Verification** - Tests web server and PHP processing

### Key Functions

- `list_ubuntu_lts_templates()` - Scans for available Ubuntu LTS templates across storage pools, handles both installed and downloadable templates
- `create_container()` - Uses `pct create` to instantiate the container with specified configuration
- `configure_container()` - Generates and executes `/tmp/container_config.sh` inside container for package installation
- `create_web_content()` - Creates test PHP files (index.html, test.php, info.php, debug.php, health.php)
- `check_id_exists()` - Validates container ID doesn't conflict with existing containers or VMs

### Configuration Script Pattern

Both scripts use a heredoc pattern to generate `/tmp/container_config.sh` which is pushed into the container and executed. This embedded script:
- Sets `DEBIAN_FRONTEND=noninteractive` to avoid prompts
- Configures locales to prevent warnings
- Adds Ondřej Surý's PHP PPA (ppa:ondrej/php) for multiple PHP versions
- Installs web server and PHP with production optimizations
- Creates configuration files for Apache2 or Nginx

## Common Tasks

### Testing Scripts
```bash
# Test with debug output
DEBUG=1 ./lxc_setup.sh

# Test with minimal settings
./lxc_setup.sh
# Accept defaults for most prompts
```

### Modifying PHP Versions
Available versions are defined in `get_available_php_versions()`:
```bash
echo "8.4 8.3 8.2 8.1 8.0 7.4"
```

To add new PHP versions, update this function in both scripts.

### Modifying Web Server Configurations

**Apache2 Virtual Host:** Lines 1036-1074 in `lxc_setup.sh`
- Default config is in heredoc to `/etc/apache2/sites-available/000-default.conf`
- Enables `.htaccess` with `AllowOverride All`
- Security headers and directory restrictions

**Nginx Configuration:** Lines 1083-1189 in `lxc_setup.sh`
- Default config is in heredoc to `/etc/nginx/sites-available/default`
- PHP-FPM socket path: `/run/php/php$PHP_VERSION-fpm.sock`
- FastCGI parameters for PHP processing

### Storage Detection

The script parses `/etc/pve/storage.cfg` to find storages that support:
- `vztmpl` - For container templates
- `rootdir` or `images` - For container root filesystems

Storage detection logic is in lines 419-504 (lxc_setup.sh).

### Template Download Workflow

Templates are checked in this order:
1. Local storage (`pvesm list <storage>`)
2. Available downloads (`pveam available`)
3. If none found, offers to download Ubuntu 24.04 LTS

Download storage priority: First storage with `vztmpl` content type, fallback to `local`.

## Important Configuration Details

### Container Defaults
- **Container ID:** 999 (default, user can change)
- **Hostname:** phprunner-template
- **Memory:** 1024 MB
- **Root Filesystem:** 100 GB
- **Network:** DHCP or static IP
- **Type:** Unprivileged container (`--unprivileged 1`)
- **Auto-start:** Enabled (`--onboot 1`)

### PHP Configuration (Production)
Located in `/etc/php/$PHP_VERSION/apache2/conf.d/99-phprunner.ini` or `/etc/php/$PHP_VERSION/fpm/conf.d/99-phprunner.ini`:
- `upload_max_filesize = 50M`
- `post_max_size = 50M`
- `max_execution_time = 300`
- `memory_limit = 256M`
- `max_input_vars = 3000`
- `display_errors = Off` (production setting)
- OPcache enabled with 64MB memory

### Security Features
- Unprivileged containers by default
- SSH key support for root login
- Security headers (X-Content-Type-Options, X-Frame-Options, X-XSS-Protection)
- Protected directories (config, logs, cache, temp, vendor)
- Disabled directory listing
- Hidden file protection

### SSL Setup
If SSL is enabled, a helper script is created at `/root/setup-ssl.sh` inside the container:
```bash
pct exec <container-id> -- /root/setup-ssl.sh your-domain.com
```

This script uses certbot to automatically configure SSL for the domain.

## Web Server Specific Notes

### Apache2
- Module dependencies: rewrite, ssl, headers, php module
- .htaccess support enabled
- Better PHPRunner compatibility (recommended for PHPRunner)
- PHP runs as Apache module (`libapache2-mod-php$PHP_VERSION`)

### Nginx
- Requires PHP-FPM (separate process)
- More complex FastCGI configuration
- Better performance for static content
- PHP-FPM pool configuration at `/etc/php/$PHP_VERSION/fpm/pool.d/www.conf`

## Troubleshooting

### Common Issues

**Template not found:**
- Run `pveam update` manually
- Check internet connectivity
- Verify storage has `vztmpl` content type: `pvesm status`

**Container creation fails:**
- Check container ID is unique: `pct status <id>` and `qm status <id>`
- Verify storage has sufficient space: `pvesm status`
- Check storage supports containers (rootdir/images content)

**PHP not processing:**
- For Nginx: Verify PHP-FPM socket exists at `/run/php/php$PHP_VERSION-fpm.sock`
- Check PHP-FPM service: `systemctl status php$PHP_VERSION-fpm`
- Review nginx error log: `/var/log/nginx/error.log`

**Port 80 in use:**
- Scripts automatically try to stop conflicting services (Apache2 when installing Nginx)
- Check with: `netstat -tlnp | grep ':80'`

### Debug Mode

Enable debug mode for verbose output:
```bash
DEBUG=1 ./lxc_setup.sh
```

Debug mode shows:
- Template detection details
- Storage parsing logic
- Configuration file generation
- Package installation progress

## Code Patterns

### Heredoc Usage
Scripts extensively use heredocs for multi-line content:
```bash
cat > /tmp/container_config.sh << 'EOF'
# Script content here
EOF
```

The `'EOF'` (quoted) prevents variable expansion until execution.

### Variable Export to Container
Variables are exported to the container script using:
```bash
pct exec $CONTAINER_ID -- bash -c \
    "export PHP_VERSION='$PHP_VERSION'; \
     export WEB_SERVER='$WEB_SERVER'; \
     /tmp/config.sh"
```

### Retry Logic
Package updates use retry loops (3 attempts):
```bash
for i in {1..3}; do
    if apt-get update -y; then
        break
    else
        sleep 10
    fi
done
```

## Development Considerations

### Adding New Features
- Maintain compatibility with both Apache2 and Nginx paths
- Use environment variables for version-specific paths
- Add debug logging with `debug_log()` function
- Test with both web servers

### Modifying Container Configuration
- Changes to the embedded script (between `cat > /tmp/container_config.sh << 'EOF'` and `EOF`) require careful testing
- Verify locale handling to avoid warnings
- Maintain DEBIAN_FRONTEND=noninteractive for non-interactive operation

### Error Handling
- Use `set -e` to exit on errors
- Provide user-friendly error messages with `print_color`
- Verify service status with `systemctl is-active`
- Check file existence before operations

## Proxmox-Specific Commands

### Container Management
```bash
pct create <id> <template> [options]    # Create container
pct start <id>                          # Start container
pct stop <id>                           # Stop container
pct status <id>                         # Check status
pct exec <id> -- <command>              # Execute command
pct push <id> <source> <dest>           # Copy file to container
```

### Template Management
```bash
pveam update                            # Update template list
pveam available                         # List available templates
pveam list <storage>                    # List installed templates
pveam download <storage> <template>     # Download template
```

### Storage Management
```bash
pvesm status                            # List all storage
pvesm list <storage>                    # List storage contents
```
