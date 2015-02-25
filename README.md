To run:

```
heat stack-create -f rpc_multi_node.yml rpc -P "key_name=<keyname>;rpc_git_version=<branch/tag>" -t 150
```

(Replace `<keyname>` with your nova key and `<branch/tag>` with the desired RPC version to deploy)

Failing to specify `-t 150` will result in the stack-create timing out and failing as a result.
