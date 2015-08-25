#!/bin/bash

SUFFIX=`date +%s | shasum | base64 | head -c 8 ; echo`
KEY=
UPGRADE_FROM=juno
UPGRADE_TO=master

usage()
{
    echo Usage: $0 "--key <key-name>" "--from <release-name>" "--to <release-name>" "--suffix <instance-name-suffix>" >&2
    echo "Options:" >&2
    echo "    -k | --key    The name of the public key to use in all the instances." >&2
    echo "    -f | --from   The OpenStack release to start from. (defaults to juno)" >&2
    echo "    -t | --to     The OpenStack release to upgrade to (defaults to master)." >&2
    echo "    -s | --suffix A string to append to all instance names (defaults to a randomly generated string)." >&2
    exit 1
}

while [[ $# > 0 ]]; do
    opt="$1"
    case $opt in
        -k|--key)
            KEY="$2"
            shift
            ;;
        -f|--from)
            UPGRADE_FROM="$2"
            shift
            ;;
        -t|--to)
            UPGRADE_TO="$2"
            shift
            ;;
        -s|--suffix)
            SUFFIX="$2"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ "$KEY" == "" ]; then
    echo Error: Key must be specified.
fi
if [ "$UPGRADE_FROM" == "" ]; then
    echo Error: Release to upgrade from must be specified.
fi
if [ "$UPGRADE_TO" == "" ]; then
    echo Error: Release to upgrade to must be specified.
fi
if [ "$SUFFIX" == "" ]; then
    echo Error: Suffix must be specified.
fi
if [ "$KEY" == "" -o "$UPGRADE_FROM" == "" -o "$UPGRADE_TO" == "" -o "$SUFFIX" == "" ]; then
    usage
fi

# ensure heat and nova are present
which heat >/dev/null 2>&1
HEAT_PRESENT=$?
which nova >/dev/null 2>&1
NOVA_PRESENT=$?
if [[ "$HEAT_PRESENT" != "0" && "$NOVA_PRESENT" != "0" ]]; then
    echo Error: The heat and nova clients are not available. Run \"pip install python-heatclient python-novaclient\" to install them.
    exit 1
elif [[ "$HEAT_PRESENT" != "0" ]]; then
    echo Error: The heat client is not available. Run \"pip install python-heatclient\" to install it.
    exit 1
elif [[ "$NOVA_PRESENT" != "0" ]]; then
    echo Error: The nova client is not available. Run \"pip install python-novaclient\" to install it.
    exit 1
fi

START=$(date +%s);

printf "Deploying RPC $UPGRADE_FROM release with stack name rpc-$SUFFIX.\n"
heat stack-create -f rpc_multi_node.yml rpc-$SUFFIX -P "heat_git_version=$UPGRADE_FROM;os_ansible_git_version=$UPGRADE_FROM;deploy_monitoring=no;key_name=$KEY;cluster_prefix=rpc-$SUFFIX" -t 150 >/dev/null

while true; do
    sleep 10
    STATUS=`heat stack-show rpc-$SUFFIX 2>/dev/null`

    # check if the stack is still building
    echo $STATUS | grep CREATE_IN_PROGRESS >/dev/null 2>&1
    if [[ "$?" == "0" ]]; then
        printf "."
        continue
    fi

    # heat is done, check if the stack built succesfully
    echo $STATUS | grep CREATE_COMPLETE >/dev/null 2>&1
    if [ "$?" == "0" ]; then
        break
    fi

    printf "\nError: The heat stack "rpc-$SUFFIX" failed to deploy. Exiting.\n"
    exit 1
done

# capture the IP addresses for the three controller hosts
CONTROLLER_ID=`heat resource-list rpc-$SUFFIX | grep 'controller1.*OS::Nova::Server' | awk '{print $4}'`
CONTROLLER_IP=`nova show $CONTROLLER_ID | grep accessIPv4 | awk '{print $4}'`
CONTROLLER2_ID=`heat resource-list rpc-$SUFFIX | grep 'controller2.*OS::Nova::Server' | awk '{print $4}'`
CONTROLLER2_IP=`nova show $CONTROLLER2_ID | grep accessIPv4 | awk '{print $4}'`
CONTROLLER3_ID=`heat resource-list rpc-$SUFFIX | grep 'controller3.*OS::Nova::Server' | awk '{print $4}'`
CONTROLLER3_IP=`nova show $CONTROLLER3_ID | grep accessIPv4 | awk '{print $4}'`

END_INSTALL=$(date +%s);
printf "\n$UPGRADE_FROM release was succesfully deployed in "
echo $((END_INSTALL-START)) | awk '{print int($1/60)"m "int($1%60)"s."}'

printf "Starting RPC upgrade to $UPGRADE_TO."
ssh root@$CONTROLLER_IP git clone -b $UPGRADE_TO https://github.com/rcbops/rpc-openstack.git /opt/rpc-openstack --recursive
ssh root@$CONTROLLER_IP "cd /opt/rpc-openstack; scripts/upgrade.sh"
RET=$?

END=$(date +%s);
printf "RPC upgrade from $UPGRADE_FROM to $UPGRADE_TO finished in "
echo $((END-END_INSTALL)) | awk '{print int($1/60)"m "int($1%60)"s."}'
printf "Infra hosts = $CONTROLLER_IP, $CONTROLLER2_IP, $CONTROLLER3_IP\n"
printf "LB = $CONTROLLER3_IP\n"

exit $RET
