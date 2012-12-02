#!/bin/bash

###############################################################################
# 
#  This is a simple VPS setup for webserver.
#     should/could work on debian 6 and ubuntu 10.04 to 12.04 
#
###############################################################################


###############################################################################
# Parameters - please set accordingly to desired values 
###############################################################################

########################################
# SETUP CLEAN SYSTEM SECTION 
########################################

# Setup/Install a clean system?
SETUP_CLEAN_SYSTEM=1

# Disable getty instances? You don't need unless you will VNC the VPS
DISABLE_GETTY=1

# Replace bash with dash and save some memory?  
INSTALL_DASH=0

# Configure timezone?
RECONFIGURE_TIMEZONE=1

# The timezone to set
SERVER_TIMEZONE="Asia/Manila"

########################################
# SETUP WEBSERVER SECTION
########################################

#  Setup/Install Webserver section?
SETUP_WEBSERVER=1

# Install Nginx Webserver
INSTALL_NGINX=yes

# Number of cpu cores in your VPS/server.
# Will be used to configure nginx for optimum performance
NUMBER_OF_CPU_CORES=1

# How long will cache for a page be valid, 5m means 5 minutes
FASTCGI_CACHE_TIMEOUT=5m

# Install PHP
INSTALL_PHP=1

# Install PHP APC, a PHP Accelerator, usually doubles the performance
# Sometimes this causes problem and makes PHP not work.
INSTALL_PHP_APC=1

# Advisable to set to yes if memory is 128mb or less
SET_PHP_LOWEND=1

# Install MySQL
INSTALL_MYSQL=1

# password of mysql root user
MYSQL_ROOT_PASSWORD=root

# Advisable to set to yes if memory is 128mb or less.
# Will disable innodb and tweak settings to decrease memory consumption 
SET_MYSQL_LOWEND=1

########################################
# SETUP SECURITY SECTION
########################################

# Setup/Install Simple Security?
SETUP_SECURITY=1

# Change default SSH Port for obscurity.  default is 22, 
# Use high number less than 65535. 
SSHPORT=49999

# install a firewall
INSTALL_FIREWALL=1

# list all ports you wish to open from the outsite world
declare -a FIREWALL_OPEN_PORTS=('80' '443');

# prevent ssh as root
DISABLE_ROOT_LOGIN=1

# prevent password login.  All login will be by public key.
# Be sure to upload your public key to a server user's authorized_keys,
# otherwise access to your VPS will be lost.
DISABLE_PASSWORD_LOGIN=1


###############################################################################
# Common functions
###############################################################################
function check_install {
    if [ -z "`which "$1" 2>/dev/null`" ]
    then
        executable=$1
        shift
        while [ -n "$1" ]
        do
            DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
            print_info "$1 installed for $executable"
            shift
        done
    else
        print_warn "$2 already installed"
    fi
}

function check_remove {
    if [ -n "`which "$1" 2>/dev/null`" ]
    then
        DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
        print_info "$2 removed"
    else
        print_warn "$2 is not installed"
    fi
}

function die {
    echo "ERROR: $1" > /dev/null 1>&2
    exit 1
}

function check_sanity {
    echo "Check Sanity"
    if [ $(/usr/bin/id -u) != "0" ]
    then
        die 'Must be run by root user'
    fi
    
    if [ ! -f /etc/debian_version ]
    then
        die "Distribution is not supported"
    fi
    
    chmod 700 /root
    
    echo "passed."
}

###############################################################################
# SETUP
###############################################################################

########################################
# SETUP CLEAN SYSTEM SECTION 
########################################

function do_install_favorite_programs {
    echo "Install favorite programs: locate, nano"
    apt-get -y update
    check_install locate locate
    check_install nano nano
    check_install htop htop
    check_install less less
    check_install zip zip
    check_install gzip gzip
    check_install unzip unzip
    
    # great tool for OpenVZ VPS to check memory
    wget http://www.pixelbeat.org/scripts/ps_mem.py
    cp ps_mem.py /usr/bin/ps_mem.py
    chmod +x /usr/bin/ps_mem.py
    updatedb
}

function do_remove_unneeded {
    echo "Remove un-needed programs"
    # Some Debian have portmap installed. We don't need that.
    echo "Remove portmap"
    check_remove /sbin/portmap portmap

    # Remove rsyslogd, which allocates ~30MB privvmpages on an OpenVZ system,
    # which might make some low-end VPS inoperatable. We will do this even
    # before running apt-get update.
    echo "Remove rsyslogd"
    check_remove /usr/sbin/rsyslogd rsyslog

    # Other packages that seem to be pretty common in standard OpenVZ
    # templates.
    echo "Remove apache2"
    check_remove /usr/sbin/apache2 'apache2*'
    echo "Remove named bind9"
    check_remove /usr/sbin/named bind9
    echo "Remove samba"
    check_remove /usr/sbin/smbd 'samba*'
    echo "Remove nscd"
    check_remove /usr/sbin/nscd nscd

    # Need to stop sendmail as removing the package does not seem to stop it.
    echo "remove sendmail"
    if [ -f /usr/lib/sm.bin/smtpd ]
    then
        invoke-rc.d sendmail stop
        check_remove /usr/lib/sm.bin/smtpd 'sendmail*'
    fi
}

