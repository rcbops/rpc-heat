#!/bin/bash

#set -e

SSH_OPTS="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o HashKnownHosts=no"
CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
KEY_NAME=${KEY_NAME:-"jenkins"}
FLAVOR=${FLAVOR:-"performance1-8"}
RPC_GIT_REPO=${RPC_GIT_REPO:-"https://github.com/stackforge/os-ansible-deployment"}
RPC_GIT_VERSION=${RPC_GIT_VERSION:-"master"}
HEAT_GIT_REPO=${HEAT_GIT_REPO:-"https://github.com/rcbops/rpc-heat"}
HEAT_GIT_VERSION=${HEAT_GIT_VERSION:-"master"}
CLUSTER_PREFIX=${CLUSTER_PREFIX:-$(date "+%Y%m%d%H%M")}
DEPLOY_LOGGING=${DEPLOY_LOGGING:-"True"}
DEPLOY_TEMPEST=${DEPLOY_TEMPEST:-"False"}
DEPLOY_SWIFT=${DEPLOY_SWIFT:-"True"}
DEPLOY_MONITORING=${DEPLOY_MONITORING:-"False"}
RACKSPACE_CLOUD_USERNAME=${RACKSPACE_CLOUD_USERNAME:-"$OS_USERNAME"}
RACKSPACE_CLOUD_API_KEY=${RACKSPACE_CLOUD_API_KEY:-"OS_API_KEY"}
RACKSPACE_CLOUD_AUTH_URL=${RACKSPACE_CLOUD_AUTH_URL:-"$OS_AUTH_URL"}
RACKSPACE_CLOUD_PASSWORD=${RACKSPACE_CLOUD_PASSWORD:-"$OS_PASSWORD"}
RACKSPACE_CLOUD_TENANT_ID=${RACKSPACE_CLOUD_TENANT_ID:-"$OS_TENANT_ID"}
GLANCE_DEFAULT_STORE=${GLANCE_DEFAULT_STORE:-"swift"}
GLANCE_SWIFT_STORE_REGION=${GLANCE_SWIFT_STORE_REGION:-"DFW"}
RUN_ANSIBLE=${RUN_ANSIBLE:-"False"}

source $CLOUD_CREDS

heat stack-create -c 120 -f rpc_multi_node.yml ${CLUSTER_PREFIX} -P "key_name=${KEY_NAME};rpc_git_version=${RPC_GIT_VERSION};cluster_prefix=${CLUSTER_PREFIX};deploy_logging=${DEPLOY_LOGGING};deploy_tempest=${DEPLOY_TEMPEST};deploy_swift=${DEPLOY_SWIFT};deploy_monitoring=${DEPLOY_MONITORING};rackspace_cloud_username=${RACKSPACE_CLOUD_USERNAME};rackspace_cloud_api_key=${RACKSPACE_CLOUD_API_KEY};rackspace_cloud_auth_url=${RACKSPACE_CLOUD_AUTH_URL};rackspace_cloud_password=${RACKSPACE_CLOUD_PASSWORD};rackspace_cloud_tenant_id=${RACKSPACE_CLOUD_TENANT_ID};glance_default_store=${GLANCE_DEFAULT_STORE};glance_swift_store_region=${GLANCE_SWIFT_STORE_REGION};flavor=${FLAVOR};rpc_git_repo=${RPC_GIT_REPO};heat_git_repo=${HEAT_GIT_REPO};heat_git_version=${HEAT_GIT_VERSION};run_ansible=${RUN_ANSIBLE}"

exit_status=-1

# don't wait forever
TIMEOUT=0
while [ $exit_status -lt 0 ] ; do
  stack_status=$(heat stack-show ${CLUSTER_PREFIX}|grep 'stack_status '|cut -d'|' -f 3|sed -e 's/ //g')
  echo $stack_status
  if [ "$stack_status" = "CREATE_COMPLETE" ]; then
    exit_status=0
    break
  elif [ "$stack_status" = "CREATE_FAILED" ]; then
    exit_status=1
    break
  elif [ $TIMEOUT -eq 120 ] ; then
    exit_status=1
    break
  fi
  sleep 60
  ((TIMEOUT++))
done

# show the stack, regardless of success or failure
heat stack-show ${CLUSTER_PREFIX}

# grab the ansible log from the run if node1 is alive
#NODE1_IP=$(heat output-show ${CLUSTER_PREFIX} controller1_ip 2>/dev/null | tr -d '"')
#if [ ! -z "$NODE1_IP" ]; then
#  ssh $SSH_OPTS -i $JENKINS_PRIVATE_KEY root@${NODE1_IP} 'if [ -e /var/log/cloud-init-output.log ]; then cat /var/log/cloud-init-output.log ; else exit 0; fi'
#fi

exit $exit_status
