#!/bin/bash

set -e

source ~/.openrc

ip=$(heat output-show rpc-jenkins-${BUILD_NUMBER} controller1_ip | sed -e 's/"//g')
cmd="cd /root/ansible-lxc-rpc/rpc_deployment && bash run_ansible.sh"

ssh -l root -i ~/.ssh/jenkins -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $ip $cmd
