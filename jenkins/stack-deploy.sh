#!/bin/bash

set -e

source ~/.openrc

ip=$(heat output-show rpc-jenkins-${BUILD_NUMBER} controller1_ip | sed -e 's/"//g')
checkout="/root/ansible-lxc-rpc/rpc_deployment"
ssh_key=~/.ssh/jenkins
ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Temporary commands to test new neutron library
ssh -l root -i $ssh_key $ssh_options $ip "cd $checkout && curl -o library/neutron https://raw.githubusercontent.com/mattt416/ansible-lxc-rpc/0cfc78d5749f7178995242272e5e90f1202e564d/rpc_deployment/library/neutron"
scp -i $ssh_key $ssh_options jenkins/tempest_resources.yml root@${ip}:${checkout}/roles/tempest_resources/tasks/main.yml
scp -i $ssh_key $ssh_options jenkins/tempest.conf.j2 root@${ip}:${checkout}/roles/tempest/templates/tempest.conf.j2

ssh -l root -i $ssh_key $ssh_options $ip "cd $checkout && bash run_ansible.sh"

ssh -l root -i $ssh_key $ssh_options $ip "ifconfig br-vlan 10.1.13.1 netmask 255.255.255.0"
ssh -l root -i $ssh_key $ssh_options $ip "mysql nova -e 'UPDATE instance_types SET memory_mb=256 WHERE flavorid=1 LIMIT 1;'"
ssh -l root -i $ssh_key $ssh_options $ip "mysql nova -e 'UPDATE instance_types SET root_gb=1,memory_mb=512 WHERE flavorid=2 LIMIT 1;'"
