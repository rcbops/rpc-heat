#!/bin/bash

set -e

CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
source $CLOUD_CREDS

CONTROLLER1_IP=$(heat output-show ${CLUSTER_PREFIX} controller1_ip | sed -e 's/"//g')
CHECKOUT="/root/os-ansible-deployment/"
SSH_KEY=${SSH_KEY:-"~/.ssh/jenkins"}
SSH_OPTS="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o HashKnownHosts=no -o UserKnownHostsFile=/dev/null"
TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS:-"nightly_heat_multinode"}


ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "export TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS}; cd ${CHECKOUT} && scripts/run-tempest.sh"
