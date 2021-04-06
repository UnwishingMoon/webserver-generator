#!/bin/sh
#########################################################
#                                                       #
#   Name: Webserver Generator                           #
#   Author: Diego Castagna (diegocastagna.com)          #
#   Description: This script will set-up                #
#   a webserver with Apache2, MariaDB, PHP              #
#   and PHPMyAdmin, all passwords are saved             #
#   under /root directory                               #
#   Common Usage: AWS User Data                         #
#   License: diegocastagna.com/license                  #
#                                                       #
#########################################################

# Variables - EDIT THIS!
DBUserName="diego"
DBName="diegocastagna_com"
WBHost="diegocastagna.com"
DBHtUser="phpmyadmin"
AWSCliUrl="https://www.diegocastagna.com/files/aws/awscli.tar.xz"

DBRootPass=$(openssl rand -base64 32)
DBUserPass=$(openssl rand -base64 32)
DBPMAPass=$(openssl rand -base64 32)
DBHtPass=$(openssl rand -base64 32)

echo "Root:$DBRootPass" >> /root/dbpass.txt
echo "User:$DBUserPass" >> /root/dbpass.txt
echo "PHPMyAdmin:$DBPMAPass" >> /root/dbpass.txt
echo "Htaccess:$DBHtUser $DBHtPass" >> /root/dbpass.txt
chmod 600 /root/dbpass.txt

# Updating and installing packages
apt update -yq
apt dist-upgrade -yq
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $DBRootPass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $DBPMAPass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $DBPMAPass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt install -yqt buster-backports php-twig
apt install -yq apache2 mariadb-server php libapache2-mod-php php-mysqli php-cli php-yaml php-mbstring snapd phpmyadmin
echo PURGE | debconf-communicate phpmyadmin

# Installing certbot
snap install core
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

# Creating gitlab user and .ssh files
adduser --disabled-password gitlab
mkdir -p /home/gitlab/.ssh
touch /home/gitlab/.ssh/authorized_keys
chown -R gitlab.gitlab /home/gitlab/.ssh/
chmod 700 /home/gitlab/.ssh/
chmod 644 /home/gitlab/.ssh/authorized_keys

# Adding groups to users
usermod -aG www-data,gitlab admin
usermod -aG www-data gitlab

# Creating backups folders
mkdir /root/scripts/
chmod -R 500 /root/scripts/
mkdir -p /root/backups/db/
chmod -R 700 /root/backups/

# Creating root mysql automatic login file
echo "[client]
user='root'
password='$DBRootPass'" > /root/.my.cnf
chmod 400 /root/.my.cnf

# Updating AWS Cli
apt remove awscli
wget -O /root/awscli.tar.xz $AWSCliUrl
tar -xf /root/awscli.tar.xz -C /root/
bash /root/aws/install
rm -r /root/aws/
rm /root/awscli.tar.xz

# Basic Apache2 setup
a2enmod rewrite headers ssl expires
a2dismod status
a2disconf charset javascript-common other-vhosts-access-log serve-cgi-bin localized-error-pages
echo "<VirtualHost *:80>
    ServerAlias www.${WBHost}
    ServerName ${WBHost}
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/${WBHost}/www

    php_admin_value open_basedir '/tmp/:/var/www/${WBHost}/'

    LogLevel error
    ErrorLog \${APACHE_LOG_DIR}/${WBHost}_error.log
    CustomLog \${APACHE_LOG_DIR}/${WBHost}_access.log combined

    <Directory /var/www/${WBHost}/www/>
        Options -Indexes +SymLinksIfOwnerMatch -Includes
        AllowOverride All
    </Directory>
</VirtualHost>" > /etc/apache2/sites-available/000-default.conf
a2ensite 000-default.conf

# Enabling extra PHP modules
phpenmod mbstring

# Creating apache2 virtualhost logs files
install -m 640 -o root -g adm /dev/null "/var/log/apache2/${WBHost}_error.log"
install -m 640 -o root -g adm /dev/null "/var/log/apache2/${WBHost}_access.log"

# Setting up webserver folders
rm -r /var/www/html
mkdir -p /var/www/$WBHost/www/
chown admin:admin /var/www/$WBHost/
chown gitlab:gitlab /var/www/$WBHost/www/
chmod -R 775 /var/www/$WBHost/
chmod -R g+s /var/www/$WBHost/

# Enabling htaccess rewrite and password login on phpmyadmin page
sed --follow-symlinks -i "/DirectoryIndex index.php/a AllowOverride All\n" /etc/apache2/conf-enabled/phpmyadmin.conf
echo 'AuthType Basic
Authname "Restricted files"
AuthUserFile /etc/phpmyadmin/.htpasswd
Require valid-user' > /usr/share/phpmyadmin/.htaccess
htpasswd -bc /etc/phpmyadmin/.htpasswd $DBHtUser $DBHtPass

# Basic database setup
mysql -u root <<_EOF_
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DBRootPass}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE ${DBName};
CREATE USER '${DBUserName}'@'localhost' IDENTIFIED BY '${DBUserPass}';
GRANT ALL PRIVILEGES ON ${DBName}.* TO '${DBUserName}'@'localhost';
FLUSH PRIVILEGES;
_EOF_

# Cleaning and exiting
apt autoremove -yq
apt autoclean -yq

service apache2 restart
service mysql restart

touch /root/.done