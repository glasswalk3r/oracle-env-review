#!/bin/bash
# this Bash script will search for Weblogic process running Weblogic Console
# if it was found, it will execute the weblock.version Java program to print to
# STDOUT the Weblogic version and patches installed
# There are some optional command arguments line arguments like
# -f <path to fifo>: the script will print results (only the output line with
# PSU information) to the named pipe instead to STDOUT

function warn() {
    msg=$1
    echo $msg >&2
}

function join_array { local IFS="$1"; shift; echo "$*"; }

function config_env() {
    config_file="$1"
    if [ -r "${config_file}" ]
    then
        . "${config_file}" > /dev/null
    else
        warn "Configuration file '"${config_file}"' does not exist or is not readable, aborting..."
        exit 1
    fi
}

function print_details() {
    jvm=$1
    server=$2
    temp_file=$(mktemp)
    java weblogic.version | sed -e '/^Use/ d' | perl -e 'unless(/^\n$/) { print $_ }' -n | sort | uniq > "${temp_file}"
    declare -a bugs
    declare -a app
    while read line
    do
        case "${line}" in
            *PSU*)
                PSU=$(echo "${line}" | awk '{print $3}')
                ;;
            *Temporary*)
                temp_data=$(echo "${line}" | awk '{print $6}')
                bugs+=(${temp_data##BUG})
                ;;
            *)
                app=($(echo ${line}))
                ;;
        esac
    done < "${temp_file}"

    rm -f "${temp_file}"
    bugs_list=$(join_array : "${bugs[@]}")
    jvm_info=$(print_jvm "${jvm}")
    info="${app[0]} ${app[1]}#${app[2]}#${PSU}#${bugs_list}#${server}#${jvm_info}"
    echo "${info}"
}

function print_jvm() {
    jvm=${1}
    classpath='/ood_repository/environment_review'
    message=$("${jvm}" -classpath "${classpath}" JavaArch 2> /dev/null)

    if [ $? -eq 0 ]
    then
        echo "${message}"
    else
        "${jvm}" -classpath "${classpath}" JavaArchRockit
    fi
}

while getopts ":f:" opt; do
  case $opt in
    f)
      FIFO=("${OPTARG}")
      ;;
    :)
      warn "Option -$OPTARG requires an argument."
      exit 1
      ;;
    \?)
      warn "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

if [ -z ${ENV_CONFIG} ]
then
    # 0 = JVM PID, 1 = java path
    old=$IFS
    IFS=$'\n'
    data=()

    for line in $(ps aux | grep 'Dweblogic.Name=' | awk '$0 !~ /grep/ {for(i=12;i<=NF;i++){if($i ~ /^\-Dweblogic\.Name=/){split($i,a,"="); print $2,$11,a[2];break;}}}')
    do
        IFS=$old
        declare -a weblogic_info
        read -a weblogic_info <<< "${line}"
        weblogic_info[2]=$(echo ${weblogic_info[2]} | sed -e 's/\-Dweblogic\.Name\=//')

        if [ ${weblogic_info[0]} ]
        then
            WL_HOME=$(xargs --null --max-args=1 echo < /proc/${weblogic_info[0]}/environ | grep WL_HOME | cut -d '=' -f2)

            if [ ${WL_HOME} ]
            then
                config_env "${WL_HOME}/server/bin/setWLSEnv.sh"
                temp=$(print_details ${weblogic_info[1]} ${weblogic_info[2]})
                data+=("$temp")
            else
                warn "Could not find WL_HOME location, cannot continue"
            fi

        fi

    done

    # give some time for programs to reach out for pipe
    sleep 5

    if [ -n "${FIFO}" -a -p "${FIFO}" -a -w "${FIFO}" ]
    then
        for entry in "${data[@]}"
        do
            echo ${entry} > ${FIFO}
        done
    else
        for entry in "${data[@]}"
        do
            echo ${entry}
        done
    fi

fi
