checkout_dir="/opt"
config_dir="/etc/openstack_deploy"
openstack_user_config="${config_dir}/openstack_user_config.yml"
swift_config="${config_dir}/conf.d/swift.yml"
user_variables="${config_dir}/user_variables.yml"
user_secrets="${config_dir}/user_secrets.yml"
ceph_config="${config_dir}/conf.d/ceph.yml"
cinder_ceph_config="${config_dir}/conf.d/cinder_ceph.yml"
cinder_lvm_config="${config_dir}/conf.d/cinder_lvm.yml"

export DEPLOY_LOGGING=%%DEPLOY_LOGGING%%
export DEPLOY_OPENSTACK=%%DEPLOY_OPENSTACK%%
export DEPLOY_SWIFT=%%DEPLOY_SWIFT%%
export DEPLOY_TEMPEST=%%DEPLOY_TEMPEST%%
export DEPLOY_MONITORING=%%DEPLOY_MONITORING%%
export TEST_MONITORING=%%TEST_MONITORING%%
export GERRIT_REFSPEC=%%GERRIT_REFSPEC%%
export OS_ANSIBLE_GIT_VERSION=%%OS_ANSIBLE_GIT_VERSION%%

echo -n "%%PRIVATE_KEY%%" > .ssh/id_rsa
chmod 600 .ssh/*

cd $checkout_dir

# clone parent repo, but don't initialise submodule yet
if [ ! -e ${checkout_dir}/rpc-openstack ]; then
  git clone -b %%RPC_OPENSTACK_GIT_VERSION%% %%RPC_OPENSTACK_GIT_REPO%%
fi

cd ${checkout_dir}/rpc-openstack

# if we want to use a different submodule repo/sha
if [ ! -z $OS_ANSIBLE_GIT_VERSION ]; then
  git config --file=.gitmodules submodule.openstack-ansible.url %%OS_ANSIBLE_GIT_REPO%%
  git submodule update --init
  pushd openstack-ansible
    git checkout $OS_ANSIBLE_GIT_VERSION
  popd
# otherwise just use the submodule sha specified by parent
else
  git submodule update --init
fi

pushd openstack-ansible

  if [ ! -z $GERRIT_REFSPEC ]; then
    # Git creates a commit while merging so identity must be set.
    git config --global user.name "Hot Hot Heat"
    git config --global user.email "flaming@li.ps"
    git fetch https://review.openstack.org/openstack/openstack-ansible $GERRIT_REFSPEC
    git merge FETCH_HEAD
  fi

  scripts/bootstrap-ansible.sh
  cp -a etc/openstack_deploy /etc/

  echo "nova_virt_type: qemu" >> $user_variables
  echo "keystone_wsgi_processes: 4" >> $user_variables
  echo "neutron_l2_population: True" >> $user_variables
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
  if [ "$DEPLOY_CEPH" = "yes" ]; then
    curl -o $cinder_ceph_config "${raw_url}/%%HEAT_GIT_VERSION%%/cinder_ceph.yml"
    sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $cinder_ceph_config
    echo "cinder_ceph_client_uuid:" >> $user_secrets
    sed -i "s/#\(nova_libvirt_images_rbd_pool\): .*/\1: vms/" $user_variables
  else
    curl -o $cinder_lvm_config "${raw_url}/%%HEAT_GIT_VERSION%%/cinder_lvm.yml"
    sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $cinder_lvm_config
  fi

  scripts/pw-token-gen.py --file $user_secrets
popd

