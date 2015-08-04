FROM ubuntu:14.04

MAINTAINER Manel Martinez <manel@nixelsolutions.com>

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y python-software-properties software-properties-common
RUN add-apt-repository -y ppa:gluster/glusterfs-3.5 && \
    apt-get update && \
    apt-get install -y php5-fpm php5-mysql php-apc supervisor glusterfs-client curl haproxy pwgen unzip mysql-client dnsutils
RUN add-apt-repository -y ppa:mc3man/trusty-media && \
    apt-get update && \
    apt-get install -y ffmpeg dpkg-dev git && \
    apt-get source nginx && \
    apt-get -y build-dep nginx

ENV SQLBUDDY_URL https://github.com/lavvy/sqlbuddy/archive/v1.0.0.tar.gz
ENV GLUSTER_VOL ranchervol
ENV GLUSTER_VOL_PATH /var/www
ENV HTTP_PORT 80
ENV RTMP_PORT 1935
ENV HTTP_DOCUMENTROOT ${GLUSTER_VOL_PATH}
ENV DEBUG 0

ENV DB_USER root
ENV DB_PASSWORD **ChangeMe**
ENV DB_HOST db
ENV GLUSTER_HOST storage

RUN mkdir -p /var/log/supervisor ${GLUSTER_VOL_PATH} /usr/src/nginx
WORKDIR ${GLUSTER_VOL_PATH}

RUN cd /usr/src/nginx && sudo git clone https://github.com/arut/nginx-rtmp-module.git
RUN cd /nginx-* && perl -p -i -e "s/ngx_http_substitutions_filter_module \\\/ngx_http_substitutions_filter_module \\\\\n            --add-module=\/usr\/src\/nginx\/nginx-rtmp-module \\\/g" debian/rules
RUN cd /nginx-* && dpkg-buildpackage -b
RUN dpkg --install /nginx-common_* /nginx-full_*
RUN rm -rf /nginx-*

RUN mkdir -p /usr/local/bin
ADD ./bin /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh
ADD ./etc/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ./etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg
ADD ./etc/nginx/sites-enabled/sqlbuddy /etc/nginx/sites-enabled/sqlbuddy

# nginx config
RUN sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf
RUN sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf
RUN echo "daemon off;" >> /etc/nginx/nginx.conf
RUN rm -f /etc/nginx/sites-enabled/default

# php-fpm config
RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/fpm/php.ini
RUN sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php5/fpm/php.ini
RUN sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php5/fpm/php.ini
RUN sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php5/fpm/php-fpm.conf

# HAProxy
RUN perl -p -i -e "s/ENABLED=0/ENABLED=1/g" /etc/default/haproxy

CMD ["/usr/local/bin/run.sh"]
