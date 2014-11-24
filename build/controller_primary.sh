echo "$PRIVATE_KEY" > .ssh/id_rsa
chmod 600 .ssh/*

cd /root
git clone -b %%RPC_VERSION%% https://github.com/rcbops/ansible-lxc-rpc.git
cd ansible-lxc-rpc
pip install -r requirements.txt
cp -a etc/rpc_deploy /etc/
scripts/pw-token-gen.py --file /etc/rpc_deploy/user_variables.yml
echo "nova_virt_type: qemu" >> /etc/rpc_deploy/user_variables.yml

rpc_user_config="/etc/rpc_deploy/rpc_user_config.yml"
environment_version=$(md5sum /etc/rpc_deploy/rpc_environment.yml | awk '{print $1}')

curl -o $rpc_user_config https://raw.githubusercontent.com/mattt416/rpc_heat/master/rpc_user_config.yml
sed -i "s/__ENVIRONMENT_VERSION__/$environment_version/g" $rpc_user_config
sed -i "s/__EXTERNAL_VIP_IP__/$EXTERNAL_VIP_IP/g" $rpc_user_config
sed -i "s/__CLUSTER_PREFIX__/$CLUSTER_PREFIX/g" $rpc_user_config

cd rpc_deployment
ansible-playbook -e @/etc/rpc_deploy/user_variables.yml playbooks/setup/host-setup.yml \
                                                        playbooks/infrastructure/haproxy-install.yml \
                                                        playbooks/infrastructure/infrastructure-setup.yml \
                                                        playbooks/openstack/openstack-setup.yml
