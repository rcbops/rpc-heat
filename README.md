To run:

```
ssh-keygen -f id_rsa -t rsa -q -N ""
./build_configs.sh
heat stack-create -f rpc_multi_node.yml rpc "version=stable/icehouse" -t 150
```

Failing to specify `-t 150` will result in the stack-create timing out and failing as a result.
