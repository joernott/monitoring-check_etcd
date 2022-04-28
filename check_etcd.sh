#!/bin/bash
# check_etcd checks etcd health using various methods:
# etcdctl --cluster-health
# curl to the metrics endpoint
PROTO="https"
HOST="localhost"
PORT=2379
WARN=""
CRIT=""
ETCDCTL=1
CURL=1
STATE=0
MESSAGE=""
GATHER_METRICS=()
RE='^[0-9]+$'

function usage() {
  cat <<EOF
Usage: $0 -w num -c num [-H host] [ -P port] [-S] [-n] [-N] [-m "label|type|warn|crit|match"]
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
EOF
}

function init() {
  if ! [[ ${WARN} =~ ${RE} ]]; then
    echo "UNKNOW: You need to provide a value WARN threshold"
    exit 3
  fi
  if ! [[ ${CRIT} =~ ${RE} ]]; then
    echo "UNKNOW: You need to provide a value for the CRIT threshold"
    exit 3
  fi
  if [ ! -d "/var/tmp/check_etcd" ]; then
    mkdir -p "/var/tmp/check_etcd"
  fi

}

function check_range() {
    local COUNT
    local RANGE
    local POS
    COUNT=$1
    RANGE="$2"
    MIN=""
    MAX=""
    POS=$(awk -v a="${RANGE}" -v b=":" 'BEGIN{print index(a,b)}')
    if [ ${POS} -le 1 ]; then
        if ! [[ ${RANGE} =~ ${RE} ]]; then
          echo "UNKNOWN: Illegal range ${RANGE}"
          exit 3
        fi
        MIN=${RANGE}
        MAX=${RANGE}
        if [ ${COUNT} -gt ${RANGE} ] || [ ${COUNT} -lt 0 ]; then
            return 1
        else
            return 0
        fi
    fi
    MIN=$(echo ${RANGE}|awk -F":" '{print $1}')
    if [ -n "${MIN}" ]; then
      if ! [[ ${MIN} =~ ${RE} ]]; then
        echo "UNKNOWN: Illegal min value ${MIN} in range ${RANGE}"
        exit 3
      fi
    fi
    MAX=$(echo ${RANGE}|awk -F":" '{print $2}')
    if [ -n "${MAX}" ]; then
      if ! [[ ${MAX} =~ ${RE} ]]; then
        echo "UNKNOWN: Illegal max value ${MAX} in range ${RANGE}"
        exit 3
      fi
    fi
    if [ -n "${MIN}" ]; then
      if [ ${COUNT} -lt ${MIN} ]; then
        return 1
      fi
    fi
    if [ -n "${MAX}" ]; then
        if [ ${COUNT} -gt ${MAX} ]; then
              return 1
        fi
    fi
    return 0
}

function check_etcdctl(){
  local RESULT
  local COUNT
  local CLUSTER_STATE
  RESULT=$(etcdctl --endpoint "${PROTO}://${HOST}:${PORT}" cluster-health)
  COUNT=$(echo "${RESULT}"|grep -c "is healthy:")
  echo "${RESULT}"|grep "cluster is healthy" &>/dev/null
  if [[ $? -ne 0 ]]; then
    if [ ${STATE} -lt 2 ] ; then
      STATE=2
    fi
    MESSAGE="${MESSAGE}\nCritical: Cluster is not healthy|cluster_health=0;;;;"
  else
    MESSAGE="${MESSAGE}\nOK: Cluster is healthy|cluster_health=1;;;;"
  fi

  if ! check_range ${COUNT} "${CRIT}:"; then
    STATE=2
    MESSAGE="${MESSAGE}\nCritical: Got ${COUNT} healthy members, expected >${CRIT}.|members=${COUNT};${WARN};${CRIT};;"
  else
    if ! check_range ${COUNT} "${WARN}:"; then
      if [ ${STATE} -lt 1 ] ; then
        STATE=1
      fi
      MESSAGE="${MESSAGE}\nWarning: Got ${COUNT} healthy members, expected >${WARN}.|members=${COUNT};${WARN};${CRIT};;"
    else
      MESSAGE="${MESSAGE}\nOK: Got ${COUNT} healthy members.|members=${COUNT};${WARN};${CRIT};;"
    fi
  fi
}

