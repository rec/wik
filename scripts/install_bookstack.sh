#!/usr/bin/env bash

set -Eeo pipefail

apt update
apt upgrade -y
apt install -y php mysql-server emacs

wget https://raw.githubusercontent.com/BookStackApp/devops/master/scripts/installation-ubuntu-18.04.sh
chmod a+x installation-ubuntu-18.04.sh
./installation-ubuntu-18.04.sh

ufw allow http
ufw allow https
systemctl reload apache2
