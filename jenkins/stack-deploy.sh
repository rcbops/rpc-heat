#!/bin/bash

set -e

CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
source $CLOUD_CREDS

CONTROLLER1_IP=$(heat output-show ${CLUSTER_PREFIX} controller1_ip | sed -e 's/"//g')
CHECKOUT="/root/os-ansible-deployment/"
SSH_KEY=${SSH_KEY:-"~/.ssh/jenkins"}
SSH_OPTS="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o HashKnownHosts=no -o UserKnownHostsFile=/dev/null"
DEPLOY_LOGGING=${DEPLOY_LOGGING:-"yes"}
DEPLOY_OPENSTACK=${DEPLOY_OPENSTACK:-"yes"}
DEPLOY_SWIFT=${DEPLOY_SWIFT:-"no"}
DEPLOY_TEMPEST=${DEPLOY_TEMPEST:-"no"}
DEPLOY_MONITORING=${DEPLOY_MONITORING:-"no"}
TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS:-"nightly_heat_multinode"}


ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "cd ${CHECKOUT} && scripts/bootstrap-ansible.sh"
ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "export DEPLOY_LOGGING=${DEPLOY_LOGGING} DEPLOY_OPENSTACK=${DEPLOY_OPENSTACK} DEPLOY_SWIFT=${DEPLOY_SWIFT} DEPLOY_TEMPEST=${DEPLOY_TEMPEST} DEPLOY_MONITORING=${DEPLOY_MONITORING}; cd ${CHECKOUT} && ANSIBLE_FORCE_COLOR=true scripts/run-playbooks.sh"

ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "ifconfig br-vlan 10.1.13.1 netmask 255.255.255.0"

if [ $DEPLOY_TEMPEST = "yes" ]; then
  ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "cd ${CHECKOUT} && scripts/run-tempest.sh ${TEMPEST_SCRIPT_PARAMETERS}"
fi

#if [ $DEPLOY_MONITORING = "true" ]; then
#  echo "Testing MaaS checks ..."
#  ssh -l root -i $ssh_key $ssh_options $ip "cd ${CHECKOUT}/scripts && python rpc_maas_tool.py check --prefix ${CLUSTER_PREFIX}"
#  echo "Done."
#fi
