#!/bin/bash

########################################################################
# This is a simple system clean up to reduce resource usage
#   should be the first item to run on a new server
#   works on debian and ubuntu, but not fully tested
########################################################################

########################################################################
# Parameters - please set accordingly to desired values 
########################################################################


# which port to connect to using ssh.  default is 22, 
# But try to use high number less than 65535, for obscurity 
SSHPORT=49999

# install a firewall
INSTALL_FIREWALL=yes

# list all ports you wish to open from the outsite world
declare -a FIREWALL_OPEN_PORTS=('80' '443');

# prevent ssh as root
DISABLE_ROOT_LOGIN=yes

# prevent password login.  All login will be by public key.
# Be sure to upload your public key to a server user's authorized_keys,
# otherwise access to your VPS will be lost.
DISABLE_PASSWORD_LOGIN=yes




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
  sed -i "/PasswordAuthentication/cPasswordAuthentication no" /etc/ssh/sshd_config
}

########################################################################
# MAIN PROGRAM
########################################################################

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
#checking
clear
check_sanity

do_change_ssh_port

if [ $INSTALL_FIREWALL = "yes" ]
then
  do_install_firewall
fi

if [ $DISABLE_ROOT_LOGIN = "yes" ]
then
  do_disable_root_login
fi

if [ $DISABLE_PASSWORD_LOGIN = "yes" ]
then
  do_disable_password_login
fi



echo "Done"