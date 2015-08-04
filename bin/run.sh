#!/bin/bash

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

# Required variables
if [ -z "${SQLBUDDY_URL}" ]; then
   echo "ERROR: You did not specify "SQLBUDDY_URL" environment variable - Exiting..."
   exit 1
fi
sleep 5
export GLUSTER_HOSTS=`dig +short ${GLUSTER_HOST}`
if [ -z "${GLUSTER_HOSTS}" ]; then
   echo "*** ERROR: Could not determine which containers are part of Gluster service."
   echo "*** Is Gluster service linked with the alias \"${GLUSTER_HOST}\"?"
   echo "*** If not, please link gluster service as \"${GLUSTER_HOST}\""
   echo "*** Exiting ..."
   exit 1
fi
export DB_HOSTS=`dig +short ${DB_HOST}`
if [ -z "${DB_HOSTS}" ]; then
   echo "*** ERROR: Could not determine which containers are part of PXC service."
   echo "*** Is PXC service linked with the alias \"${DB_HOST}\"?"
   echo "*** If not, please link gluster service as \"${DB_HOST}\""
   echo "*** Exiting ..."
   exit 1
fi

# Seems not to be necessary
#if [ "${DB_PASSWORD}" == "**ChangeMe**" -o -z "${DB_PASSWORD}" ]; then
#   echo "ERROR: You did not specify "DB_PASSWORD" environment variable - Exiting..."
#   exit 1
#fi

### Prepare configuration
# nginx config
HTTP_ESCAPED_DOCROOT=`echo ${HTTP_DOCUMENTROOT} | sed "s/\//\\\\\\\\\//g"`
# Seems not to be necessary
#perl -p -i -e "s/HTTP_PORT/${HTTP_PORT}/g" /etc/nginx/sites-enabled/sqlbuddy
#perl -p -i -e "s/HTTP_DOCUMENTROOT/${HTTP_ESCAPED_DOCROOT}/g" /etc/nginx/sites-enabled/sqlbuddy

perl -p -i -e "s/RTMP_PORT/${RTMP_PORT}/g" /etc/nginx/rtmp
perl -p -i -e "s/HTTP_PORT/${HTTP_PORT}/g" /etc/nginx/sites-enabled/http
perl -p -i -e "s/HTTP_DOCUMENTROOT/${HTTP_ESCAPED_DOCROOT}/g" /etc/nginx/sites-enabled/http

ALIVE=0
for glusterHost in ${GLUSTER_HOSTS}; do
    echo "=> Checking if I can reach GlusterFS node ${glusterHost} ..."
    if ping -c 10 ${glusterHost} >/dev/null 2>&1; then
       echo "=> GlusterFS node ${glusterHost} is alive"
       ALIVE=1
       break
    else
       echo "*** Could not reach server ${glusterHost} ..."
    fi
done

if [ "$ALIVE" == 0 ]; then
   echo "ERROR: could not contact any GlusterFS node from this list: ${GLUSTER_HOSTS} - Exiting..."
   exit 1
fi

echo "=> Mounting GlusterFS volume ${GLUSTER_VOL} from GlusterFS node ${glusterHost} ..."
mount -t glusterfs ${glusterHost}:/${GLUSTER_VOL} ${GLUSTER_VOL_PATH}

if [ ! -d ${HTTP_DOCUMENTROOT} ]; then
   mkdir -p ${HTTP_DOCUMENTROOT}
fi

if [ ! -d ${HTTP_DOCUMENTROOT}/sqlbuddy ]; then
   mkdir -p ${HTTP_DOCUMENTROOT}/sqlbuddy
fi

if [ ! -d ${HTTP_DOCUMENTROOT}/data ]; then
   mkdir -p ${HTTP_DOCUMENTROOT}/data
fi

if [ ! -d ${HTTP_DOCUMENTROOT}/static ]; then
   mkdir -p ${HTTP_DOCUMENTROOT}/static
fi

if [ ! -e ${HTTP_DOCUMENTROOT}/index.php ]; then
   echo "=> Installing sqlbuddy in ${HTTP_DOCUMENTROOT}/sqlbuddy - this may take a while ..."
   touch ${HTTP_DOCUMENTROOT}/sqlbuddy/index.php
   wget -O /tmp/sqlbuddy.tar.gz ${SQLBUDDY_URL}
   tar -zxf /tmp/sqlbuddy.tar.gz -C /tmp/
   cp -pr /tmp/sqlbuddy-*/src/* ${HTTP_DOCUMENTROOT}/sqlbuddy/
   rm -rf /tmp/sqlbuddy-*
   chown -R www-data:www-data ${HTTP_DOCUMENTROOT}
fi

if grep "PXC nodes here" /etc/haproxy/haproxy.cfg >/dev/null; then
   PXC_HOSTS_HAPROXY=""
   PXC_HOSTS_COUNTER=0

   for host in `echo ${DB_HOSTS} | sed "s/,/ /g"`; do
      PXC_HOSTS_HAPROXY="$PXC_HOSTS_HAPROXY\n  server pxc$PXC_HOSTS_COUNTER $host check port 9200 rise 2 fall 3"
      if [ $PXC_HOSTS_COUNTER -gt 0 ]; then
         PXC_HOSTS_HAPROXY="$PXC_HOSTS_HAPROXY backup"
      fi
      PXC_HOSTS_COUNTER=$((PXC_HOSTS_COUNTER+1))
   done
   perl -p -i -e "s/DB_PASSWORD/${DB_PASSWORD}/g" /etc/haproxy/haproxy.cfg
   perl -p -i -e "s/.*server pxc.*//g" /etc/haproxy/haproxy.cfg
   perl -p -i -e "s/# PXC nodes here.*/# PXC nodes here\n${PXC_HOSTS_HAPROXY}/g" /etc/haproxy/haproxy.cfg
fi

if [ ! -e ${HTTP_DOCUMENTROOT}/healthcheck.txt ]; then
   echo "OK" > ${HTTP_DOCUMENTROOT}/healthcheck.txt
fi

if [ ! -e ${HTTP_DOCUMENTROOT}/static/stat.xsl ]; then
   cp -p /static/stat.xsl ${HTTP_DOCUMENTROOT}/static/stat.xsl
   chown -R www-data:www-data ${HTTP_DOCUMENTROOT}/static
fi

/usr/bin/supervisord
