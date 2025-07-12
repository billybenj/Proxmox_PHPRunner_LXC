\# PHPRunner Template Creation Script



\## Complete Setup Guide

\*\*Template\*\*: Debian 12.7 + PHP 8.4 + Nginx + SSL-Ready  

\*\*Storage\*\*: ZFS (Storage pool)  

\*\*Memory\*\*: 1GB template, 512MB customers  

\*\*Features\*\*: Modern PHP 8.4, SSL infrastructure, container optimized



---



\## 1. Create Template Container



```bash

\# Create the template container

pct create 999 local:vztmpl/debian-12-standard\_12.7-1\_amd64.tar.zst \\

&nbsp; --hostname phprunner-template \\

&nbsp; --memory 1024 \\

&nbsp; --rootfs Storage:100 \\

&nbsp; --net0 name=eth0,bridge=vmbr0,ip=dhcp \\

&nbsp; --unprivileged 1



\# Start the container

pct start 999

```



---



\## 2. Configure PHP 8.4 + Nginx + SSL



```bash

\# Configure fresh template with PHP 8.4 (modern default)

pct exec 999 -- bash -c "

echo 'Starting modern PHP 8.4 template configuration...'



\# Update system to latest (12.11 equivalent)

apt update \&\& apt dist-upgrade -y



echo 'Adding Sury PHP repository for PHP 8.4...'



\# Add Ondřej Surý repository for latest PHP

apt install -y apt-transport-https lsb-release ca-certificates wget

wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

echo 'deb https://packages.sury.org/php/ bookworm main' > /etc/apt/sources.list.d/php.list



\# Update package list with new repository

apt update



echo 'Installing core packages...'



\# Install nginx and basic tools

apt install -y \\

&nbsp; nginx-light \\

&nbsp; mariadb-client \\

&nbsp; unzip \\

&nbsp; curl \\

&nbsp; wget \\

&nbsp; git \\

&nbsp; nano \\

&nbsp; htop \\

&nbsp; certbot



echo 'Installing PHP 8.4 (modern default)...'



\# Install PHP 8.4 with all necessary extensions

apt install -y \\

&nbsp; php8.4-fpm \\

&nbsp; php8.4-cli \\

&nbsp; php8.4-mysql \\

&nbsp; php8.4-curl \\

&nbsp; php8.4-gd \\

&nbsp; php8.4-zip \\

&nbsp; php8.4-mbstring \\

&nbsp; php8.4-xml \\

&nbsp; php8.4-imagick \\

&nbsp; php8.4-intl \\

&nbsp; php8.4-opcache \\

&nbsp; php8.4-readline



echo 'Configuring PHP 8.4 for containers...'



\# Optimize PHP 8.4 FPM for container use

sed -i 's/pm.max\_children = 5/pm.max\_children = 4/' /etc/php/8.4/fpm/pool.d/www.conf

sed -i 's/pm.start\_servers = 2/pm.start\_servers = 1/' /etc/php/8.4/fpm/pool.d/www.conf

sed -i 's/pm.min\_spare\_servers = 1/pm.min\_spare\_servers = 1/' /etc/php/8.4/fpm/pool.d/www.conf

sed -i 's/pm.max\_spare\_servers = 3/pm.max\_spare\_servers = 2/' /etc/php/8.4/fpm/pool.d/www.conf



echo 'Creating PHP 8.4 configuration for PHPRunner...'



\# PHP 8.4 settings optimized for PHPRunner

cat > /etc/php/8.4/fpm/conf.d/99-phprunner.ini << 'EOF'

; PHPRunner optimizations for PHP 8.4

upload\_max\_filesize = 50M

post\_max\_size = 50M

max\_execution\_time = 300

memory\_limit = 256M

max\_input\_vars = 3000

date.timezone = America/Edmonton

expose\_php = Off

display\_errors = Off

log\_errors = On

EOF



echo 'Setting up web directory structure...'



\# Create web directories

mkdir -p /var/www/html

chown -R www-data:www-data /var/www/html



\# Create test files

cat > /var/www/html/index.html << 'EOF'

<!DOCTYPE html>

<html>

<head><title>PHPRunner Template - PHP 8.4</title></head>

<body>

<h1>PHPRunner Template Ready</h1>

<p>This container runs PHP 8.4 (modern default)</p>

<ul>

<li><a href=\\"info.php\\">PHP 8.4 Info</a></li>

<li><a href=\\"test.php\\">Test PHP 8.4</a></li>

</ul>

</body>

</html>

EOF



\# PHP 8.4 test file

cat > /var/www/html/test.php << 'EOF'

<?php

echo '<h2>PHP 8.4 Ready</h2>';

echo 'PHP Version: ' . PHP\_VERSION . '<br>';

echo 'Server Time: ' . date('Y-m-d H:i:s') . '<br>';

echo 'MySQL Extension: ' . (extension\_loaded('mysqli') ? 'Available' : 'Not Available') . '<br>';

echo 'Memory Limit: ' . ini\_get('memory\_limit') . '<br>';

echo '<strong>Ready for modern PHPRunner applications!</strong>';

?>

EOF



\# Standard PHP info

cat > /var/www/html/info.php << 'EOF'

<?php phpinfo(); ?>

EOF



echo 'Configuring nginx for PHP 8.4...'



\# Clean nginx config for PHP 8.4

cat > /etc/nginx/sites-available/default << 'EOF'

server {

&nbsp;   listen 80 default\_server;

&nbsp;   listen \[::]:80 default\_server;

&nbsp;   

&nbsp;   root /var/www/html;

&nbsp;   index index.php index.html index.htm;

&nbsp;   server\_name \_;

&nbsp;   

&nbsp;   # Let's Encrypt challenge location

&nbsp;   location /.well-known/acme-challenge/ {

&nbsp;       root /var/www/html;

&nbsp;   }

&nbsp;   

&nbsp;   # Increase upload limits for PHPRunner

&nbsp;   client\_max\_body\_size 50M;

&nbsp;   

&nbsp;   location / {

&nbsp;       try\_files \\$uri \\$uri/ /index.php?\\$query\_string;

&nbsp;   }

&nbsp;   

&nbsp;   location ~ \\.php\\$ {

&nbsp;       include snippets/fastcgi-php.conf;

&nbsp;       fastcgi\_pass unix:/var/run/php/php8.4-fpm.sock;

&nbsp;       fastcgi\_param SCRIPT\_FILENAME \\$document\_root\\$fastcgi\_script\_name;

&nbsp;       include fastcgi\_params;

&nbsp;   }

&nbsp;   

&nbsp;   location ~ /\\.ht {

&nbsp;       deny all;

&nbsp;   }

&nbsp;   

&nbsp;   location ~\* \\.(jpg|jpeg|png|gif|ico|css|js|pdf|zip)\\$ {

&nbsp;       expires 1y;

&nbsp;       add\_header Cache-Control 'public, immutable';

&nbsp;   }

}

EOF



\# Test nginx configuration

nginx -t



echo 'Enabling services...'



\# Enable services to start on boot

systemctl enable php8.4-fpm nginx



echo 'Starting services...'



\# Start services

systemctl start php8.4-fmp nginx



echo 'Setting up SSL infrastructure...'



\# Create SSL directories

mkdir -p /etc/nginx/ssl

mkdir -p /var/www/html/.well-known/acme-challenge



\# Create SSL setup script for easy customer deployment

cat > /root/setup-ssl.sh << 'EOF'

\#!/bin/bash

\# SSL Setup Script for PHPRunner Container



if \[ -z \\"\\$1\\" ]; then

&nbsp;   echo \\"Usage: ./setup-ssl.sh your-domain.com\\"

&nbsp;   echo \\"Example: ./setup-ssl.sh myapp.example.com\\"

&nbsp;   exit 1

fi



DOMAIN=\\$1

echo \\"Setting up SSL for domain: \\$DOMAIN\\"



\# Update server\_name in nginx config

sed -i \\"s/server\_name \_;/server\_name \\$DOMAIN;/\\" /etc/nginx/sites-available/default



\# Get Let's Encrypt certificate

certbot --nginx -d \\$DOMAIN --non-interactive --agree-tos --email admin@\\$DOMAIN



\# Enable automatic renewal

systemctl enable certbot.timer



echo \\"SSL setup complete for \\$DOMAIN\\"

echo \\"Your site is now available at: https://\\$DOMAIN\\"

EOF



chmod +x /root/setup-ssl.sh



echo 'Template configuration complete!'

"

```



