#!/bin/bash

set -e

export HOME=${HOME:-"/root"}

ANSIBLE_PLAYBOOKS="%%ANSIBLE_PLAYBOOKS%%"

INTERFACES="/etc/network/interfaces"
INTERFACES_D="/etc/network/interfaces.d"
SWIFT_ENABLED=0

if echo "$ANSIBLE_PLAYBOOKS" | grep "swift"; then
  SWIFT_ENABLED=1
fi

if echo "$ANSIBLE_PLAYBOOKS" | grep "tempest"; then
  TEMPEST_ENABLED=1
fi

if [ "%%RUN_ANSIBLE%%" = "True" ]; then
  RUN_ANSIBLE=1
else
  RUN_ANSIBLE=0
fi

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

cd /root
echo -n "%%PUBLIC_KEY%%" > .ssh/id_rsa.pub
echo -n "%%PUBLIC_KEY%%" >> .ssh/authorized_keys
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
iface br-vxlan inet manual
    bridge_ports vxlan3
EOF

ifup -a

if [ $SWIFT_ENABLED -eq 1 ]; then
  pvcreate /dev/xvde1
  vgcreate swift /dev/xvde1

  for DISK in disk1 disk2 disk3; do
    lvcreate -L 10G -n ${DISK} swift
    echo "/dev/swift/${DISK} /srv/${DISK} xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0" >> /etc/fstab
    mkfs.xfs -f /dev/swift/${DISK}
    mkdir -p /srv/${DISK}
    mount /srv/${DISK}
  done
fi

rpc_user_config="/etc/rpc_deploy/rpc_user_config.yml"
swift_config="/etc/rpc_deploy/conf.d/swift.yml"
user_variables="/etc/rpc_deploy/user_variables.yml"

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

if [ ! -e /root/os-ansible-deployment ]; then
  git clone -b %%RPC_GIT_VERSION%% %%RPC_GIT_REPO%% os-ansible-deployment
fi

cd os-ansible-deployment
pip install -r requirements.txt
cp -a etc/rpc_deploy /etc/

scripts/pw-token-gen.py --file $user_variables
echo "nova_virt_type: qemu" >> $user_variables

sed -i "s#\(rackspace_cloud_auth_url\): .*#\1: %%RACKSPACE_CLOUD_AUTH_URL%%#g" $user_variables
sed -i "s/\(rackspace_cloud_tenant_id\): .*/\1: %%RACKSPACE_CLOUD_TENANT_ID%%/g" $user_variables
sed -i "s/\(rackspace_cloud_username\): .*/\1: %%RACKSPACE_CLOUD_USERNAME%%/g" $user_variables
sed -i "s/\(rackspace_cloud_password\): .*/\1: %%RACKSPACE_CLOUD_PASSWORD%%/g" $user_variables
sed -i "s/\(rackspace_cloud_api_key\): .*/\1: %%RACKSPACE_CLOUD_API_KEY%%/g" $user_variables
sed -i "s/\(glance_default_store\): .*/\1: %%GLANCE_DEFAULT_STORE%%/g" $user_variables

if [ $SWIFT_ENABLED -eq 1 ]; then
  sed -i "s/\(glance_swift_store_auth_address\): .*/\1: '{{ auth_identity_uri }}'/" $user_variables
  sed -i "s/\(glance_swift_store_key\): .*/\1: '{{ glance_service_password }}'/" $user_variables
  sed -i "s/\(glance_swift_store_region\): .*/\1: RegionOne/" $user_variables
  sed -i "s/\(glance_swift_store_user\): .*/\1: 'service:glance'/" $user_variables
else
  sed -i "s/\(glance_swift_store_region\): .*/\1: %%GLANCE_SWIFT_STORE_REGION%%/g" $user_variables
fi

