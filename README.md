To run:

```
./build_configs.sh
heat stack-create -f rpc_multi_node.yml rpc "version=stable/icehouse" -t 150
```

Note that you have to pass -t 150, otherwise heat will time out after 60 minutes.  Rackspace orchestration does not seem to support the OS::Heat::WaitCondition and OS::Heat::WaitConditionHandle resource types at this time.
