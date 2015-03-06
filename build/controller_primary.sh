rpc_user_config="/etc/rpc_deploy/rpc_user_config.yml"
swift_config="/etc/rpc_deploy/conf.d/swift.yml"
user_variables="/etc/rpc_deploy/user_variables.yml"

DEPLOY_INFRASTRUCTURE=%%DEPLOY_INFRASTRUCTURE%%
DEPLOY_LOGGING=%%DEPLOY_LOGGING%%
DEPLOY_OPENSTACK=%%DEPLOY_OPENSTACK%%
DEPLOY_SWIFT=%%DEPLOY_SWIFT%%
DEPLOY_TEMPEST=%%DEPLOY_TEMPEST%%
DEPLOY_MONITORING=%%DEPLOY_MONITORING%%
GERRIT_REFSPEC=%%GERRIT_REFSPEC%%

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

if [ ! -e /root/os-ansible-deployment ]; then
  git clone -b %%OS_ANSIBLE_GIT_VERSION%% %%OS_ANSIBLE_GIT_REPO%% os-ansible-deployment
fi

cd os-ansible-deployment
if [ ! -z $GERRIT_REFSPEC ]; then
  # Git creates a commit while merging so identity must be set.
  git config --global user.name "Hot Hot Heat"
  git config --global user.email "flaming@li.ps"
  git fetch https://review.openstack.org/stackforge/os-ansible-deployment $GERRIT_REFSPEC
  git merge FETCH_HEAD
fi
pip install -r requirements.txt
cp -a etc/rpc_deploy /etc/

scripts/pw-token-gen.py --file $user_variables
echo "nova_virt_type: qemu" >> $user_variables
echo "lb_name: %%CLUSTER_PREFIX%%-node3" >> $user_variables

sed -i "s#\(rackspace_cloud_auth_url\): .*#\1: %%RACKSPACE_CLOUD_AUTH_URL%%#g" $user_variables
sed -i "s/\(rackspace_cloud_tenant_id\): .*/\1: %%RACKSPACE_CLOUD_TENANT_ID%%/g" $user_variables
sed -i "s/\(rackspace_cloud_username\): .*/\1: %%RACKSPACE_CLOUD_USERNAME%%/g" $user_variables
sed -i "s/\(rackspace_cloud_password\): .*/\1: %%RACKSPACE_CLOUD_PASSWORD%%/g" $user_variables
sed -i "s/\(rackspace_cloud_api_key\): .*/\1: %%RACKSPACE_CLOUD_API_KEY%%/g" $user_variables
sed -i "s/\(glance_default_store\): .*/\1: %%GLANCE_DEFAULT_STORE%%/g" $user_variables
sed -i "s/\(maas_notification_plan\): .*/\1: npTechnicalContactsEmail/g" $user_variables

if [ "%%DEPLOY_SWIFT%%" = "yes" ]; then
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

if [ "%%DEPLOY_SWIFT%%" = "yes" ]; then
  curl -o $swift_config "${raw_url}/%%HEAT_GIT_VERSION%%/swift.yml"
  sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $swift_config
else
  test -f $swift_config && rm $swift_config
fi

# here we run ansible using the run-playbooks script in the ansible repo
if [ "%%RUN_ANSIBLE%%" = "True" ]; then
  cd /root/os-ansible-deployment
  scripts/bootstrap-ansible.sh
  scripts/run-playbooks.sh
fi
