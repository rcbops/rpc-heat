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

# Partition Cloud Block Storage disk used by cinder and swift
if [ ! -b /dev/xvdf1 ]; then
    echo -e "n\np\n1\n\n\nw\n" | fdisk /dev/xvdf
fi

if [ "%%DEPLOY_SWIFT%%" = "yes" ]; then
    pvcreate /dev/xvdf1 || true
    vgcreate swift /dev/xvdf1 || true

    for DISK in disk1 disk2 disk3; do
        if [ ! mountpoint /srv/${DISK}]; then
            lvcreate -L 10G -n ${DISK} swift
            echo "/dev/swift/${DISK} /srv/${DISK} xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0" >> /etc/fstab
            mkfs.xfs -f /dev/swift/${DISK}
            mkdir -p /srv/${DISK}
            mount /srv/${DISK}
        fi
   done
fi