---



\## 3. Verify Template Setup



```bash

\# Test the complete setup

pct exec 999 -- bash -c "

echo 'Final verification:'

echo '=================='

echo 'PHP Version:' \&\& php -v | head -1

echo 'PHP-FPM Status:' \&\& systemctl is-active php8.4-fpm

echo 'Nginx Status:' \&\& systemctl is-active nginx

echo 'Container IP:' \&\& ip addr show eth0 | grep 'inet ' | awk '{print \\$2}' | cut -d'/' -f1

echo 'Web Access:' \&\& echo \\"http://\\$(ip addr show eth0 | grep 'inet ' | awk '{print \\$2}' | cut -d'/' -f1)/test.php\\"

echo 'SSL Script:' \&\& ls -la /root/setup-ssl.sh

echo 'Template ready for conversion!'

"

```



---



\## 4. Convert to Template



```bash

\# Stop the container

pct stop 999



\# Convert to template

pct template 999



\# Verify in GUI - should show template icon

```



---



\## 5. Customer Deployment



\### Clone Template

```bash

\# Clone for new customer

pct clone 999 101 --hostname customer-domain-com

pct set 101 --memory 512 --cores 1

pct set 101 --net0 name=eth0,bridge=vmbr0,ip=192.168.1.101/24,gw=192.168.1.1

pct start 101

```



