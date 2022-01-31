! check_etcd
A Nagios/Icinga2 check to monitor etcd cluster members written in bash.
This check makes use of etcdctl and curl to the /metrics endpoint.

!!Usage
```
/usr/lib64/nagios/plugins/check_etcd.sh -w num -c num [-H host] [ -P port] [-S] [-n] [-N] [-m "label|type|warn|crit|match"]
-w defines the warning threshold. If less lines are reporting "is healthy",
   this triggers a warning
-c defines the critical threshold (should be lower than -w)
-m defines a metric to gather via curl
-h this help
-H Host/IP to check, defaults to localhost
-P Port to chjeck, defaults to 2379
-S Use http instead of https, by default https is used
-n No cluster check with etcdctl
-N no curl check to /metrics
-m defines optional metrics to gather data for. label is the label used for
   storing the data in influxdb, type is either value (or empty) or delta,
   describing whether the value of the metric or its delta to the previous
   value will be used. warn and crit are the ranges for alerting, these
   may be empty. Match is the string to grep for in the output.
```

!!License
BSD 3-Clause License

!! Build instructions for the RPM
There is a rpmbuild folder containing the spec file. The provided build.sh
script will build a rpm based on the tagged version on github. You need to provide
the version number and optionally a release as parameters to the script.

Example
```
./build.sh 1.0.0 1
```
builds the icinga_check_etcd-1.0.0-1.x86_64.rpm