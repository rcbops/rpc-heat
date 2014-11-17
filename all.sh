#!/bin/bash

PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCkouwNWE73SrUSWP7AxH+8WXI5LTgPOcSxEhmurqjwkakRXvelabQdnI6qhvhxxWnhtIfrw3ARNAUMNSzXq0MJAyjiKoJI/nSBfuTwq9QS8rjXm1iZ7KcHeNpS/H6nb8aJyzMO2fvVNQ4J6WYFyLPBH3pXDeSG+9sW8Fm2WUC8097H0r/mCW0+T8X3ftaUOFO85F54Eal4/4gG7EeYAYzdCTliFloyqi5/SLo2NqDUsPo+N448RyadR7rCqTyoCf2kHmmDzBSNBzW0YpfBtzRZWSnk8GRz+7UejkQlt/alnu2kRbt9Lx/ooRVDqHkBZhDDSFKHkEw4mL3Daadyxxuh root@heat-controller-1"

apt-get update
apt-get install -y bridge-utils git

cat > /etc/hosts << "EOF"
127.0.0.1 localhost
172.29.236.1 heat-controller-1
172.29.236.2 heat-controller-2
172.29.236.3 heat-controller-3
172.29.236.4 heat-compute-1
172.29.236.5 heat-compute-2
EOF

cd /root

echo $PUBKEY > .ssh/id_rsa.pub

echo $PUBKEY >> .ssh/authorized_keys

chmod 600 .ssh/*