cat >> $user_variables << EOF
apt_common_repos:
  - { repo: "deb http://ftp.hosteurope.de/mirror/archive.mariadb.org/mariadb-5.5.41/repo/ubuntu/ {{ ansible_distribution_release }} main", state: "present" }
EOF

environment_version=$(md5sum /etc/rpc_deploy/rpc_environment.yml | awk '{print $1}')

# if %%HEAT_GIT_REPO%% has .git at end (https://github.com/mattt416/rpc_heat.git),
# strip it off otherwise curl will 404
raw_url=$(echo %%HEAT_GIT_REPO%% | sed -e 's/\.git$//g' -e 's/github.com/raw.githubusercontent.com/g')

curl -o $rpc_user_config "${raw_url}/%%HEAT_GIT_VERSION%%/rpc_user_config.yml"
sed -i "s/__ENVIRONMENT_VERSION__/$environment_version/g" $rpc_user_config
sed -i "s/__EXTERNAL_VIP_IP__/%%EXTERNAL_VIP_IP%%/g" $rpc_user_config
sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $rpc_user_config

if [ $SWIFT_ENABLED -eq 1 ]; then
  curl -o $swift_config "${raw_url}/%%HEAT_GIT_VERSION%%/swift.yml"
  sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $swift_config
fi

# here we create a separate script incase run_ansible paramater is false and
# you want to re-run the correct set of playbooks at a later time
cd rpc_deployment
cat >> run_ansible.sh << "EOF"
#!/bin/bash

set -e

function retry()
{
  local n=1
  local try=$1
  local cmd="${@: 2}"

  until [[ $n -gt $try ]]
  do
    echo "attempt number $n:"
    $cmd && break || {
      echo "Command Failed..."
      ((n++))
      sleep 1;
    }
  done
}

user_variables=${user_variables:-"/etc/rpc_deploy/user_variables.yml"}

timeout=$(($(date +%s) + 300))

until ansible hosts -m ping > /dev/null 2>&1; do
  if [ $(date +%s) -gt $timeout ]; then
    echo "Timed out waiting for nodes to become accessible ..."
    exit 1
  fi
done

retry 3 ansible-playbook -e @${user_variables} playbooks/setup/host-setup.yml
retry 3 ansible-playbook -e @${user_variables} playbooks/infrastructure/haproxy-install.yml
EOF

if echo "$ANSIBLE_PLAYBOOKS" | grep "all"; then
  cat >> run_ansible.sh << "EOF"
retry 3 ansible-playbook -e @${user_variables} playbooks/infrastructure/infrastructure-setup.yml \
                                               playbooks/openstack/openstack-setup.yml
EOF
fi

if echo "$ANSIBLE_PLAYBOOKS" | grep "minimal"; then
  cat >> run_ansible.sh << "EOF"
egrep -v 'rpc-support-all.yml|rsyslog-config.yml' playbooks/openstack/openstack-setup.yml > \
                                                  playbooks/openstack/openstack-setup-no-logging.yml
retry 3 ansible-playbook -e @${user_variables} playbooks/infrastructure/memcached-install.yml \
                                               playbooks/infrastructure/galera-install.yml \
                                               playbooks/infrastructure/rabbit-install.yml
retry 3 ansible-playbook -e @${user_variables} playbooks/openstack/openstack-setup-no-logging.yml
EOF
fi

if [ $SWIFT_ENABLED -eq 1 ]; then
  cat >> run_ansible.sh << "EOF"
retry 3 ansible-playbook -e @${user_variables} playbooks/openstack/swift-all.yml
EOF
fi

if [ $TEMPEST_ENABLED -eq 1 ]; then
  cat >> run_ansible.sh << "EOF"
retry 3 ansible-playbook -e @${user_variables} playbooks/openstack/tempest.yml
EOF
fi

if [ $RUN_ANSIBLE -eq 1 ]; then
  bash run_ansible.sh
fi
%%CURL_CLI%% --data-binary '{"status": "SUCCESS"}'
