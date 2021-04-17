#!/bin/bash

set -eu

readonly DIR_SCRIPT=$(cd $(dirname $0); pwd)
readonly DIR_ROOT_VOLUMES=${DIR_SCRIPT}/volumes
readonly DIR_GITBUCKET_HOME=${DIR_ROOT_VOLUMES}/gitbucket_data

function _mkdir() {
    local _dir=$1
    if [ -d ${_dir} ]; then
        echo "skip mkdir ${_dir}"
    else
        mkdir -p ${_dir}
        echo "mkdir ${_dir}"
    fi
}

function _start_operation()
{
cat << EOF

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ $*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
}


function _download_plugin()
{
    local _url=$1
    local _jar=${_url##*/}
    local _dir_plugins=${DIR_GITBUCKET_HOME}/plugins
    local _file_tmp=${DIR_SCRIPT}/tmp.jar
    local _file_dst=${_dir_plugins}/${_jar}

    if [ -f ${_file_dst} ]; then
        echo "skip download ${_url}"
    else
        echo "downloading ${_url} to ${_file_dst}"
        curl -s -L -o ${_file_tmp} ${_url}
        mv ${_file_tmp} ${_file_dst}
    fi
}

function _download_plugin_all()
{
    _start_operation "download gitbucket plugins."

    _download_plugin https://github.com/jyuch/gitbucket-backup-plugin/releases/download/1.2.3/gitbucket-backup-plugin-1.2.3.jar
    _download_plugin https://github.com/kasancode/gitbucket-label-kanban-plugin/releases/download/3.7.0/gitbucket-label-kanban-plugin-3.7.0.jar
    _download_plugin https://github.com/codelibs/gitbucket-fess-plugin/releases/download/gitbucket-fess-plugin-1.7.0/gitbucket-fess-plugin_2.13-1.7.0.jar
    _download_plugin https://github.com/onukura/gitbucket-rmarkdown-plugin/releases/download/1.0.0/gitbucket-rmarkdown-plugin_2.13-1.0.0.jar
    _download_plugin https://github.com/onukura/gitbucket-mathjax-plugin/releases/download/1.0.4/gitbucket-mathjax-plugin_2.13-1.0.4.jar
    _download_plugin https://github.com/onukura/gitbucket-csvtsv-plugin/releases/download/1.0.5/gitbucket-csvtsv-plugin_2.13-1.0.5.jar
    _download_plugin https://github.com/gitbucket-plugins/gitbucket-explorer-plugin/releases/download/9.0.0/gitbucket-explorer-plugin-9.0.0.jar
    _download_plugin https://github.com/kounoike/gitbucket-ipynb-plugin/releases/download/v0.4.2/gitbucket-ipynb-plugin-0.4.2.jar
}

function _mk_volume_all()
{
    _start_operation "make directory for docker"

    _mkdir ${DIR_ROOT_VOLUMES}/gitbucket_data
    _mkdir ${DIR_ROOT_VOLUMES}/gitbucket_data/backup
    _mkdir ${DIR_ROOT_VOLUMES}/gitbucket_data/plugins
    _mkdir ${DIR_ROOT_VOLUMES}/postgres_data
}

function _mk_backup_conf()
{
    _start_operation "make backup.conf for gitbucket"

    local _file_conf=${DIR_GITBUCKET_HOME}/backup.conf

    if [ -f ${_file_conf} ]; then
        echo "skip make ${_file_conf}"
    fi

cat << EOF > ${_file_conf}
# Backup timing (Required)
# For details, see http://www.quartz-scheduler.org/documentation/quartz-2.3.0/tutorials/crontrigger.html
# and https://github.com/enragedginger/akka-quartz-scheduler/blob/master/README.md
# This example, backup 12am every day
akka {
  quartz {
    schedules {
      Backup {
        expression = "0 0 3 * * ?"
        timezone = "Asia/Tokyo"
      }
    }
  }
}

backup {
  # Backup archive destination directory (Optional)
  # If not specified, archive is saved into GITBUCKET_HOME
  #archive-destination = """/path/to/archive-dest-dir"""
  archive-destination = """/gitbucket/backup"""

  # Maximum number of backup archives to keep (if 0 or negative value, keep unlimited) (Optional)
  # If not specified, keep unlimited
  archive-limit = 10

  # Send notify email when backup is success (Optional, default:false)
  #notify-on-success = true

  # Send notify email when backup is failure (Optional, default:false)
  #notify-on-failure = true

  # Notify email destination (Optional)
  #notify-dest = ["jyuch@localhost"]

  # S3 compatible object storage for backup upload (Optional)
#  s3 {
#    # Endpoing URL
#    endpoint = "http://localhost:9000"
#
#    # Region
#    region = "US_EAST_1"
#
#    # Access key
#    access-key = "access-key"
#
#    # Secret key
#    secret-key = "secret-key"
#
#    # Bucket of backup destination
#    bucket = "gitbucket"
#  }
}
EOF
}

function _print_usage()
{
cat << EOF
------------------------------------------------------------
- usage
- $0 <host name> <context name> <gitbucket port>
- 
- http://<host name>/<context name>/gitbucket/
------------------------------------------------------------
EOF
}

function _mk_conf()
{
    if [ -f ${DIR_SCRIPT}/.env ]; then
        echo "already exist .env"
        return 0
    fi

    if [ $# -lt 3 ]; then
        _print_usage $*
        exit 1
    fi

    _start_operation "make .env for docker-compose and conf for nginx"

    local _host_name=$1
    local _context_path=$2
    local _gitbucket_port=$3

    local _dir_conf=${DIR_SCRIPT}/conf
    local _dir_nginx_conf=${_dir_conf}/nginx
    local _file_docker_compose_env=${_dir_conf}/docker_compose.env
    local _file_gitbucket_nginx_conf=${_dir_nginx_conf}/${_gitbucket_port}_${_context_path}_gitbucket.conf

    echo ${_dir_nginx_conf}
    _mkdir ${_dir_nginx_conf}

cat << EOF > ${_file_docker_compose_env}
# gitbucket base url
HOST_NAME=${_host_name}
CONTEXT_PATH=${_context_path}

# gitbucket port
GITBUCKET_PORT=${_gitbucket_port}

# gitbucket base url
GITBUCKET_BASE_URL=http://\${HOST_NAME}/\${CONTEXT_PATH}/gitbucket
EOF

ln -sf conf/docker_compose.env ${DIR_SCRIPT}/.env

cat << EOF > ${_file_gitbucket_nginx_conf}
location /${_context_path}/gitbucket/ {
    proxy_pass              http://127.0.0.1:${_gitbucket_port}/;
    proxy_set_header        Host \$host;
    proxy_set_header        X-Real-IP \$remote_addr;
    proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_connect_timeout   150;
    proxy_send_timeout      100;
    proxy_read_timeout      100;
    proxy_buffers           4 32k;
    client_max_body_size    500m; # Big number is we can post big commits.
    client_body_buffer_size 128k;
}
EOF

}

_mk_conf $*

_mk_volume_all

_mk_backup_conf

_download_plugin_all
