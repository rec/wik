#!/usr/bin/env bash

set -Eeo pipefail

# Update packages and clean up
apt update && apt upgrade -y && apt autoremove -y

# Install packages we need
apt install -y \
    emacs \
    letsencrypt \
    mysql-server \
    php \
    software-properties-common \
    whois

# Set a mysql root password
mysqladmin -u root password <new-password-here>


# certbot!  Needed for https (secure connections)
# Install certbot from its repository
add-apt-repository universe
add-apt-repository ppa:certbot/certbot
apt install -y certbot python-certbot-apache

apt update && apt upgrade -y && apt autoremove -y

# Get a certificate and test
# These should only be run ONCE on a given server!

# https://certbot.eff.org/lets-encrypt/ubuntubionic-apache
certbot --apache
certbot renew --dry-run

# Install BookStack
wget https://raw.githubusercontent.com/BookStackApp/devops/master/scripts/installation-ubuntu-18.04.sh
chmod a+x installation-ubuntu-18.04.sh

# This edits your Apache configuration for BookStack
./installation-ubuntu-18.04.sh

# Open the firewall to http and https
ufw allow http
ufw allow https

# Restart the webserver
systemctl reload apache2

---

# To reinstall BookStack with the script above,
# you need to get rid of the mysql
mysql -u root
DROP DATABASE bookstack;
DROP USER bookstack@localhost;
