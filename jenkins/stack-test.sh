#!/bin/bash

set -e

CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
source $CLOUD_CREDS

CONTROLLER1_IP=$(heat output-show ${CLUSTER_PREFIX} controller1_ip | sed -e 's/"//g')
CHECKOUT="/root/os-ansible-deployment/"
SSH_KEY=${SSH_KEY:-"~/.ssh/jenkins"}
SSH_OPTS="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o HashKnownHosts=no -o UserKnownHostsFile=/dev/null"
TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS:-"smoke"}
RUN_TEMPEST_OPTS=${RUN_TEMPEST_OPTS:-'--serial'}


ssh -l root -i $SSH_KEY $SSH_OPTS $CONTROLLER1_IP "export TEMPEST_SCRIPT_PARAMETERS=${TEMPEST_SCRIPT_PARAMETERS} RUN_TEMPEST_OPTS=${RUN_TEMPEST_OPTS}; cd ${CHECKOUT} && scripts/run-tempest.sh"
