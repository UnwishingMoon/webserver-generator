#!/bin/sh
#########################################################
#                                                       #
#   Name: Webserver Generator                           #
#   Author: Diego Castagna (diegocastagna.com)          #
#   Description: This script will set-up                #
#   a webserver with Apache2, MySQL, PHP                #
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

DBRootPass=$(openssl rand -base64 32)
DBUserPass=$(openssl rand -base64 32)
DBPMAPass=$(openssl rand -base64 32)
DBHtPass=$(openssl rand -base64 32)

echo "Root:$DBRootPass" >> /root/DBPass.txt
echo "User:$DBUserPass" >> /root/DBPass.txt
echo "PHPMyAdmin:$DBPMAPass" >> /root/DBPass.txt
echo "Htaccess:$DBHtUser $DBHtPass" >> /root/DBPass.txt
chmod 600 /root/DBPass.txt

apt update -yq
apt dist-upgrade -yq

echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $DBRootPass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $DBPMAPass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $DBPMAPass" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt install -yq apache2 mysql-server php libapache2-mod-php php-mysql php-yaml php-cli php-mbstring phpmyadmin
echo PURGE | debconf-communicate phpmyadmin

snap install core
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

a2enmod rewrite headers ssl expires
a2dismod status
a2disconf charset javascript-common other-vhosts-access-log serve-cgi-bin localized-error-pages
rm /etc/apache2/sites-available/*
rm /etc/apache2/sites-enabled/*
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

install -m 640 -o root -g adm /dev/null "/var/log/apache2/${WBHost}_error.log"
install -m 640 -o root -g adm /dev/null "/var/log/apache2/${WBHost}_access.log"

rm -r /var/www/html
mkdir -p /var/www/$WBHost/www
chown -R www-data:www-data /var/www/$WBHost/
chmod -R 775 /var/www/$WBHost/
chmod g+s /var/www/$WBHost/ /var/www/$WBHost/www

usermod -a -G www-data ubuntu

phpenmod mbstring

sed --follow-symlinks -i "/DirectoryIndex index.php/a AllowOverride All\nphp_admin_value open_basedir 'none'" /etc/apache2/conf-enabled/phpmyadmin.conf

echo 'AuthType Basic
Authname "Restricted files"
AuthUserFile /etc/phpmyadmin/.htpasswd
Require valid-user' > /usr/share/phpmyadmin/.htaccess
htpasswd -bc /etc/phpmyadmin/.htpasswd $DBHtUser $DBHtPass

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

apt autoremove -yq
apt autoclean -yq

service apache2 restart
service mysql restart

touch /root/.done