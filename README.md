# DEPRECATED

Please use https://github.com/cloud-training/rpc-heat-ansible instead.

**To run:**

```
heat stack-create -e openstack_multi_node_environment.yml -f openstack_multi_node.yml openstack-multi -P "key_name=<keyname>;os_ansible_git_version=<branch/tag>" -t 150
```

(Replace `<keyname>` with your nova key and `<branch/tag>` with the desired openstack-ansible version to deploy)

Failing to specify `-t 150` will result in the stack-create timing out and failing as a result.

**Which version of rpc-heat should I use?**

openstack-ansible     | rpc-heat
----------------------|---------
master                | master
liberty               | master
kilo                  | master
juno                  | juno