function do_update_upgrade {
    echo "Update and Upgrade"
    # Run through the apt-get update/upgrade first. This should be done before
    # we try to install any package
    apt-get -q -y update
    apt-get -q -y upgrade
}

function do_disable_getty {
    echo "Reduce Getty Instances"
    sed -i -e '/getty/d' /etc/inittab
}

function do_install_dash {
    echo "Dash"
    #ignore dash for now, as the savings is not that much for 128mb+ vps
    #check_install dash dash
    #rm -f /bin/sh
    #ln -s dash /bin/sh
}

function do_install_syslogd {
    echo "Install Syslogd"
    
    echo "install syslogd"
    check_install /usr/sbin/syslogd inetutils-syslogd
    echo "stop syslogd service"
    invoke-rc.d inetutils-syslogd stop
    
    # Remove Log Files
    echo "remove old log files"
    rm /var/log/* /var/log/*/* > /dev/null 2>&1
    rm -rf /var/log/news > /dev/null 2>&1

    # Create New Log Files
    echo "create new logfiles"
    touch /var/log/{auth,daemon,kernel,mail,messages} > /dev/null 2>&1
    
    #Disable synch()
    echo "Disable synch()"
    sed -i -e 's@\([[:space:]]\)\(/var/log/\)@\1-\2@' /etc/*syslog.conf
    
    invoke-rc.d inetutils-syslogd start   
}

function do_reconfigure_timezone {
    echo "Timezone"
    dpkg-reconfigure -f noninteractive tzdata
    echo $SERVER_TIMEZONE > /etc/timezone    
    dpkg-reconfigure -f noninteractive tzdata
}

function do_setup_cleanup_system {
  do_install_favorite_programs
  do_remove_unneeded
  do_update_upgrade
  do_install_syslogd

  if [ $DISABLE_GETTY = "1" ]
  then
    do_disable_getty
  fi

  if [ $INSTALL_DASH = "1" ]
  then
    do_install_dash
  fi

  if [ $RECONFIGURE_TIMEZONE = "1" ]
  then
    do_reconfigure_timezone
  fi
}

########################################
# SETUP WEBSERVER SECTION
########################################

function do_install_nginx {
    echo " Installing NGINX"
    
	echo "install nginx"
    check_install nginx nginx
    
    echo " Setting up configurations"
    mkdir /etc/nginx/global
    
    echo "Setup worker processes based on number of cpu cores"
    sed -i "/worker_processes/cworker_processes $NUMBER_OF_CPU_CORES;"  /etc/nginx/nginx.conf
    
    echo "Setup cache"    
    sed -i '/http {/c\http \{\n\n\nfastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=WORDPRESS:10m inactive=50m;\nfastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";\nfastcgi_cache_use_stale error timeout invalid_header http_500;\n\n\n'  /etc/nginx/nginx.conf
    
    echo " Common restrictions"
    cat > /etc/nginx/global/restrictions.conf <<END
# Global restrictions configuration file.
# Designed to be included in any server {} block.</p>
location = /favicon.ico {
	log_not_found off;
	access_log off;
}

location = /robots.txt {
	allow all;
	log_not_found off;
	access_log off;
}

# Deny all attempts to access hidden files such as .htaccess, .htpasswd, .DS_Store (Mac).
# Keep logging the requests to parse later (or to pass to firewall utilities such as fail2ban)
location ~ /\. {
	deny all;
}

# Deny access to any files with a .php extension in the uploads directory
# Works in sub-directory installs and also in multisite network
# Keep logging the requests to parse later (or to pass to firewall utilities such as fail2ban)
location ~* /(?:uploads|files)/.*\.php\$ {
	deny all;
}

# Make sure files with the following extensions do not get loaded by nginx because nginx would display the source code, and these files can contain PASSWORDS!
location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)\$|^(\..*|Entries.*|Repository|Root|Tag|Template)\$|\.php_
{
	return 444;
}

# Deny all attempts to access hidden files such as .htaccess, .htpasswd, .DS_Store (Mac).
location ~ /\. {
	return 444;
	access_log off;
	log_not_found off;
}

#nocgi
location ~* \.(pl|cgi|py|sh|lua)\\$ {
	return 444;
}

#disallow
    location ~* (roundcube|webdav|smtp|http\:|soap|w00tw00t) {
	return 444;
}
END

    echo " Common wordpress with fastcgi caching"
    cat > /etc/nginx/global/wordpress.cache.conf <<END
#fastcgi_cache start
set \$no_cache 0;

# POST requests and urls with a query string should always go to PHP
if (\$request_method = POST) {
        set \$no_cache 1;
}   
if (\$query_string != "") {
        set \$no_cache 1;
}   

# Don't cache uris containing the following segments
if (\$request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-(app|cron|login|register|mail).php|wp-.*.php|/feed/|index.php|wp-comments-popup.php|wp-links-opml.php|wp-locations.php|sitemap(_index)?.xml|[a-z0-9_-]+-sitemap([0-9]+)?.xml)") {
        set \$no_cache 1;
}   

# Don't use the cache for logged in users or recent commenters
if (\$http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
        set \$no_cache 1;
}

#note location{] block is simple now as caching is done on nginx's end
location / {
        try_files \$uri \$uri/ /index.php?\$args;
} 

# Add trailing slash to */wp-admin requests.
rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;

# Directives to send expires headers and turn off 404 error logging.
location ~* ^.+\.(js|css|swf|xml|txt|ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)\$ {
       access_log off; log_not_found off; expires max;
}

# Pass all .php files onto a php-fpm/php-fcgi server.
location ~ \.php\$ {
         try_files \$uri =404; 
         include fastcgi_params;
         fastcgi_pass 127.0.0.1:9000;
         fastcgi_cache_bypass \$no_cache;
         fastcgi_no_cache \$no_cache;
         fastcgi_cache WORDPRESS;
         #fastcgi_cache_valid  1m;
         
		fastcgi_cache_valid  200 302 $FASTCGI_CACHE_TIMEOUT;
		fastcgi_cache_valid  301 1h;
		fastcgi_cache_valid  any $FASTCGI_CACHE_TIMEOUT;
}
END

    echo " Common wordpress without caching"
    cat > /etc/nginx/global/wordpress.conf <<END
# WordPress single blog rules.
location / {
	try_files \$uri \$uri/ /index.php?\$args;
}

# Add trailing slash to */wp-admin requests.
rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;

# Directives to send expires headers and turn off 404 error logging.
location ~* ^.+\.(js|css|swf|xml|txt|ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)\$ {
       access_log off; log_not_found off; expires max;
}

# Pass all .php files onto a php-fpm/php-fcgi server.
location ~ \.php\$ {
	try_files \$uri =404;
	fastcgi_split_path_info ^(.+\.php)(/.+)\$;
	include fastcgi_params;
	fastcgi_index index.php;
	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	fastcgi_pass 127.0.0.1:9000;
}
END

    #remove these files as they can cause problems.
    rm /etc/nginx/sites-enabled/default
    rm /etc/nginx/sites-available/default

    echo "Restart NGINX"
    invoke-rc.d nginx restart
}

