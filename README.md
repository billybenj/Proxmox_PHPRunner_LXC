# Proxmox PHPRunner LXC Container Creator

A comprehensive bash script for creating ready-to-use LXC containers optimized for PHPRunner applications on Proxmox VE.

## 🚀 Features

### Core Functionality
- **Ubuntu LTS Support**: Optimized for Ubuntu LTS systems only
- **Interactive Setup**: User-friendly prompts with sensible defaults
- **Template Management**: Smart template detection and caching
- **Web Server Choice**: Apache2 or Nginx with proper configuration
- **PHP Versions**: Support for PHP 7.4, 8.0, 8.1, 8.2, 8.3, 8.4
- **Production Ready**: Optimized settings for production environments

### Web Server Features
- **Apache2**: Full .htaccess support, better PHPRunner compatibility
- **Nginx**: Lightweight, high performance with PHP-FPM
- **SSL Ready**: Optional SSL infrastructure setup
- **Security Headers**: Built-in security configurations
- **Performance Optimized**: Production-ready configurations

### PHP Configuration
- **Multiple Versions**: PHP 7.4 through 8.4 support
- **OPCache**: Optimized for performance
- **Memory Limits**: Configurable memory and upload limits
- **Error Handling**: Production error reporting settings
- **Extensions**: MySQL, cURL, GD, ZIP, MBString, XML, Imagick, Intl

### Additional Components
- **Redis**: Optional Redis server installation
- **Composer**: Optional PHP Composer installation
- **MariaDB**: Optional MariaDB server installation
- **SSL Tools**: Certbot integration for Let's Encrypt

### Container Management
- **SSH Access**: Optional SSH server configuration
- **Root Access**: Password and SSH key setup
- **Network Configuration**: DHCP or static IP support
- **Storage Management**: Automatic storage detection
- **Resource Allocation**: Configurable memory and disk space

### Security Features
- **Unprivileged Containers**: Enhanced security
- **SSH Key Support**: Public key authentication
- **Firewall Ready**: Proper network configurations
- **Security Headers**: Web server security configurations

## 📋 Prerequisites

- Proxmox VE 7.x or 8.x
- Ubuntu LTS container templates
- Internet connection for package downloads
- Root or sudo access on Proxmox host

## 🛠️ Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/wdbenj/proxmox-phprunner-lxc.git
   cd proxmox-phprunner-lxc
   ```

2. **Make the script executable**:
   ```bash
   chmod +x lxc_setup.sh
   ```

3. **Run the script**:
   ```bash
   ./lxc_setup.sh
   ```

## 🎯 Usage

### Basic Usage
```bash
./lxc_setup.sh
```

### Debug Mode
```bash
DEBUG=1 ./lxc_setup.sh
```

### Interactive Setup
The script will guide you through:
1. **Template Selection**: Choose Ubuntu LTS template
2. **Container Configuration**: ID, hostname, memory, storage
3. **Network Setup**: DHCP or static IP configuration
4. **Web Server Choice**: Apache2 or Nginx
5. **PHP Version**: Select PHP version (7.4-8.4)
6. **Additional Components**: Redis, Composer, MariaDB
7. **SSL Configuration**: Optional SSL setup
8. **SSH Access**: Optional SSH server configuration
9. **Root Access**: Password and SSH key setup

## 📁 Generated Files

The script creates several test files in `/var/www/html/`:
- `index.html`: Main landing page
- `test.php`: PHP version and configuration test
- `info.php`: PHP information page
- `debug.php`: Debug information
- `health.php`: JSON health check endpoint

## 🔧 Configuration Options

### Container Settings
- **Container ID**: Unique identifier (default: 999)
- **Hostname**: Container hostname (default: phprunner-template)
- **Memory**: RAM allocation in MB (default: 1024)
- **Storage**: Root filesystem size in GB (default: 100)

### Network Configuration
- **DHCP**: Automatic IP assignment
- **Static IP**: Manual IP configuration with gateway

### Web Server Options
- **Apache2**: Full .htaccess support
- **Nginx**: High performance with PHP-FPM

### PHP Versions
- **PHP 8.4**: Latest version (recommended)
- **PHP 8.3**: Stable version
- **PHP 8.2**: LTS version
- **PHP 8.1**: Legacy version
- **PHP 8.0**: Legacy version
- **PHP 7.4**: Legacy version

## 🚀 Quick Start

1. **Run the script**:
   ```bash
   ./lxc_setup.sh
   ```

2. **Follow the prompts**:
   - Choose template (Ubuntu 24.04 LTS recommended)
   - Configure container settings
   - Select web server (Apache2 for PHPRunner)
   - Choose PHP version (8.4 recommended)
   - Configure additional components

3. **Access your container**:
   - Web interface: `http://[container-ip]/`
   - SSH access: `ssh root@[container-ip]` (if enabled)
   - Console access: `pct enter [container-id]`

## 🔍 Troubleshooting

### Common Issues

**Template Download Fails**:
- Check internet connection
- Verify storage has template support
- Run `pveam update` manually

**Container Creation Fails**:
- Check container ID is unique
- Verify storage has sufficient space
- Ensure template exists

**Web Server Issues**:
- Check if port 80 is available
- Verify PHP module is installed
- Check service status: `systemctl status apache2/nginx`

**Locale Warnings**:
- These are normal during installation
- Locale is properly configured after setup

### Debug Mode
Enable debug mode for detailed output:
```bash
DEBUG=1 ./lxc_setup.sh
```

## 📊 System Requirements

### Minimum Requirements
- **RAM**: 1GB per container
- **Storage**: 10GB minimum
- **CPU**: 1 core minimum

### Recommended Requirements
- **RAM**: 2GB per container
- **Storage**: 50GB minimum
- **CPU**: 2 cores minimum

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📝 Changelog

### v1.0.0
- Initial release
- Ubuntu LTS support
- Apache2 and Nginx support
- PHP 7.4-8.4 support
- SSL configuration
- SSH access
- Template caching
- Production optimizations

## 📄 License

MIT License

Copyright (c) 2024 wdbenj

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## 🙏 Acknowledgments

- Proxmox VE team for the excellent virtualization platform
- Ubuntu team for the LTS releases
- PHP community for the web development language
- All contributors and users of this script

## 📞 Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/wdbenj/proxmox-phprunner-lxc/issues)
- **Documentation**: Check this README for usage instructions
- **Community**: Join Proxmox community forums for general help

---

**Made with ❤️ for the Proxmox and PHPRunner communities** 