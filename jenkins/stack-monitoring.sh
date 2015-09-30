#!/bin/bash

set -e

CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
source $CLOUD_CREDS

CONTROLLER1_IP=$(heat output-show ${CLUSTER_PREFIX} controller1_ip | sed -e 's/"//g')
CHECKOUT="/opt/rpc-openstack/"
SSH_KEY=${SSH_KEY:-"~/.ssh/jenkins"}
SSH_OPTS="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o HashKnownHosts=no -o UserKnownHostsFile=/dev/null"
DEPLOY_MONITORING=${DEPLOY_MONITORING:-"no"}
TEST_MONITORING=${TEST_MONITORING:-"no"}


if [ $DEPLOY_MONITORING = "yes" ]; then
  # We setup test-maas.yml first so we get the mocked hp tools dropped on the
  # hosts; this prevents us from getting hp-related failures until the tools
  # are dropped.
  if [ "$TEST_MONITORING" = "yes" ]; then
    ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "cd ${CHECKOUT}/rpcd/playbooks && openstack-ansible test-maas.yml --tags setup,setup-fake-hp"
  fi
  ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "cd ${CHECKOUT}/rpcd/playbooks && openstack-ansible setup-maas.yml"
  if [ "$TEST_MONITORING" = "yes" ]; then
    ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "cd ${CHECKOUT}/rpcd/playbooks && openstack-ansible test-maas.yml --tags test"
  fi
fi
