#!/bin/bash

set -e

INTERFACES="/etc/network/interfaces"
INTERFACES_D="/etc/network/interfaces.d"
EXTERNAL_VIP_IP="$external_vip_ip"

PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCkouwNWE73SrUSWP7AxH+8WXI5LTgPOcSxEhmurqjwkakRXvelabQdnI6qhvhxxWnhtIfrw3ARNAUMNSzXq0MJAyjiKoJI/nSBfuTwq9QS8rjXm1iZ7KcHeNpS/H6nb8aJyzMO2fvVNQ4J6WYFyLPBH3pXDeSG+9sW8Fm2WUC8097H0r/mCW0+T8X3ftaUOFO85F54Eal4/4gG7EeYAYzdCTliFloyqi5/SLo2NqDUsPo+N448RyadR7rCqTyoCf2kHmmDzBSNBzW0YpfBtzRZWSnk8GRz+7UejkQlt/alnu2kRbt9Lx/ooRVDqHkBZhDDSFKHkEw4mL3Daadyxxuh root@heat-controller-1"

apt-get update
apt-get install -y bridge-utils git

cat > /etc/hosts << "EOF"
127.0.0.1 localhost
172.29.236.1 heat-controller-1
172.29.236.2 heat-controller-2
172.29.236.3 heat-controller-3
172.29.236.4 heat-compute-1
172.29.236.5 heat-compute-2
EOF

cd /root
echo $PUBKEY > .ssh/id_rsa.pub
echo $PUBKEY >> .ssh/authorized_keys
chmod 600 .ssh/*

found=0
found_private=0
tmp_file=$(mktemp)

for interface in eth1 eth2 eth3 eth4; do
  ifdown $interface
done

cat $INTERFACES | while read line; do
  if echo "$line" | grep "# Label heat_"; then
    found=1
  fi

  if echo "$line" | grep "# Label private"; then
    found_private=1
  fi

  if [ $found -eq 1 ] && [ "$line" = "" ]; then
    found=0
  fi

  if [ $found_private -eq 1 ] && [ "$line" = "" ]; then
    echo "bridge_ports eth1" >> ${INTERFACES_D}/br-snet.cfg
    found_private=0
  fi

  if [ $found -eq 0 ] && [ $found_private -eq 0 ]; then
    echo "$line" >> $tmp_file
  fi

  if [ $found_private -eq 1 ]; then
    echo "$line" | sed -e 's/eth1/br-snet/g' >> ${INTERFACES_D}/br-snet.cfg
  fi
done

echo "source ${INTERFACES_D}/*.cfg" >> $tmp_file

mv -f $tmp_file ${INTERFACES}

cat > ${INTERFACES_D}/eth1.cfg << "EOF"
auto eth1
iface eth1 inet manual
EOF

cat > ${INTERFACES_D}/eth2.cfg << "EOF"
auto eth2
iface eth2 inet static
    address 172.29.232.$id
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
    address 172.29.236.$id
    netmask 255.255.252.0
    bridge_ports vxlan2
EOF

cat > ${INTERFACES_D}/eth4.cfg << "EOF"
auto eth4
iface eth4 inet static
    address 172.29.244.$id
    netmask 255.255.252.0
EOF

cat > ${INTERFACES_D}/br-storage.cfg << "EOF"
auto br-storage
iface br-storage inet manual
    bridge_ports eth4
EOF

cat > ${INTERFACES_D}/br-vlan.cfg << "EOF"
auto br-vlan
iface br-vlan inet manual
    bridge_ports none
EOF

ifup -a

