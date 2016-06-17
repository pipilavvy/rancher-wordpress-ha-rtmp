#!/bin/bash

echo ${AWSS3User}:${AWSS3Secret} > /etc/passwd-s3fs
chmod 600 /etc/passwd-s3fs
mkdir -p ${MOUNTPOINT}
chmod 777 ${MOUNTPOINT}
sudo s3fs -o allow_other ${BUCKETNAME} ${MOUNTPOINT}
