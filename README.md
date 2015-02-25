To run:

```
heat stack-create -f openstack_multi_node.yml openstack-multi -P "key_name=<keyname>;os_ansible_git_version=<branch/tag>" -t 150
```

(Replace `<keyname>` with your nova key and `<branch/tag>` with the desired os-ansible version to deploy)

Failing to specify `-t 150` will result in the stack-create timing out and failing as a result.
