openstack_user_config="/etc/openstack_deploy/openstack_user_config.yml"
swift_config="/etc/openstack_deploy/conf.d/swift.yml"
user_variables="/etc/openstack_deploy/user_variables.yml"
user_secrets="/etc/openstack_deploy/user_secrets.yml"

DEPLOY_INFRASTRUCTURE=%%DEPLOY_INFRASTRUCTURE%%
DEPLOY_LOGGING=%%DEPLOY_LOGGING%%
DEPLOY_OPENSTACK=%%DEPLOY_OPENSTACK%%
DEPLOY_SWIFT=%%DEPLOY_SWIFT%%
DEPLOY_TEMPEST=%%DEPLOY_TEMPEST%%
DEPLOY_MONITORING=%%DEPLOY_MONITORING%%

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

if [ ! -e /root/os-ansible-deployment ]; then
  git clone -b %%OS_ANSIBLE_GIT_VERSION%% %%OS_ANSIBLE_GIT_REPO%% os-ansible-deployment
fi

cd os-ansible-deployment
pip install -r requirements.txt
cp -a etc/openstack_deploy /etc/

scripts/pw-token-gen.py --file $user_secrets
echo "nova_virt_type: qemu" >> $user_variables
echo "lb_name: %%CLUSTER_PREFIX%%-node3" >> $user_variables
# Temporary work-around otherwise we hit https://bugs.launchpad.net/neutron/+bug/1382064
# which results in tempest tests failing
echo "neutron_api_workers: 0" >> $user_variables
echo "neutron_rpc_workers: 0" >> $user_variables

echo "rackspace_cloud_auth_url: %%RACKSPACE_CLOUD_AUTH_URL%%" >> $user_variables
echo "rackspace_cloud_tenant_id: %%RACKSPACE_CLOUD_TENANT_ID%%" >> $user_variables
echo "rackspace_cloud_username: %%RACKSPACE_CLOUD_USERNAME%%" >> $user_variables
echo "rackspace_cloud_password: %%RACKSPACE_CLOUD_PASSWORD%%" >> $user_variables
echo "rackspace_cloud_api_key: %%RACKSPACE_CLOUD_API_KEY%%" >> $user_variables
echo "maas_notification_plan: npTechnicalContactsEmail" >> $user_variables

sed -i "s/\(glance_default_store\): .*/\1: %%GLANCE_DEFAULT_STORE%%/g" $user_variables

if [ "%%DEPLOY_SWIFT%%" = "yes" ]; then
  sed -i "s/\(glance_swift_store_auth_address\): .*/\1: '{{ keystone_service_internaluri }}'/" $user_secrets
  sed -i "s/\(glance_swift_store_key\): .*/\1: '{{ glance_service_password }}'/" $user_secrets
  sed -i "s/\(glance_swift_store_region\): .*/\1: RegionOne/" $user_secrets
  sed -i "s/\(glance_swift_store_user\): .*/\1: 'service:glance'/" $user_secrets
else
  sed -i "s/\(glance_swift_store_region\): .*/\1: %%GLANCE_SWIFT_STORE_REGION%%/g" $user_secrets
fi

environment_version=$(md5sum /etc/openstack_deploy/openstack_environment.yml | awk '{print $1}')

# if %%HEAT_GIT_REPO%% has .git at end (https://github.com/rcbops/rpc-heat.git),
# strip it off otherwise curl will 404
raw_url=$(echo %%HEAT_GIT_REPO%% | sed -e 's/\.git$//g' -e 's/github.com/raw.githubusercontent.com/g')

curl -o $openstack_user_config "${raw_url}/%%HEAT_GIT_VERSION%%/openstack_user_config.yml"
sed -i "s/__ENVIRONMENT_VERSION__/$environment_version/g" $openstack_user_config
sed -i "s/__EXTERNAL_VIP_IP__/%%EXTERNAL_VIP_IP%%/g" $openstack_user_config
sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $openstack_user_config

if [ "%%DEPLOY_SWIFT%%" = "yes" ]; then
  curl -o $swift_config "${raw_url}/%%HEAT_GIT_VERSION%%/swift.yml"
  sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $swift_config
fi

# here we run ansible using the run-playbooks script in the ansible repo
if [ "%%RUN_ANSIBLE%%" = "True" ]; then
  cd /root/os-ansible-deployment
  scripts/bootstrap-ansible.sh
  scripts/run-playbooks.sh
fi
