#!/bin/bash

set -e

INTERFACES="/etc/network/interfaces"
INTERFACES_D="/etc/network/interfaces.d"
EXTERNAL_LB_VIP_ADDRESS="__EXTERNAL_VIP_IP__"

PUBLIC_KEY="__PUBLIC_KEY__"
PRIVATE_KEY="__PRIVATE_KEY__"

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
echo $PUBLIC_KEY > .ssh/id_rsa.pub
echo $PUBLIC_KEY >> .ssh/authorized_keys
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
    address 172.29.232.__ID__
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
    address 172.29.236.__ID__
    netmask 255.255.252.0
    bridge_ports vxlan2
EOF

cat > ${INTERFACES_D}/eth4.cfg << "EOF"
auto eth4
iface eth4 inet static
    address 172.29.244.__ID__
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
iface br-vxlan inet manual
    bridge_ports vxlan3
EOF

ifup -a

echo "$PRIVATE_KEY" > .ssh/id_rsa
chmod 600 .ssh/*

cd /root
git clone -b __VERSION__ https://github.com/rcbops/ansible-lxc-rpc.git
cd ansible-lxc-rpc
pip install -r requirements.txt
cp -a etc/rpc_deploy /etc/
scripts/pw-token-gen.py --file /etc/rpc_deploy/user_variables.yml
echo "nova_virt_type: qemu" >> /etc/rpc_deploy/user_variables.yml

rpc_user_config="/etc/rpc_deploy/rpc_user_config.yml"
environment_version=$(md5sum /etc/rpc_deploy/rpc_environment.yml | awk '{print $1}')

curl -o $rpc_user_config https://raw.githubusercontent.com/mattt416/rpc_heat/master/rpc_user_config.yml
sed -i "s/__ENVIRONMENT_VERSION__/$environment_version/g" $rpc_user_config
sed -i "s/__EXTERNAL_LB_VIP_ADDRESS__/$EXTERNAL_LB_VIP_ADDRESS/g" $rpc_user_config

cd rpc_deployment
ansible-playbook -e @/etc/rpc_deploy/user_variables.yml playbooks/setup/host-setup.yml \
                                                        playbooks/infrastructure/haproxy-install.yml \
                                                        playbooks/infrastructure/infrastructure-setup.yml \
                                                        playbooks/openstack/openstack-setup.yml
