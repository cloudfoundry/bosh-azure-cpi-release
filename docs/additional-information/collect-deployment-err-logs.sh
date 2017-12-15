#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR=$(mktemp -d /tmp/cf-deployment-diagnostics-logs.XXXXX)

# how many bosh error logs to collect
err_log_count=10

bosh_version="unknown"
bosh_cmd="bosh"

err_vms=() # error vms

function check_dependency() {
  # bosh
  which bosh > /dev/null
  if [[ $? -ne 0 ]]; then
    BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh -v
    if [[ $? == 0 ]]; then
      export BUNDLE_GEMFILE="/home/tempest-web/tempest/web/vendor/bosh/Gemfile"
      bosh_cmd="bundle exec bosh"
    else
      echo "*bosh* is not found, please install it"
      exit -1
    fi
  fi

  # jq
  which jq > /dev/null
  if [[ $? -ne 0 ]]; then
    echo "*jq* is not found, please install it"
    exit -1
  fi
}

function notice() {
  echo "
    This script assumes:
        1. you have bosh (v1 / v2) and jq installed
        2. you have already login to bosh director with admin permission
    The script will try to collect error logs including
        a. bosh error logs
        b. job error logs
        c. related system logs of the failed vm: kern.log, syslog, waagent.log, omsagent.log, scx.log
        d. bosh agent log of the failed vm
    note: logs in windows vms won't be collected
  "
}


# run_cmd $cmd $action
#   $cmd: command to run
#   $action: action to do if command fail, available values: ignore, warn, exit
#            default value: ignore
function run_cmd() {
  cmd=$1
  action=$2
  echo -e "Running cmd: ${cmd}"
  output=$(bash -c "${cmd} 2>&1")
  ret=$?
  if [[ ${ret} != 0 ]]; then
    if [[ "${action}" == "warn" ]]; then
      echo -e "Warning: error on running: ${cmd}\nOutput:\n${output}\n"
    elif [[ "${action}" == "exit" ]]; then
      echo -e "Error: error on running: ${cmd}\nOutput:\n${output}\n"
      exit -1
    fi
  fi
}

function quit_with_msg() {
  echo -e "\n$1"
  exit -1
}

function check_version_and_auth() {
  # bosh versions
  echo "Checking bosh version..."
  echo "${bosh_cmd} -v"
  output=$(${bosh_cmd} -v)
  if [[ ${output} == "BOSH 1"* ]]; then
    echo "Found version 1"
    bosh_version="v1"
  elif [[ ${output} == "version 2"* ]]; then
    echo "Found version 2"
    bosh_version="v2"
  else
    echo "Unknown bosh version, quit!"
    exit -1
  fi

  if [[ ${bosh_version} == "v2" ]]; then
    # environments
    echo "Checkign environments..."
    output=$(${bosh_cmd} environments --json) || quit_with_msg "Fail to get environments. You might need to login first"
    envs=$(echo ${output} | jq '.Tables[] .Rows[] | select (.url!="")' |jq .url | sort | uniq)
    if [[ -z ${envs} ]]; then
      echo "No environment is found. Exit"
      exit -1
    fi
    if [[ $(echo "${envs}" | wc -l) == 1 ]]; then
      echo "Use env ${envs}"
      bosh_cmd="${bosh_cmd} -e ${envs}"
    else
      echo -e "Found multiple environments:\n$(${bosh_cmd} environments)\nInput environment name that you want to collect logs for:"
      read env
      bosh_cmd="${bosh_cmd} -e ${env}"
    fi
  fi

  # login
  ${bosh_cmd} stemcells > /dev/null || quit_with_msg "You need to login first"
}

function check_deployment() {
  echo "Checking deployments..."
  status=0

  if [[ ${bosh_version} == "v1" ]]; then
    ${bosh_cmd} deployment > /dev/null
    status=$?
  fi

  if [[ ${bosh_version} == "v2" ]]; then
    output=$($bosh_cmd deployments --json)
    deployments=$(echo ${output} | jq '.Tables[] .Rows[] .name')
    if [[ -z ${deployments} ]]; then
      echo "No deployment is found"
      status=-1
    elif [[ $(echo "${deployments}" | wc -l) == 1 ]]; then
      echo "Use deployment ${deployments}"
      bosh_cmd="${bosh_cmd} -d ${deployments}"
    else
      echo -e "Found multiple deployments:\n$($bosh_cmd deployments)\nInput deployment name that you want to collect logs for:"
      read deployment
      bosh_cmd="${bosh_cmd} -d ${deployment}"
    fi
    return ${status}
  fi
}

function collect_bosh_logs() {
  log_dir="${WORK_DIR}/bosh"
  mkdir -p ${log_dir}

  if [[ ${bosh_version} == "v1" ]]; then
    output=$(${bosh_cmd} tasks recent |grep 'error\|timeout' | head -n ${err_log_count})
    tasks=$(echo "${output}" |cut -d '|' -f 2)
  elif [[ ${bosh_version} == "v2" ]]; then
    output=$(${bosh_cmd} tasks -r |grep 'error\|timeout' | head -n ${err_log_count})
    tasks=$(echo "${output}" | cut  -f1)
  fi
  for task in ${tasks}; do
    echo -e "Getting bosh task log of task ${task}..."
    #run_cmd "${bosh_cmd} task ${task} > ${log_dir}/${task}.log"
    run_cmd "${bosh_cmd} task ${task} --debug > ${log_dir}/${task}-debug.log"
  done
}

