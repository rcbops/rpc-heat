#!/bin/bash

set -e

source ~/.openrc

ip=$(heat output-show rpc-jenkins-${BUILD_NUMBER} controller1_ip | sed -e 's/"//g')
checkout="/root/os-ansible-deployment/"
ssh_key=~/.ssh/jenkins
ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Temporary work-around otherwise we hit https://bugs.launchpad.net/neutron/+bug/1382064
# which results in tempest tests failing
ssh -l root -i $ssh_key $ssh_options $ip "sed -i 's/api_workers = 10/api_workers = 0/' ${checkout}/rpc_deployment/roles/neutron_common/templates/neutron.conf"
ssh -l root -i $ssh_key $ssh_options $ip "sed -i 's/rpc_workers = 5/rpc_workers = 0/' ${checkout}/rpc_deployment/roles/neutron_common/templates/neutron.conf"

ssh -l root -i $ssh_key $ssh_options $ip "cd ${checkout}/rpc_deployment && bash run_ansible.sh 2>&1 | tee -a run_ansible.log"

ssh -l root -i $ssh_key $ssh_options $ip "ifconfig br-vlan 10.1.13.1 netmask 255.255.255.0"

if echo "$ANSIBLE_PLAYBOOKS" | grep "tempest"; then
  ssh -l root -i $ssh_key $ssh_options $ip "lxc-attach -n \$(lxc-ls | grep utility) -- sh -c 'cd /opt/tempest_*/ && ./run_tempest.sh --smoke -N || true'"
fi

if echo "$ANSIBLE_PLAYBOOKS" | grep "monitoring"; then
  ssh -l root -i $ssh_key $ssh_options $ip "cd ${checkout}/scripts && python rpc_maas_tool.py check --prefix jenkins-${BUILD_NUMBER}"
end
