rpc_user_config="/etc/rpc_deploy/rpc_user_config.yml"
user_variables="/etc/rpc_deploy/user_variables.yml"

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

cd /root
git clone -b %%RPC_VERSION%% %%GIT_REPO%% ansible-lxc-rpc
cd ansible-lxc-rpc
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
sed -i "s/\(glance_swift_store_region\): .*/\1: %%GLANCE_SWIFT_STORE_REGION%%/g" $user_variables

environment_version=$(md5sum /etc/rpc_deploy/rpc_environment.yml | awk '{print $1}')

curl -o $rpc_user_config https://raw.githubusercontent.com/mattt416/rpc_heat/master/rpc_user_config.yml
sed -i "s/__ENVIRONMENT_VERSION__/$environment_version/g" $rpc_user_config
sed -i "s/__EXTERNAL_VIP_IP__/%%EXTERNAL_VIP_IP%%/g" $rpc_user_config
sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $rpc_user_config

cd rpc_deployment
ansible-playbook -e @${user_variables} playbooks/setup/host-setup.yml
ansible-playbook -e @${user_variables} playbooks/infrastructure/haproxy-install.yml
if [ "$ANSIBLE_PLAYBOOKS" = "all" ]; then
  ansible-playbook -e @${user_variables} playbooks/infrastructure/infrastructure-setup.yml \
                                         playbooks/openstack/openstack-setup.yml
else
  ansible-playbook -e @${user_variables} playbooks/infrastructure/memcached-install.yml \
                                         playbooks/infrastructure/galera-install.yml \
                                         playbooks/infrastructure/rabbit-install.yml
  ansible-playbook -e @${user_variables} playbooks/openstack/keystone-all.yml \
                                         playbooks/openstack/glance-all.yml \
                                         playbooks/openstack/heat-all.yml \
                                         playbooks/openstack/nova-all.yml \
                                         playbooks/openstack/neutron-all.yml \
                                         playbooks/openstack/cinder-all.yml \
                                         playbooks/openstack/horizon-all.yml \
                                         playbooks/openstack/utility-all.yml
fi
