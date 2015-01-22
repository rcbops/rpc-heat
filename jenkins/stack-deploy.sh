#!/bin/bash

set -e

source ~/.openrc

ip=$(heat output-show rpc-jenkins-${BUILD_NUMBER} controller1_ip | sed -e 's/"//g')
checkout="/root/ansible-lxc-rpc/rpc_deployment"
ssh_key=~/.ssh/jenkins
ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Temporary commands to test new neutron library
ssh -l root -i $ssh_key $ssh_options $ip "cd $checkout && curl -o library/neutron https://raw.githubusercontent.com/mattt416/ansible-lxc-rpc/3b425cdd1f7ef8ca8819c503bcda7e0b0dfa1351/rpc_deployment/library/neutron"
scp -i $ssh_key $ssh_options jenkins/tempest_resources.yml root@${ip}:${checkout}/roles/tempest_resources/tasks/main.yml
scp -i $ssh_key $ssh_options jenkins/tempest.conf.j2 root@${ip}:${checkout}/roles/tempest/templates/tempest.conf.j2

# Temporary work-around otherwise we hit https://bugs.launchpad.net/neutron/+bug/1382064
# which results in tempest tests failing
ssh -l root -i $ssh_key $ssh_options $ip "sed -i 's/api_workers = 10/api_workers = 0/' /root/ansible-lxc-rpc/rpc_deployment/roles/neutron_common/templates/neutron.conf"
ssh -l root -i $ssh_key $ssh_options $ip "sed -i 's/rpc_workers = 5/rpc_workers = 0/' /root/ansible-lxc-rpc/rpc_deployment/roles/neutron_common/templates/neutron.conf"

ssh -l root -i $ssh_key $ssh_options $ip "cd $checkout && bash run_ansible.sh"

ssh -l root -i $ssh_key $ssh_options $ip "ifconfig br-vlan 10.1.13.1 netmask 255.255.255.0"

ssh -l root -i $ssh_key $ssh_options $ip "lxc-attach -n \$(lxc-ls | grep utility) -- sh -c 'cd /opt/tempest_*/ && ./run_tempest.sh --smoke -N || true'"