pushd rpcd
  cp -a etc/openstack_deploy/{env.d/,user_extras*.yml} $config_dir
  ../scripts/update-yaml.py $user_variables etc/openstack_deploy/user_variables.yml

  sed -i "s/\(maas_notification_plan\): .*/\1: npTechnicalContactsEmail/" ${config_dir}/user_extras_variables.yml
  # The primary IPv4 is more consistently available on access_ip1_v4 than public0_v4
  sed -i "s/\(maas_target_alias\): .*/\1: access_ip1_v4/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(lb_name\): .*/\1: %%CLUSTER_PREFIX%%-node3/" ${config_dir}/user_extras_variables.yml
  sed -i "s@\(rackspace_cloud_auth_url\): .*@\1: %%RACKSPACE_CLOUD_AUTH_URL%%@" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_tenant_id\): .*/\1: %%RACKSPACE_CLOUD_TENANT_ID%%/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_username\): .*/\1: %%RACKSPACE_CLOUD_USERNAME%%/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_password\): .*/\1: %%RACKSPACE_CLOUD_PASSWORD%%/" ${config_dir}/user_extras_variables.yml
  sed -i "s/\(rackspace_cloud_api_key\): .*/\1: %%RACKSPACE_CLOUD_API_KEY%%/" ${config_dir}/user_extras_variables.yml
  if [ "$DEPLOY_CEPH" = "yes" ]; then
    curl -o $ceph_config "${raw_url}/%%HEAT_GIT_VERSION%%/ceph.yml"
    last_ceph_node=$(($CEPH_NODE_COUNT-1))
    for x in $(seq 0 $last_ceph_node); do
      echo -e "  __CLUSTER_PREFIX__-node2$x:\n    ip: 172.29.236.2$x" >> $ceph_config
    done
    sed -i "s/__CLUSTER_PREFIX__/%%CLUSTER_PREFIX%%/g" $ceph_config
    # NOTE: these are non-sensical values; we need to revisit!
    echo "raw_multi_journal: true" | tee -a ${config_dir}/user_extras_variables.yml
    echo "journal_size: 80000" | tee -a ${config_dir}/user_extras_variables.yml
    echo "monitor_interface: eth1" | tee -a ${config_dir}/user_extras_variables.yml
    echo "public_network: 172.29.236.0/22" | tee -a ${config_dir}/user_extras_variables.yml
    echo "\
devices:
  - /dev/xvdg
  - /dev/xvdh
  - /dev/xvdi
  - /dev/xvdj
  - /dev/xvdk" | tee -a ${config_dir}/user_extras_variables.yml
    echo "\
raw_journal_devices:
  - /dev/xvdf
  - /dev/xvdf
  - /dev/xvdf
  - /dev/xvdf
  - /dev/xvdf" | tee -a ${config_dir}/user_extras_variables.yml
    echo "pool_default_size: 3" | tee -a ${config_dir}/user_extras_variables.yml
  fi

  if [ "$DEPLOY_MONITORING" = "yes" ] && [ "$TEST_MONITORING" = "yes" ]; then
    sed -i "s/\(ssl_check\): .*/\1: true/" ${config_dir}/user_extras_variables.yml
    sed -i "s/\(hp_check\): .*/\1: true/" ${config_dir}/user_extras_variables.yml
    echo "maas_horizon_scheme: https" >> ${config_dir}/user_extras_variables.yml
    echo "\
maas_testing_mappings:
  - \"%%CLUSTER_PREFIX%%-node1:CONTROLLER,LOGGER,SWIFT\"
  - \"%%CLUSTER_PREFIX%%-node2:CONTROLLER,SWIFT\"
  - \"%%CLUSTER_PREFIX%%-node3:CONTROLLER,LOADBALANCER,SWIFT\"
  - \"%%CLUSTER_PREFIX%%-node4:COMPUTE,BLOCK_STORAGE\"
  - \"%%CLUSTER_PREFIX%%-node5:COMPUTE\"" >> ${config_dir}/user_extras_variables.yml
    echo "\
maas_testing_task_files:
  - swift_maas
  - maas_cdm
  - maas_hp_hardware
  - maas_local
  - maas_remote
  - maas_ssl_check
  - network" >> ${config_dir}/user_extras_variables.yml
  fi

  ${checkout_dir}/rpc-openstack/openstack-ansible/scripts/pw-token-gen.py --file ${config_dir}/user_extras_secrets.yml
popd

# here we run ansible using the run-playbooks script in the ansible repo
if [ "%%RUN_ANSIBLE%%" = "True" ]; then
  if [ "$DEPLOY_MONITORING" = "yes" ] && [ "$TEST_MONITORING" = "yes" ]; then
    pushd ${checkout_dir}/rpc-openstack/rpcd/playbooks
      openstack-ansible "test-maas.yml" --tags "setup"
    popd
  fi
  pushd ${checkout_dir}/rpc-openstack
    export DEPLOY_HAPROXY="yes"
    export DEPLOY_CEPH=$DEPLOY_CEPH
    export DEPLOY_OA=$DELOY_OPENSTACK
    export DEPLOY_ELK=$DEPLOY_LOGGING
    export DEPLOY_MAAS=$DEPLOY_MONITORING
    export DEPLOY_CEILOMETER="no"
    ./scripts/deploy.sh
  popd
  if [ "%%RUN_TEMPEST%%" = "True" ]; then
    pushd ${checkout_dir}/rpc-openstack/openstack-ansible
      export TEMPEST_SCRIPT_PARAMETERS="%%TEMPEST_SCRIPT_PARAMETERS%%"
      scripts/run-tempest.sh
    popd
  fi
  if [ "$DEPLOY_MONITORING" = "yes" ] && [ "$TEST_MONITORING" = "yes" ]; then
    pushd ${checkout_dir}/rpc-openstack/rpcd/playbooks
      openstack-ansible "test-maas.yml" --tags "test"
    popd
  fi
fi
