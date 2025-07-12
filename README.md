# Proxmox LXC PHPRunner Application Stack

Production-ready LXC templates and deployment scripts for hosting multiple PHPRunner applications on Proxmox VE with enterprise-grade security and performance.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange)](https://www.proxmox.com/)
[![PHP](https://img.shields.io/badge/PHP-8.4-blue)](https://www.php.net/)
[![Debian](https://img.shields.io/badge/Debian-12.7+-red)](https://www.debian.org/)

## 🚀 Features

- **Modern PHP Stack**: PHP 8.4 with legacy 7.4 support for older applications
- **Containerized Architecture**: Lightweight LXC containers with ZFS thin provisioning
- **SSL Automation**: One-command Let's Encrypt SSL certificate deployment
- **Enterprise Security**: Unprivileged containers with optimized security settings
- **Resource Efficient**: 70% less resource usage compared to traditional VM hosting
- **Template-Based**: Clone and deploy new customers in seconds
- **Production Ready**: Battle-tested configuration for hosting multiple customers

## 🏗️ Architecture

┌─────────────────────────────────────────────────────────────┐
│                     Proxmox VE Host                         │
├─────────────────┬─────────────────┬─────────────────────────┤
│  Template (999) │ Customer A (101)│ Customer B (102)        │
│  PHP 8.4        │ PHPRunner App   │ PHPRunner App           │
│  Nginx          │ SSL Enabled     │ Legacy PHP 7.4          │
│  SSL Ready      │ 192.168.1.101   │ 192.168.1.102           │
└─────────────────┴─────────────────┴─────────────────────────┘
│                 Shared Database LXC (200)                   │
│                 MariaDB 10.11                               │
└─────────────────────────────────────────────────────────────┘

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [📋 Template Creation Guide](templates/phprunner-template-creation.md) | Complete setup instructions for creating the base template |
| [🚀 Customer Deployment](deployment/) | Scripts and guides for deploying new customer containers |
| [🔒 SSL Setup Guide](deployment/setup-ssl.sh) | Automated SSL certificate configuration |
| [📊 Monitoring](monitoring/) | Health checks and resource monitoring scripts |
| [💾 Backup Procedures](backup/) | Container backup and restore procedures |

## ⚡ Quick Start

### 1. Create Template Container
```bash
# Clone this repository to your Proxmox host
git clone https://github.com/billybenj/proxmox-lxc-phprunner-app.git
cd proxmox-lxc-phprunner-app

# Create the base template (see full guide for details)
pct create 999 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname phprunner-template \
  --memory 1024 \
  --rootfs Storage:100 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1