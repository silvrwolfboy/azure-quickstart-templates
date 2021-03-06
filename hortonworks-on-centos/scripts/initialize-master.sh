#!/bin/bash
IPPREFIX=$1
NAMEPREFIX=$2
NAMESUFFIX=$3
NAMENODES=$4
DATANODES=$5
ADMINUSER=$6

# Converts a domain like machine.domain.com to domain.com by removing the machine name
NAMESUFFIX=`echo $NAMESUFFIX | sed 's/^[^.]*\.//'`

#disable the need for a tty when running sudo
sed -i '/Defaults[[:space:]]\+!*requiretty/s/^/#/' /etc/sudoers

#use the key from the key vault as the SSH private key
openssl rsa -in /var/lib/waagent/*.prv -out /home/$ADMINUSER/.ssh/id_rsa
chmod 600 /home/$ADMINUSER/.ssh/id_rsa
chown $ADMINUSER /home/$ADMINUSER/.ssh/id_rsa

# Disable SELinux
/usr/sbin/setenforce 0
sed -i s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config

# Do not start iptables on boot
chkconfig iptables off

# Start ntpd on boot
chkconfig ntpd on 

# Install ambari
sudo yum install -y epel-release
sudo wget http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.0.0/ambari.repo
sudo cp ambari.repo /etc/yum.repos.d
sudo rm -f ambari.repo
sudo yum install -y ambari-server
sudo yum install -y ambari-agent
sudo ambari-server setup -s

# Format and mount the disks
let i=0 || true
for disk in $(sfdisk -l | grep "Disk /dev/sd[^ab]" | sed -r "s/Disk (\/dev\/sd.):.*$/\1/");
do
  sh ./mountDisk.sh $disk $i 0</dev/null & 
  let i=(i + 1) || true
done
wait

# Format the node IPs and setup the node
let "MASTERNODES=NAMENODES+1"

MASTER_NODES=()
for i in $(seq 1 $MASTERNODES)
do 
  let "IP=i+8"
  MASTER_NODES+=("$IPPREFIX$IP")
done
IFS=',';MASTER_NODE_IPS="${MASTER_NODES[*]}";IFS=$' \t\n'

WORKER_NODES=()
for i in $(seq 1 $DATANODES)
do 
  let "IP=i+19"
  WORKER_NODES+=("$IPPREFIX$IP")
done
IFS=',';WORKER_NODE_IPS="${WORKER_NODES[*]}";IFS=$' \t\n'

sudo python vm-bootstrap.py --action 'bootstrap' --cluster_id $NAMEPREFIX --scenario_id 'evaluation' --num_masters $MASTERNODES --num_workers $DATANODES --master_prefix "$NAMEPREFIX-mn-" --worker_prefix "$NAMEPREFIX-wn-" --domain_name ".$NAMESUFFIX" --admin_password 'admin' --masters_iplist $MASTER_NODE_IPS --workers_iplist $WORKER_NODE_IPS --id_padding 1