\### Test Customer Container

```bash

\# Verify customer container

pct exec 101 -- bash -c "

echo 'Customer Container Test:'

echo '======================'

echo 'PHP Version:' \&\& php -v | head -1

echo 'Services:' \&\& systemctl is-active nginx php8.4-fpm

echo 'IP Address:' \&\& ip addr show eth0 | grep 'inet ' | awk '{print \\$2}' | cut -d'/' -f1

echo 'SSL Script:' \&\& ls /root/setup-ssl.sh

echo 'Ready for PHPRunner deployment!'

"

```



\### Add SSL (When Ready)

```bash

\# Enable SSL for customer domain

pct exec 101 -- /root/setup-ssl.sh customer-domain.com

```



---



\## 6. Legacy PHP 7.4 Support (Optional)



\### Add PHP 7.4 to Specific Customer

```bash

\# For customers needing PHP 7.4 compatibility

pct exec 101 -- bash -c "

echo 'Adding PHP 7.4 for legacy app...'



\# Install PHP 7.4 alongside 8.4

apt install -y php7.4-fmp php7.4-cli php7.4-mysql php7.4-curl php7.4-gd php7.4-zip php7.4-mbstring php7.4-xml



\# Configure PHP 7.4

sed -i 's/pm.max\_children = 5/pm.max\_children = 4/' /etc/php/7.4/fpm/pool.d/www.conf

cp /etc/php/8.4/fpm/conf.d/99-phprunner.ini /etc/php/7.4/fpm/conf.d/



\# Switch to PHP 7.4

sed -i 's/php8.4-fpm.sock/php7.4-fpm.sock/' /etc/nginx/sites-available/default



\# Start services

systemctl enable php7.4-fpm \&\& systemctl start php7.4-fpm

systemctl reload nginx



echo 'Switched to PHP 7.4 for legacy compatibility'

"

```



\### Switch Back to PHP 8.4

```bash

\# Upgrade customer from 7.4 to 8.4 when ready

pct exec 101 -- sed -i 's/php7.4-fpm.sock/php8.4-fpm.sock/' /etc/nginx/sites-available/default

pct exec 101 -- systemctl reload nginx

```



---



\## Template Specifications



\- \*\*Base\*\*: Debian 12.7 (upgrades to 12.11)

\- \*\*PHP\*\*: 8.4 with all PHPRunner extensions

\- \*\*Web Server\*\*: Nginx (optimized)

\- \*\*SSL\*\*: Let's Encrypt ready (one-command setup)

\- \*\*Storage\*\*: 100GB virtual

\- \*\*Memory\*\*: 1GB template, 512MB customers

\- \*\*Security\*\*: Unprivileged containers

\- \*\*Timezone\*\*: America/Edmonton



---



\## Quick Reference



| Action | Command |

|--------|---------|

| Access container | `pct exec 101 -- bash` |

| Check services | `pct exec 101 -- systemctl status nginx php8.4-fpm` |

| Add SSL | `pct exec 101 -- /root/setup-ssl.sh domain.com` |

| Container IP | `pct exec 101 -- hostname -I` |

| Switch PHP version | Edit `/etc/nginx/sites-available/default` socket path |