function do_install_php {
    echo "PHP"
    
    echo "install php"
    sed -i -e '/packages.dotdeb.org/d' /etc/apt/sources.list
    echo "deb http://packages.dotdeb.org stable all" >> /etc/apt/sources.list
    gpg --keyserver keys.gnupg.net --recv-key 89DF5277
    gpg -a --export 89DF5277 | apt-key add -
    apt-get -q -y update
    apt-get install -q -y --force-yes php5 php5-fpm php-pear php5-common php5-mcrypt php5-mysql php5-cli php5-gd php5-suhosin php5-cgi
    # we dont edit nginx.conf and leave the default as is.  to avoid nginx not loading properly.

    sed -i "/pm.max_children =/cpm.max_children = 4" /etc/php5/fpm/pool.d/www.conf
    sed -i "/request_terminate_timeout/crequest_terminate_timeout = 30s" /etc/php5/fpm/pool.d/www.conf
    sed -i "/memory_limit/cmemory_limit = 80M" /etc/php5/fpm/php.ini
    sed -i "/pm.max_requests/cpm.max_requests = 500" /etc/php5/fpm/pool.d/www.conf
    sed -i "/pm.start_servers/cpm.start_servers = 2" /etc/php5/fpm/pool.d/www.conf
    sed -i "/pm.max_spare_servers/cpm.max_spare_servers = 4" /etc/php5/fpm/pool.d/www.conf

    if [ $SET_PHP_LOWEND = "1" ]
    then
        sed -i "/memory_limit/cmemory_limit = 32M" /etc/php5/fpm/php.ini
        sed -i "/pm.max_children/cpm.max_children = 2" /etc/php5/fpm/pool.d/www.conf
        sed -i "/pm.max_spare_servers/cpm.max_spare_servers = 2" /etc/php5/fpm/pool.d/www.conf
    fi

    echo "restart PHP"
    invoke-rc.d php5-fpm restart
}

function do_install_php_apc {
  check_install php-apc php-apc
}

