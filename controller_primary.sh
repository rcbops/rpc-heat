cat > .ssh/id_rsa << "EOF"
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEApKLsDVhO90q1Elj+wMR/vFlyOS04DznEsRIZrq6o8JGpEV73
pWm0HZyOqob4ccVp4bSH68NwETQFDDUs16tDCQMo4iqCSP50gX7k8KvUEvK415tY
meynB3jaUvx+p2/GicszDtn71TUOCelmBcizwR96Vw3khvvbFvBZtllAvNPex9K/
5gltPk/F937WlDhTvOReeBGpeP+IBuxHmAGM3Qk5YhZaMqouf0i6Njag1LD6PjeO
PEcmnUe6wqk8qAn9pB5pg8wUjQc1tGKXwbc0WVkp5PBkc/u1Ho5EJbf2pZ7tpEW7
fS8f6KEVQ6h5AWYQw0hSh5BMOJi9w2mncscboQIDAQABAoIBAQCXBpmR2FuAAHlA
XoE7pkYjKs5cYv3VAcJMSPVkR/bT0FsOg1ab1+6RZ2d8SRopi9YIZYp2HS91qImk
3DbJlOKGpu5fIm2ntjx7+kLcAFQoGZ60sl3BvdSvRw7IJ7WrtR6kktHAovigae35
67BaR/WViGG68BSeOvWNAmjZnOCFFkHTdf5XCR068v1DgOg889ymaEbh9OnY2s50
BUiM34J777Za9TdErwsRvSO9CYHCy0utfcMN6Acs+IoZle+UcONYyw6h3M1WudwQ
jxlLCEJtypjRxJHKDWs4jKM2WhQMQJUSstjaQCwTr+KYH9gG849E9okgWMarZGCh
n2ZRL5ABAoGBAM5LHVoM3tCE85yoO4fVoAQUqNjHCwmWqIEE1ss8PxYimWVMfbjp
YIN1nGNxVdQuzZzz9gU9M2N7XLKn8yQSI3qv47YPrAwODs0Xs+pklSGSeq4dV7gC
ZzEY6VQAhZbw7muAFZbDPiKAylTqLg8NVRoDyxifyApRrJrQYDLF5uwhAoGBAMxO
Qru6XWPukMeAHM01w97FQ+9sEbFHq4jjjbkFODO7VaBaRk4MCCxoYSDSJmNbog7u
YgxwydOOc+3M/6XIRNlc+tWZwv6UoY355OOlpNzWdVQR+RtvkcJtKYksTFn/lsMD
oDNRn5RtpJr4h4Y4Z2nPugH2HafuvG1kPvGLjj+BAoGAU1Ye3mDyphP/gdqoaeBP
yzY5W5FVESOOoMg+qU2GQr/pbfWvmEKXHaQmcDm5rYTWxT/8s/McTmTodrfITlsR
gB+MAuFj5F7NdebMZLULVcuhybLK2+gEnd3tbGTlkqtz9XOBxSzMbg3PLuyHfMcr
CN5dbm4l1p1V+BiTtA8kkWECgYEAoumo9w811zDty9eRn+VGigYdFPbE6Otwkhh5
81aBKWcxcUtrEmMvxVF6WfSZXdM819Eo6CisF4FZWf+Ev4qBtB4bemZBAkY8yPzC
kvCMFPkB2Ab47/K4dSQc4eAsBfv0GQ90GFf2+yGvB1A0qUei1tIozdWWcknBgS1V
r8CLroECgYApgl9fhrOI2uxjKJMUAZ07JnOqn2pIZnjGtJTbyCKsQt4JpS2/bDUG
LiSDlee56d1iOWKBWBz2/i1EHFqhW1GFDM448vA0C3pwZc72OlmugEonRyRXbKL2
ptG+vgOPUKOdkjtR9HUveHgm+PrQjs7mx0GhzV8Y2RKN9ENJw+AAyQ==
-----END RSA PRIVATE KEY-----
EOF

chmod 600 .ssh/*

cd /root
git clone -b $version https://github.com/rcbops/ansible-lxc-rpc.git
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

cd rpc_deployment
ansible-playbook -e @/etc/rpc_deploy/user_variables.yml playbooks/setup/host-setup.yml \
                                                        playbooks/infrastructure/haproxy-install.yml \
                                                        playbooks/infrastructure/infrastructure-setup.yml \
                                                        playbooks/openstack/openstack-setup.yml
