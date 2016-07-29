#!/bin/bash

set -e

export HOME=${HOME:-"/root"}
export DEPLOY_CEPH=%%DEPLOY_CEPH%%
export CEPH_NODE_COUNT=%%CEPH_NODE_COUNT%%

INTERFACES="/etc/network/interfaces"
INTERFACES_D="/etc/network/interfaces.d"

apt-get update
apt-get install -y python-dev python-pip bridge-utils git lvm2 vim xfsprogs

# Add trailing newline to file
echo >> /etc/ssh/sshd_config

cat > /etc/hosts << "EOF"
127.0.0.1 localhost
172.29.236.1 %%CLUSTER_PREFIX%%-node1
172.29.236.2 %%CLUSTER_PREFIX%%-node2
172.29.236.3 %%CLUSTER_PREFIX%%-node3
172.29.236.4 %%CLUSTER_PREFIX%%-node4
172.29.236.5 %%CLUSTER_PREFIX%%-node5
EOF
if [ $DEPLOY_CEPH == "yes" ] && [ $CEPH_NODE_COUNT -gt 0 ]; then
  last_ceph_node=$(($CEPH_NODE_COUNT-1))
  for x in $(seq 0 $last_ceph_node); do
    echo "172.29.236.2$x %%CLUSTER_PREFIX%%-node2$x" >> /etc/hosts
  done
fi

cd /root
echo -n "%%PUBLIC_KEY%%" > .ssh/id_rsa.pub
echo -n "%%PUBLIC_KEY%%" >> .ssh/authorized_keys
chmod 600 .ssh/*

for interface in eth1 eth2 eth3 eth4; do
  ifdown $interface
done

# Convert private network config into br-snet config and write to br-snet.cfg
sed -n '/Label private/,/^$/ {
          s/eth1/br-snet/
          s/^$/    bridge_ports eth1/
          p
        }' ${INTERFACES} > ${INTERFACES_D}/br-snet.cfg

# Write public network config into eth0.cfg
sed -n '/Label public/,/^$/p' $INTERFACES > ${INTERFACES_D}/eth0.cfg

# write new interfaces file with loopback and source line only
cat >${INTERFACES} <<EOF
# The loopback network interface
auto lo
iface lo inet loopback

source ${INTERFACES_D}/*.cfg
EOF

cat > ${INTERFACES_D}/eth1.cfg << "EOF"
auto eth1
iface eth1 inet manual
EOF

cat > ${INTERFACES_D}/eth2.cfg << "EOF"
auto eth2
iface eth2 inet static
    address 172.29.232.%%ID%%
    netmask 255.255.252.0
EOF

cat > ${INTERFACES_D}/vxlan2.cfg << "EOF"
auto vxlan2
iface vxlan2 inet manual
        pre-up ip link add vxlan2 type vxlan id 2 group 239.0.0.16 ttl 4 dev eth2
        up ip link set vxlan2 up
        down ip link set vxlan2 down
EOF

cat > ${INTERFACES_D}/br-mgmt.cfg << "EOF"
auto br-mgmt
iface br-mgmt inet static
    address 172.29.236.%%ID%%
    netmask 255.255.252.0
    bridge_ports vxlan2
EOF

cat > ${INTERFACES_D}/eth4.cfg << "EOF"
auto eth4
iface eth4 inet static
    address 172.29.228.%%ID%%
    netmask 255.255.252.0
EOF

cat > ${INTERFACES_D}/vxlan4.cfg << "EOF"
auto vxlan4
iface vxlan4 inet manual
        pre-up ip link add vxlan4 type vxlan id 4 group 239.0.0.16 ttl 4 dev eth4
        up ip link set vxlan4 up
        down ip link set vxlan4 down
EOF

cat > ${INTERFACES_D}/vxlan5.cfg << "EOF"
# We don't have a dedicated network for this traffic, so we piggy-back on eth4
auto vxlan5
iface vxlan5 inet manual
        pre-up ip link add vxlan5 type vxlan id 5 group 239.0.0.16 ttl 4 dev eth4
        up ip link set vxlan5 up
        down ip link set vxlan5 down
EOF

cat > ${INTERFACES_D}/br-storage.cfg << "EOF"
auto br-storage
iface br-storage inet static
    address 172.29.244.%%ID%%
    netmask 255.255.252.0
    bridge_ports vxlan4
EOF

cat > ${INTERFACES_D}/br-vlan.cfg << "EOF"
auto br-vlan
iface br-vlan inet manual
    bridge_ports vxlan5
EOF

ifup -a
cat > ${INTERFACES_D}/eth3.cfg << "EOF"
auto eth3
iface eth3 inet manual
EOF

cat > ${INTERFACES_D}/vxlan3.cfg << "EOF"
auto vxlan3
iface vxlan3 inet manual
        pre-up ip link add vxlan3 type vxlan id 3 group 239.0.0.16 ttl 4 dev eth3
        up ip link set vxlan3 up
        down ip link set vxlan3 down
EOF

cat > ${INTERFACES_D}/br-vxlan.cfg << "EOF"
auto br-vxlan
iface br-vxlan inet static
    address 172.29.240.%%ID%%
    netmask 255.255.252.0
    bridge_ports vxlan3
EOF

ifup -a

# Partition Cloud Block Storage disk used by cinder and swift
fdisk /dev/xvdf << EOF
n
p
1


w
EOF

pvcreate /dev/xvdf1
vgcreate cinder-volumes /dev/xvdf1

%%CURL_CLI%% --data-binary '{"status": "SUCCESS"}'
