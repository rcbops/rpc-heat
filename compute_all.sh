found=0

for interface in eth2 eth3 eth4; do
  ifdown $interface
done

cat /etc/network/interfaces | while read line; do
  if echo "$line" | grep "# Label heat_"; then
    found=1
  fi

  if [ $found -eq 1 ] && [ "$line" = "" ]; then
    found=0
  fi

  if [ $found -eq 0 ]; then
    echo "$line" >> /etc/network/interfaces.tmp
  fi
done

echo "source /etc/network/interfaces.d/*.cfg" >> /etc/network/interfaces.tmp

mv -f /etc/network/interfaces.tmp /etc/network/interfaces

cat > /etc/network/interfaces.d/eth2.cfg << "EOF"
auto eth2
iface eth2 inet static
    address 172.29.232.$id
    netmask 255.255.252.0
EOF

cat > /etc/network/interfaces.d/vxlan2.cfg << "EOF"
auto vxlan2
iface vxlan2 inet manual
        pre-up ip link add vxlan2 type vxlan id 2 group 239.0.0.16 ttl 4 dev eth2
        up ip link set vxlan2 up
        down ip link set vxlan2 down
EOF

cat > /etc/network/interfaces.d/br-mgmt.cfg << "EOF"
auto br-mgmt
iface br-mgmt inet static
    address 172.29.236.$id
    netmask 255.255.252.0
    bridge_ports vxlan2
EOF

cat > /etc/network/interfaces.d/eth3.cfg << "EOF"
auto eth3
iface eth3 inet manual
EOF

cat > /etc/network/interfaces.d/vxlan3.cfg << "EOF"
auto vxlan3
iface vxlan3 inet manual
        pre-up ip link add vxlan3 type vxlan id 3 group 239.0.0.16 ttl 4 dev eth3
        up ip link set vxlan3 up
        down ip link set vxlan3 down
EOF

cat > /etc/network/interfaces.d/br-vxlan.cfg << "EOF"
auto br-vxlan
iface br-vxlan inet static
    address 172.29.240.$id
    netmask 255.255.252.0
    bridge_ports vxlan3
EOF

cat > /etc/network/interfaces.d/eth4.cfg << "EOF"
auto eth4
iface eth4 inet static
    address 172.29.244.$id
    netmask 255.255.252.0
EOF

cat > /etc/network/interfaces.d/br-storage.cfg << "EOF"
auto br-storage
iface br-storage inet manual
    bridge_ports eth4
EOF

cat > /etc/network/interfaces.d/br-vlan.cfg << "EOF"
auto br-vlan
iface br-vlan inet manual
    bridge_ports none
EOF

ifup -a

