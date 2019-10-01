#!/bin/bash

###############################################################################
# 
#  This is a simple VPS setup for webserver.
#     should/could work on debian 6 and ubuntu 10.04 to 12.04 
#
###############################################################################


########################################
# SETUP SECURITY SECTION
########################################

SSHPORT=55188
declare -a FIREWALL_OPEN_PORTS=('80' '443');

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
    check_install git-core git-core
    
    updatedb
}

function do_remove_unneeded {
    echo "Remove un-needed programs"
    # Some Debian have portmap installed. We don't need that.
    echo "Remove portmap"
    check_remove /sbin/portmap portmap

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

function do_setup_cleanup_system {
  do_install_favorite_programs
  do_update_upgrade

  timedatectl set-timezone "Asia/Manila"
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
  do_install_firewall
  do_disable_root_login
  do_disable_password_login

  echo "
#Allow DSS keys
PubkeyAcceptedKeyTypes=+ssh-dss
" >> /etc/ssh/sshd_config

  iptables -F
  echo "Restart the system later for the changes to take effect."
}

########################################################################
# MAIN PROGRAM
########################################################################

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
#checking
clear
check_sanity

do_setup_cleanup_system
do_setup_security


echo "Done"
