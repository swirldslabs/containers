#!/usr/bin/env bash
set -eo pipefail

#############################
### General Configuration ###
#############################

# Make entrypoint.sh executable
chmod +x /usr/local/bin/entrypoint.sh
chmod +x /usr/local/bin/entrypoint-helper.sh
chmod +x /usr/local/bin/logger.sh

#############################
### Apache2 Configuration ###
#############################

# Ensure directories exist
mkdir -p /var/www/html
mkdir -p /var/log/apache2
mkdir -p /var/run/apache2

### Clean HTML Root Directory ###
rm -rf /var/www/html/*

### Setup Folder Ownership & Permissions ###
# Log Directory
chown -R www-data:www-data /var/log/apache2/
chmod -R 755 /var/log/apache2/
# Run Directories
chown -R www-data:www-data /var/run/apache2/
# Configuration Directories
chown -R www-data:www-data /etc/apache2/conf-enabled
chown -R www-data:www-data /etc/apache2/mods-enabled
chown -R www-data:www-data /etc/apache2/sites-enabled
# Lib Directories
chown -R www-data:www-data /var/lib/apache2/conf
chown -R www-data:www-data /var/lib/apache2/module
chown -R www-data:www-data /var/lib/apache2/site
# Default Site Root
chown -R www-data:www-data /var/www/html

# Configure modules
a2enmod ssl >/dev/null
a2enmod rewrite >/dev/null
a2enmod headers >/dev/null
a2dismod auth_openidc >/dev/null

# Configure sites
a2dissite 000-default >/dev/null
rm -f /etc/apache2/sites-available/000-default.conf

# Disable cgi-bin support
a2disconf serve-cgi-bin >/dev/null
a2disconf auth_openidc >/dev/null

# Rewrite ports.conf to use 8080 & 8443
</etc/apache2/ports.conf \
  perl -pe 's/Listen\s+80/Listen 8080/g' | \
  perl -pe 's/Listen\s+443/Listen 8443/g' | \
  tee /etc/apache2/ports.conf.tmp >/dev/null
cp -f /etc/apache2/ports.conf.tmp /etc/apache2/ports.conf
rm -f /etc/apache2/ports.conf.tmp

# Rewrite security.conf to harden the server
</etc/apache2/conf-available/security.conf \
    perl -pe 's/^ServerSignature\s+On/#ServerSignature On/g' | \
    perl -pe 's/#ServerSignature\s+Off/ServerSignature Off/g' | \
    perl -pe 's/^ServerTokens\s+OS/#ServerTokens OS/g' | \
    perl -pe 's/^ServerTokens\s+Full/#ServerTokens Full/g' | \
    perl -pe 's/#ServerTokens\s+Minimal/ServerTokens Minimal/g' | \
    perl -pe 's/#Header\s+set\s+Content-Security-Policy/Header set Content-Security-Policy/g' | \
    tee /etc/apache2/conf-available/security.conf.tmp >/dev/null
cp -f /etc/apache2/conf-available/security.conf.tmp /etc/apache2/conf-available/security.conf
rm -f /etc/apache2/conf-available/security.conf.tmp

</etc/apache2/apache2.conf \
    perl -pe 's/^ErrorLog.*$/ErrorLog \"|\/usr\/bin\/cat\"/g' | \
    tee /etc/apache2/apache2.conf.tmp >/dev/null
cp -f /etc/apache2/apache2.conf.tmp /etc/apache2/apache2.conf
rm -f /etc/apache2/apache2.conf.tmp

</etc/apache2/mods-available/ssl.conf \
    perl -pe 's/#SSLHonorCipherOrder/SSLHonorCipherOrder/g' | \
    tee /etc/apache2/mods-available/ssl.conf.tmp >/dev/null
cp -f /etc/apache2/mods-available/ssl.conf.tmp /etc/apache2/mods-available/ssl.conf
rm -f /etc/apache2/mods-available/ssl.conf.tmp
