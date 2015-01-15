rpc_user_config="/etc/rpc_deploy/rpc_user_config.yml"
swift_config="/etc/rpc_deploy/conf.d/swift.yml"
user_variables="/etc/rpc_deploy/user_variables.yml"

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

git clone -b %%RPC_GIT_VERSION%% %%RPC_GIT_REPO%% ansible-lxc-rpc
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

if [ $SWIFT_ENABLED -eq 1 ]; then
  sed -i "s/\(glance_swift_store_auth_address\): .*/\1: '{{ auth_identity_uri }}'/" $user_variables
  sed -i "s/\(glance_swift_store_key\): .*/\1: '{{ glance_service_password }}'/" $user_variables
  sed -i "s/\(glance_swift_store_region\): .*/\1: RegionOne/" $user_variables
  sed -i "s/\(glance_swift_store_user\): .*/\1: 'service:glance'/" $user_variables
else
  sed -i "s/\(glance_swift_store_region\): .*/\1: %%GLANCE_SWIFT_STORE_REGION%%/g" $user_variables
fi

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

if [ $RUN_ANSIBLE -eq 1 ]; then
  cd rpc_deployment
  retry 3 ansible-playbook -e @${user_variables} playbooks/setup/host-setup.yml
  retry 3 ansible-playbook -e @${user_variables} playbooks/infrastructure/haproxy-install.yml

  if [ "$ANSIBLE_PLAYBOOKS" = "all" ] || [ "$ANSIBLE_PLAYBOOKS" = "all+swift" ]; then
    retry 3 ansible-playbook -e @${user_variables} playbooks/infrastructure/infrastructure-setup.yml \
                                                   playbooks/openstack/openstack-setup.yml
  fi

  if [ "$ANSIBLE_PLAYBOOKS" = "minimal" ] || [ "$ANSIBLE_PLAYBOOKS" = "minimal+swift" ]; then
    egrep -v 'rpc-support-all.yml|rsyslog-config.yml' playbooks/openstack/openstack-setup.yml > \
                                                      playbooks/openstack/openstack-setup-no-logging.yml
    retry 3 ansible-playbook -e @${user_variables} playbooks/infrastructure/memcached-install.yml \
                                                   playbooks/infrastructure/galera-install.yml \
                                                   playbooks/infrastructure/rabbit-install.yml
    retry 3 ansible-playbook -e @${user_variables} playbooks/openstack/openstack-setup-no-logging.yml
  fi

  if [ $SWIFT_ENABLED -eq 1 ]; then
    retry 3 ansible-playbook -e @${user_variables} playbooks/openstack/swift-all.yml
  fi
fi
