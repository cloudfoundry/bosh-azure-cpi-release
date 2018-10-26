# Collect CF deployment error logs

Here is a script that helps you to collect error logs when you hit an error on deploying CF. You can analyze the error by yourselves, or send the error logs to support team to get some helps.

The script will collect error logs including:
  * debug logs of bosh tasks which failed
  * job error logs of the failed vm
  * kernel, syslog, waagent, omsagent logs of the failed vm
  * bosh agent log of the failed vm

## Pre-requisites

1. You need to have bosh cli (v1 / v2) installed. The script will automatically detect the cli version.

1. Install jq

    ```bash
    sudo apt-get install jq
    ```

1. You need to login the bosh director with the admin permission

    for bosh v1:
    ```bash
    bosh login
    ```

    for bosh v2:
    ```bash
    bosh -e ${env} login
    ```

## Collect logs

Run belowing commands in your jumpbox to collect error logs

```bash
wget https://raw.githubusercontent.com/cloudfoundry/bosh-azure-cpi-release/master/docs/additional-information/collect-deployment-err-logs.sh
bash collect-deployment-err-logs.sh
```

After completion, you will see output like `Logs have been collected at /tmp/cf-deployment-diagnostics-*.tgz`. You can review the log, redact the credentials and then send it out for further support.

>Note: By default, the script only collects the latest 10 error deployment logs. If you need to collect more error logs (e.g. 50), you can pass the number to the parameter `--err-log-count`. For example:
```bash
bash collect-deployment-err-logs.sh --err-log-count 50
```
