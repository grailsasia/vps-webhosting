#!/bin/bash

########################################################################
# This is a simple installation of LNMP Stack
#   Linux, Nginx, Mysql, PHP
#   works on debian and ubuntu, but not fully tested
########################################################################

########################################################################
# Parameters - please set accordingly to desired values 
########################################################################

# Install Nginx Webserver
INSTALL_NGINX=yes

# Number of cpu cores in your VPS/server.
# Will be used to configure nginx for optimum performance
NUMBER_OF_CPU_CORES=1

# How long will cache for a page be valid, 5m means 5 minutes
FASTCGI_CACHE_TIMEOUT=5m

# Install PHP
INSTALL_PHP=yes

# Advisable to set to yes if memory is 128mb or less
SET_PHP_LOWEND=yes

# Install MySQL
INSTALL_MYSQL=yes

# password of mysql root user
MYSQL_ROOT_PASSWORD=root

# Advisable to set to yes if memory is 256mb or less.
# Will disable innodb and tweak settings to decrease memory consumption 
SET_MYSQL_LOWEND=yes





########################################################################
# Common functions
########################################################################
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

########################################################################
# SYSTEM
########################################################################

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
    cat > /etc/nginx/global/wordpress.cache.conf <<END
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

    if [ $SET_PHP_LOWEND = "yes" ]
    then
        sed -i "/memory_limit/cmemory_limit = 32M" /etc/php5/fpm/php.ini
        sed -i "/pm.max_children/cpm.max_children = 2" /etc/php5/fpm/pool.d/www.conf
        sed -i "/pm.max_spare_servers/cpm.max_spare_servers = 2" /etc/php5/fpm/pool.d/www.conf
    fi

    echo "restart PHP"
    invoke-rc.d php5-fpm restart
}

function do_install_mysql {
    show_title "MySQL"
    # Install the MySQL packages
    check_install mysqld mysql-server
    check_install mysql mysql-client

if [ $SET_MYSQL_LOWEND = "yes" ]
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

########################################################################
# MAIN PROGRAM
########################################################################

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
#checking
clear
check_sanity

if [ $INSTALL_NGINX = "yes" ]
then
  do_install_nginx
fi

if [ $INSTALL_PHP = "yes" ]
then
  do_install_php
fi

if [ $INSTALL_MYSQL = "yes" ]
then
  do_install_mysql
fi


echo "Done"