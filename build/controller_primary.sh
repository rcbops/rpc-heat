checkout_dir="/opt"
config_dir="/etc/openstack_deploy"
openstack_user_config="${config_dir}/openstack_user_config.yml"
swift_config="${config_dir}/conf.d/swift.yml"
user_variables="${config_dir}/user_variables.yml"
user_secrets="${config_dir}/user_secrets.yml"

DEPLOY_LOGGING=%%DEPLOY_LOGGING%%
DEPLOY_OPENSTACK=%%DEPLOY_OPENSTACK%%
DEPLOY_SWIFT=%%DEPLOY_SWIFT%%
DEPLOY_TEMPEST=%%DEPLOY_TEMPEST%%
DEPLOY_MONITORING=%%DEPLOY_MONITORING%%
GERRIT_REFSPEC=%%GERRIT_REFSPEC%%
OS_ANSIBLE_GIT_VERSION=%%OS_ANSIBLE_GIT_VERSION%%

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

cd $checkout_dir

if [ ! -e ${checkout_dir}/rpc-openstack ]; then
  git clone -b %%RPC_OPENSTACK_GIT_VERSION%% %%RPC_OPENSTACK_GIT_REPO%%
fi

cd ${checkout_dir}/rpc-openstack
if [ ! -z $OS_ANSIBLE_GIT_VERSION ]; then
  rm .gitmodules
  git rm os-ansible-deployment
  git submodule add %%OS_ANSIBLE_GIT_REPO%%
fi
git submodule init
git submodule update

pushd os-ansible-deployment
  git checkout $OS_ANSIBLE_GIT_VERSION

  if [ ! -z $GERRIT_REFSPEC ]; then
    # Git creates a commit while merging so identity must be set.
    git config --global user.name "Hot Hot Heat"
    git config --global user.email "flaming@li.ps"
    git fetch https://review.openstack.org/stackforge/os-ansible-deployment $GERRIT_REFSPEC
    git merge FETCH_HEAD
  fi

  scripts/bootstrap-ansible.sh
  cp -a etc/openstack_deploy /etc/

  echo "nova_virt_type: qemu" >> $user_variables
  sed -i "s/\(glance_default_store\): .*/\1: %%GLANCE_DEFAULT_STORE%%/g" $user_variables

  environment_version=$(md5sum ${config_dir}/openstack_environment.yml | awk '{print $1}')
  # if %%HEAT_GIT_REPO%% has .git at end (https://github.com/rcbops/rpc-heat.git),
  # strip it off otherwise curl will 404
  raw_url=$(echo %%HEAT_GIT_REPO%% | sed -e 's/\.git$//g' -e 's/github.com/raw.githubusercontent.com/g')

  curl -o $openstack_user_config "${raw_url}/%%HEAT_GIT_VERSION%%/openstack_user_config.yml"
  sed -i "s/__ENVIRONMENT_VERSION__/$environment_version/g" $openstack_user_config
  sed -i "s/__EXTERNAL_VIP_IP__/%%EXTERNAL_VIP_IP%%/g" $openstack_user_config
  sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $openstack_user_config

  if [ "$DEPLOY_SWIFT" = "yes" ]; then
    curl -o $swift_config "${raw_url}/%%HEAT_GIT_VERSION%%/swift.yml"
    sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $swift_config

    sed -i "s/#\(glance_swift_store_auth_address\): .*/\1: '{{ keystone_service_internalurl }}'/" $user_variables
    sed -i "s/#\(glance_swift_store_user\): .*/\1: 'service:glance'/" $user_variables
    sed -i "s/#\(glance_swift_store_key\): .*/\1: '{{ glance_service_password }}'/" $user_variables
    sed -i "s/#\(glance_swift_store_region\): .*/\1: RegionOne/" $user_variables
  else
    sed -i "s/#\(glance_swift_store_auth_address\): .*/\1: '{{ rackspace_cloud_auth_url }}'/" $user_variables
    sed -i "s/#\(glance_swift_store_user\): .*/\1: '{ rackspace_cloud_tenant_id }}:{{ rackspace_cloud_username }}'/" $user_variables
    sed -i "s/#\(glance_swift_store_key\): .*/\1: '{{ rackspace_cloud_password }}'/" $user_variables
    sed -i "s/#\(glance_swift_store_region\): .*/\1: %%GLANCE_SWIFT_STORE_REGION%%/g" $user_variables

    test -f $swift_config && rm $swift_config
  fi

  scripts/pw-token-gen.py --file $user_secrets
popd

pushd rpcd
  cp -a etc/openstack_deploy/* $config_dir

  sed -i "s/\(maas_notification_plan\): .*/\1: npTechnicalContactsEmail/" ${config_dir}/user_extras_variables.yml
  # The primary IPv4 is more consistently available on access_ip1_v4 than public0_v4
  sed -i "s/\(maas_target_alias\): .*/\1: access_ip1_v4/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(lb_name\): .*/\1: %%CLUSTER_PREFIX%%-node3/" ${config_dir}/user_extras_variables.yml
  sed -i "s@\(rackspace_cloud_auth_url\): .*@\1: %%RACKSPACE_CLOUD_AUTH_URL%%@" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_tenant_id\): .*/\1: %%RACKSPACE_CLOUD_TENANT_ID%%/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_username\): .*/\1: %%RACKSPACE_CLOUD_USERNAME%%/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_password\): .*/\1: %%RACKSPACE_CLOUD_PASSWORD%%/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_api_key\): .*/\1: %%RACKSPACE_CLOUD_API_KEY%%/" ${config_dir}/user_extras_variables.yml

  ${checkout_dir}/rpc-openstack/os-ansible-deployment/scripts/pw-token-gen.py --file ${config_dir}/user_extras_secrets.yml
popd

# here we run ansible using the run-playbooks script in the ansible repo
if [ "%%RUN_ANSIBLE%%" = "True" ]; then
  cd ${checkout_dir}/rpc-openstack/os-ansible-deployment
  scripts/run-playbooks.sh
  pushd ${checkout_dir}/rpc-openstack/rpcd/playbooks
    openstack-ansible repo-build.yml
    openstack-ansible repo-pip-setup.yml
    if [ "$DEPLOY_MONITORING" = "yes" ]; then
      openstack-ansible setup-maas.yml
    fi
  popd
  if [ "%%RUN_TEMPEST%%" = "True" ]; then
    export TEMPEST_SCRIPT_PARAMETERS="%%TEMPEST_SCRIPT_PARAMETERS%%"
    scripts/run-tempest.sh
  fi
fi
