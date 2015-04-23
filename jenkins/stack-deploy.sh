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
RUN_TEMPEST=${RUN_TEMPEST:-"yes"}
DEPLOY_MONITORING=${DEPLOY_MONITORING:-"no"}
TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS:-"smoke"}


ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "cd ${CHECKOUT} && scripts/bootstrap-ansible.sh"
# Enabling this works for scenario tests, but generates failures when running smoke tests
ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "echo 'tempest_compute_run_ssh: False' >> /etc/openstack_deploy/user_variables.yml"
ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "export DEPLOY_LOGGING=${DEPLOY_LOGGING} DEPLOY_OPENSTACK=${DEPLOY_OPENSTACK} DEPLOY_SWIFT=${DEPLOY_SWIFT} DEPLOY_TEMPEST=${DEPLOY_TEMPEST} DEPLOY_MONITORING=${DEPLOY_MONITORING}; cd ${CHECKOUT} && ANSIBLE_FORCE_COLOR=true scripts/run-playbooks.sh"

ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "/sbin/ifconfig br-vlan 10.1.13.1 netmask 255.255.255.0"
# This allows instances to be able to reach public Internet
ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"

if [ $RUN_TEMPEST = "yes" ]; then
  ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "export TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS}; cd ${CHECKOUT} && scripts/run-tempest.sh"
fi

#if [ $DEPLOY_MONITORING = "true" ]; then
#  echo "Testing MaaS checks ..."
#  ssh -l root -i $ssh_key $ssh_options $ip "cd ${CHECKOUT}/scripts && python rpc_maas_tool.py check --prefix ${CLUSTER_PREFIX}"
#  echo "Done."
#fi