function get_val() {
  local MATCH
  local FILE
  local DATA
  local RESULT
  FILE="$1"
  MATCH="$2"
  DATA=$(grep -vE "^# " "${FILE}"|grep "${MATCH}")
  RESULT=$?
  printf -v VALUE "%.f" "$(echo "${DATA}"|awk '{print $2}')"
  if [ ${RESULT} -ne 0 ]; then
    # If the statistics is missing in the file, we consider it OK as some of them only appear conditionally
    VALUE=0
    RESULT=0
  fi
  return ${RESULT}
}

function check_curl() {
  local METRIC
  if [ -f "/var/tmp/check_etcd/current" ]; then
    mv "/var/tmp/check_etcd/current" "/var/tmp/check_etcd/previous"
  fi
  curl -sSL "${PROTO}://${HOST}:${PORT}/metrics" >"/var/tmp/check_etcd/current"
  RESULT=$?
  if [ ${RESULT} -ne 0 ]; then
    MESSAGE="${MESSAGE}\nCritical: Curl returned ${RESULT}.|curl=${RESULT};0;0;;"
    if [ ${STATE} -lt 2 ] ; then
      STATE=2
    fi
  else
    MESSAGE="${MESSAGE}\nOK: Curl successful.|curl=${RESULT};0;0;;"
  fi
  for METRIC in "${GATHER_METRICS[@]}"; do
    local LABEL
    local MTYPE
    local MWARN
    local MCRIT
    local MATCH
    local CURRENT
    local PREVIOUS
    LABEL=$(echo "${METRIC}"|awk -F '|' '{print $1}')
    MTYPE=$(echo "${METRIC}"|awk -F '|' '{print $2}')
    MWARN=$(echo "${METRIC}"|awk -F '|' '{print $3}')
    MCRIT=$(echo "${METRIC}"|awk -F '|' '{print $4}')
    MATCH=$(echo "${METRIC}"|awk -F '|' '{print $5}'|sed -e 's|"|\\\"|g')
    if [ -z "${MTYPE}" ]; then
      MTYPE="value"
    fi
    get_val "/var/tmp/check_etcd/current" "${MATCH}"
    RESULT=$?
    CURRENT=${VALUE}
    if [ "${MTYPE}" == "delta" ]; then
      if [ ! -f "/var/tmp/check_etcd/previous" ]; then
        PREVIOUS=0
      else
        get_val "/var/tmp/check_etcd/previous" "${MATCH}"
        RESULT=$?
        PREVIOUS=${VALUE}
      fi
    fi
    VALUE=$(( CURRENT - PREVIOUS ))
    if ! check_range ${VALUE} "${MCRIT}"; then
      STATE=2
      MESSAGE="${MESSAGE}\nCritical: Got ${VALUE} for ${LABEL}, should match ${MCRIT}.|${LABEL}=${VALUE};${MWARN};${MCRIT};;"
    else
      if ! check_range ${VALUE} "${MWARN}"; then
        if [ ${STATE} -lt 1 ] ; then
          STATE=1
        fi
        MESSAGE="${MESSAGE}\nWarning: Got ${VALUE} for ${LABEL}, should match ${MWARN}.|${LABEL}=${VALUE};${MWARN};${MCRIT};;"
      else
        MESSAGE="${MESSAGE}\nOK: Got ${VALUE} for ${LABEL}.|${LABEL}=${VALUE};${MWARN};${MCRIT};;"
      fi
    fi
  done
}


while [[ -n "$1" ]]; do
    case $1 in
      --help) usage ; exit 0 ;;
      -h) usage ; exit 0 ;;
      -H) HOST=$2; shift ;;
      -n) ETCDCTL=0 ;;
      -N) CURL=0 ;;
      -P) PORT=$2; shift ;;
      -S) PROTO="http" ;;
      -w) WARN=$2; shift ;;
      -c) CRIT=$2; shift ;;
      -m) GATHER_METRICS+=("$2")
    esac
    shift
done

init
if [ ${ETCDCTL} -ne 0 ]; then
  check_etcdctl
fi
if [ ${CURL} -ne 0 ]; then
  check_curl
fi
echo -e "${MESSAGE:2}"
exit ${STATE}

