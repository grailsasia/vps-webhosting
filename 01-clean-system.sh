#!/bin/bash

########################################################################
# This is a simple system clean up to reduce resource usage
#   should be the first item to run on a new server
#   works on debian and ubuntu, but not fully tested
########################################################################

########################################################################
# Parameters - please set accordingly to desired values 
########################################################################

# Disable getty instances?
DISABLE_GETTY=yes

# Yes if you want to repalce bash with dash - a lighter alternative
INSTALL_DASH=no

# Change timezone to default?
RECONFIGURE_TIMEZONE=yes
SERVER_TIMEZONE="Asia/Manila"






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

########################################################################
# MAIN PROGRAM
########################################################################

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
#checking
clear
check_sanity


do_install_favorite_programs
do_remove_unneeded
do_update_upgrade
do_install_syslogd

if [ $DISABLE_GETTY = "yes" ]
then
  do_disable_getty
fi

if [ $INSTALL_DASH = "yes" ]
then
  do_install_dash
fi

if [ $RECONFIGURE_TIMEZONE = "yes" ]
then
  do_reconfigure_timezone
fi

echo "Done"