#!/bin/bash

set -e

CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
source $CLOUD_CREDS

CONTROLLER1_IP=$(heat output-show ${CLUSTER_PREFIX} controller1_ip | sed -e 's/"//g')
CHECKOUT="/opt/rpc-openstack/"
SSH_KEY=${SSH_KEY:-"~/.ssh/jenkins"}
SSH_OPTS="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o HashKnownHosts=no -o UserKnownHostsFile=/dev/null"
DEPLOY_LOGGING=${DEPLOY_LOGGING:-"yes"}
DEPLOY_OPENSTACK=${DEPLOY_OPENSTACK:-"yes"}
DEPLOY_SWIFT=${DEPLOY_SWIFT:-"no"}
DEPLOY_TEMPEST=${DEPLOY_TEMPEST:-"no"}

# We always set DEPLOY_MAAS to "no" as we deploy it in a different sequence in stack-monitoring.sh
ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "export DEPLOY_HAPROXY="yes" DEPLOY_CEPH=${DEPLOY_CEPH} DEPLOY_OA=${DEPLOY_OPENSTACK} export DEPLOY_CEILOMETER="no" DEPLOY_ELK=${DEPLOY_LOGGING} DEPLOY_TEMPEST=${DEPLOY_TEMPEST} DEPLOY_MAAS="no"; cd ${CHECKOUT} && scripts/deploy.sh"
ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "ifconfig br-vlan 10.1.13.1 netmask 255.255.255.0"