function get_err_vms() {
  log_dir="${WORK_DIR}/vms"
  mkdir -p ${log_dir}

  if [[ ${bosh_version} == "v1" ]]; then
    vms=$(${bosh_cmd} vms)
    echo "${vms}" > ${log_dir}/vms.log
    err_vms=$(echo "${vms}" | grep '|' | grep -v State |grep -v + | grep -v running | cut -d ' ' -f2 )
  elif [[ ${bosh_version} == "v2" ]]; then
    vms=$(${bosh_cmd} vms --json)
    echo "${vms}" > ${log_dir}/vms.log
    err_vms=$(echo "${vms}" | jq '.Tables[] .Rows[] | select(.process_state!="running")' | jq --raw-output .instance)
  fi
}

function collect_job_logs() {
  log_dir="${WORK_DIR}/jobs"
  mkdir -p ${log_dir}

  echo "Getting cf job logs..."
  # for v1
  if [[ ${bosh_version} == "v1" ]]; then
    for vm in ${err_vms}; do
      job=$(echo ${vm} | cut -d '/' -f1)
      index=$(echo ${vm} | cut -d '/' -f2)
      run_cmd "${bosh_cmd} logs ${job} ${index} --job --dir ${log_dir}" "warn"
    done
  # for v2
  elif [[ ${bosh_version} == "v2" ]]; then
    for vm in ${err_vms}; do
      echo -e "Getting job log of vm ${vm}..."
      run_cmd "${bosh_cmd} logs ${vm} --dir=${log_dir}" "warn"
    done
  fi
}

function collect_bosh_agent_logs() {
  log_dir="${WORK_DIR}/bosh-agents"
  mkdir -p ${log_dir}

  echo "Getting bosh agent logs..."
  # for v1
  if [[ ${bosh_version} == "v1" ]]; then
    for vm in ${err_vms}; do
      job=$(echo ${vm} | cut -d '/' -f1)
      index=$(echo ${vm} | cut -d '/' -f2)
      run_cmd "${bosh_cmd} logs ${job} ${index} --agent --dir ${log_dir}" "warn"
    done
  # for v2
  elif [[ ${bosh_version} == "v2" ]]; then
    for vm in ${err_vms}; do
      echo -e "Getting agent log of vm ${vm}..."
      run_cmd "${bosh_cmd} logs --agent ${vm} --dir=${log_dir}" "warn"
    done
  fi
}

function collect_system_logs() {
  tgz="/var/vcap/diagnostics/sys-logs.tgz"
  copy_syslog_script="sudo su -c 'rm ${tgz}; mkdir -p $(dirname ${tgz}); tar -czf ${tgz} /var/log/kern.log /var/log/syslog /var/log/waagent.log /var/opt/microsoft/omsagent/log/omsagent.log /var/opt/microsoft/scx/log/scx.log; chmod -R 755 ${tgz}'"
  # for v1
  if [[ ${bosh_version} == "v1" ]]; then
    for vm in ${err_vms}; do
      echo -e "Getting system log of vm ${vm}..."
      log_dir="${WORK_DIR}/syslog/${vm//\//-}"
      mkdir -p ${log_dir}

      job=$(echo ${vm} | cut -d '/' -f1)
      index=$(echo ${vm} | cut -d '/' -f2)

      run_cmd "echo \"${copy_syslog_script}; exit\" | ${bosh_cmd} ssh ${vm}" "warn"
      run_cmd "${bosh_cmd} scp ${job} ${index} ${tgz} ${log_dir} --download" "warn"
    done
  # for v2
  elif [[ ${bosh_version} == "v2" ]]; then
    for vm in ${err_vms}; do
      echo -e "Getting system log of vm ${vm}..."
      log_dir="${WORK_DIR}/syslog/${vm//\//-}"
      mkdir -p ${log_dir}

      run_cmd "echo \"${copy_syslog_script}; exit\" | ${bosh_cmd} ssh ${vm}" "warn"
      run_cmd "${bosh_cmd} scp ${vm}:/var/vcap/diagnostics/sys-logs.tgz ${log_dir}" "warn"
    done
  fi
}

function package_logs() {
  package_name="/tmp/cf-deployment-diagnostics-$(date '+%Y-%m-%d-%H:%M:%S').tgz"
  pushd ${WORK_DIR} > /dev/null
    tar -czf ${package_name} *
  popd > /dev/null
  echo -e "\nLogs have been collected at ${package_name}"
}

# main
notice

while [[ $# -gt 1 ]]; do
  key="$1"
  case $key in
    --err-log-count)
    err_log_count="$2"
    shift
    ;;
    *)
    ;;
  esac
  shift
done

check_dependency
check_version_and_auth

echo -e "Collecting logs. logs will be collected to ${WORK_DIR}"
collect_bosh_logs

check_deployment
if [[ $? == 0 ]]; then
  get_err_vms
  collect_job_logs
  collect_bosh_agent_logs
  collect_system_logs
else
  echo "[Warn]: No deployment is set, will NOT collect error logs from VMs."
fi

echo -e "Compressing files..."
package_logs