function do_install_mysql {
    show_title "MySQL"
    # Install the MySQL packages
    check_install mysqld mysql-server
    check_install mysql mysql-client

if [ $SET_MYSQL_LOWEND = "1" ]
then
    # Install a low-end copy of the my.cnf to disable InnoDB, and then delete
    # all the related files.
    invoke-rc.d mysql stop
    rm -f /var/lib/mysql/ib*
    cat > /etc/mysql/conf.d/lowmem.cnf <<END
[mysqld]
key_buffer_size = 8M
max_allowed_packet = 1M
max_connections = 20
max_heap_table_size = 4M
net_buffer_length = 2K
query_cache_limit = 256K
query_cache_size = 4M
read_buffer_size = 256K
read_rnd_buffer_size = 256K
sort_buffer_size = 64K
table_open_cache = 256
thread_stack = 128K
END

    cat > /etc/mysql/conf.d/innodb.cnf <<END
[mysqld]
default-storage-engine = myisam
innodb = off
END
  invoke-rc.d mysql start
fi
  
    # Set root password
    passwd=$MYSQL_ROOT_PASSWORD
    mysqladmin password "$passwd"
}


function do_setup_webserver {
  if [ $INSTALL_NGINX = "1" ]
  then
    do_install_nginx
  fi

  if [ $INSTALL_PHP = "1" ]
  then
    do_install_php
  fi
  
  if [ $INSTALL_PHP_APC = "1" ]
  then
    do_install_php_apc
  fi
  

  if [ $INSTALL_MYSQL = "1" ]
  then
    do_install_mysql
  fi
}

########################################
# SETUP SECURITY SECTION
########################################

function do_change_ssh_port {
  echo "Set ssh port to: $SSHPORT"
  sed -i "/Port/cPort $SSHPORT" /etc/ssh/sshd_config
}

function do_install_firewall {
  echo "Install firewall"
  
  echo "create iptables rules in a file: /etc/iptables.up.rules "
  rm /etc/iptables.up.rules

  OPEN_TCP_PORTS_STR=""  
  NUMBER_OF_PORTS=${#FIREWALL_OPEN_PORTS[@]}
  LOOP_MAX=$(expr $NUMBER_OF_PORTS - 1)
  for PORT_INDEX in $(seq 0 $LOOP_MAX)
  do
        OPEN_PORT=${FIREWALL_OPEN_PORTS[$PORT_INDEX]}
        OPEN_TCP_PORTS_STR="$OPEN_TCP_PORTS_STR
# Open Port $OPEN_PORT
-A INPUT -p tcp --dport $OPEN_PORT -j ACCEPT
"
  done
    

  
  cat > /etc/iptables.up.rules <<END
*filter

#  Allows all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

#  Accepts all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

#  Allows all outbound traffic
-A OUTPUT -j ACCEPT

# Open TCP Posts
$OPEN_TCP_PORTS_STR

#  Allows SSH connections
# use this if iptables does not have recent module loaded
-A INPUT -p tcp --dport $SSHPORT -j ACCEPT

# Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# log iptables denied calls
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7

# Reject all other inbound - default deny unless explicitly allowed policy
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
END

    echo "flush iptables rules"
    iptables -F
    /sbin/iptables-restore < /etc/iptables.up.rules

    echo "apply rules on restart"
	#rm /etc/network/if-pre-up.d/iptables
	cat > /etc/network/if-pre-up.d/iptables <<END
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.up.rules
END

	#make it executable
	chmod +x /etc/network/if-pre-up.d/iptables
  
}

function do_disable_root_login {
  echo "Disable root login"
  sed -i "/PermitRootLogin/cPermitRootLogin no" /etc/ssh/sshd_config
}

function do_disable_password_login {
  echo "Disable password login"
  echo "Please setup SSH key pair before restarting the network/system"
  echo "Otherwise, you won't be able to login using a password"
  sed -i "/PasswordAuthentication/cPasswordAuthentication no" /etc/ssh/sshd_config
}


function do_setup_security {
  do_change_ssh_port

  if [ $INSTALL_FIREWALL = "1" ]
  then
    do_install_firewall
  fi

  if [ $DISABLE_ROOT_LOGIN = "1" ]
  then
    do_disable_root_login
  fi

  if [ $DISABLE_PASSWORD_LOGIN = "1" ]
  then
    do_disable_password_login
  fi

}

########################################################################
# MAIN PROGRAM
########################################################################

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
#checking
clear
check_sanity

if [ $SETUP_CLEAN_SYSTEM = "1" ]
then
  do_setup_cleanup_system
fi

if [ $SETUP_WEBSERVER = "1" ]
then
  do_setup_webserver
fi

if [ $SETUP_SECURITY = "1" ]
then
  do_setup_security
fi


echo "Done"