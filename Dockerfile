FROM phusion/baseimage:0.10.2
MAINTAINER Denys Zhdanov <denis.zhdanov@gmail.com>

RUN apt-get -y update \
  && apt-get -y upgrade \
  && apt-get -y install vim \
  nginx \
  python-dev \
  python-flup \
  python-pip \
  python-ldap \
  expect \
  git \
  memcached \
  sqlite3 \
  libffi-dev \
  libcairo2 \
  libcairo2-dev \
  python-cairo \
  python-rrdtool \
  pkg-config \
  nodejs \
  && rm -rf /var/lib/apt/lists/*

# choose a timezone at build-time
# use `--build-arg CONTAINER_TIMEZONE=Europe/Brussels` in `docker build`
ARG CONTAINER_TIMEZONE
ENV DEBIAN_FRONTEND noninteractive

RUN if [ ! -z "${CONTAINER_TIMEZONE}" ]; \
    then ln -sf /usr/share/zoneinfo/$CONTAINER_TIMEZONE /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata; \
    fi

# fix python dependencies (LTS Django and fadvise)
RUN python -m pip install --upgrade pip && \
  pip install fadvise==6.0.1 && \                                                                                              
  pip install django==1.11.15

# install useful 3rd paty modules
RUN pip install fadvise && \
  pip install msgpack-python

ARG version=1.1.4
ARG whisper_version=${version}
ARG carbon_version=${version}
ARG graphite_version=${version}

ARG whisper_repo=https://github.com/graphite-project/whisper.git
ARG carbon_repo=https://github.com/graphite-project/carbon.git
ARG graphite_repo=https://github.com/graphite-project/graphite-web.git

ARG statsd_version=v0.8.0

ARG statsd_repo=https://github.com/etsy/statsd.git

# install whisper
RUN git clone -b ${whisper_version} --depth 1 ${whisper_repo} /usr/local/src/whisper
WORKDIR /usr/local/src/whisper
RUN python ./setup.py install

# install carbon
RUN git clone -b ${carbon_version} --depth 1 ${carbon_repo} /usr/local/src/carbon
WORKDIR /usr/local/src/carbon
RUN pip install -r requirements.txt \
  && python ./setup.py install

# install graphite
RUN git clone -b ${graphite_version} --depth 1 ${graphite_repo} /usr/local/src/graphite-web
WORKDIR /usr/local/src/graphite-web
RUN pip install -r requirements.txt \
  && python ./setup.py install

# install statsd
RUN git clone -b ${statsd_version} ${statsd_repo} /opt/statsd

# config graphite
ADD conf/opt/graphite/conf/*.conf /opt/graphite/conf/
ADD conf/opt/graphite/webapp/graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
# ADD conf/opt/graphite/webapp/graphite/app_settings.py /opt/graphite/webapp/graphite/app_settings.py
WORKDIR /opt/graphite/webapp
RUN mkdir -p /var/log/graphite/ \
  && PYTHONPATH=/opt/graphite/webapp django-admin.py collectstatic --noinput --settings=graphite.settings

# config statsd
ADD conf/opt/statsd/config_*.js /opt/statsd/

# config nginx
RUN rm /etc/nginx/sites-enabled/default
ADD conf/etc/nginx/nginx.conf /etc/nginx/nginx.conf
ADD conf/etc/nginx/sites-enabled/graphite-statsd.conf /etc/nginx/sites-enabled/graphite-statsd.conf

# init django admin
ADD conf/usr/local/bin/django_admin_init.exp /usr/local/bin/django_admin_init.exp
ADD conf/usr/local/bin/manage.sh /usr/local/bin/manage.sh
RUN chmod +x /usr/local/bin/manage.sh && /usr/local/bin/django_admin_init.exp

# logging support
RUN mkdir -p /var/log/carbon /var/log/graphite /var/log/nginx
ADD conf/etc/logrotate.d/graphite-statsd /etc/logrotate.d/graphite-statsd

# daemons
ADD conf/etc/service/carbon/run /etc/service/carbon/run
ADD conf/etc/service/carbon-aggregator/run /etc/service/carbon-aggregator/run
ADD conf/etc/service/graphite/run /etc/service/graphite/run
ADD conf/etc/service/statsd/run /etc/service/statsd/run
ADD conf/etc/service/nginx/run /etc/service/nginx/run

# default conf setup
ADD conf /etc/graphite-statsd/conf
ADD conf/etc/my_init.d/01_conf_init.sh /etc/my_init.d/01_conf_init.sh

# cleanup
RUN apt-get clean\
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# defaults
EXPOSE 80 2003-2004 2023-2024 8080 8125 8125/udp 8126
VOLUME ["/opt/graphite/conf", "/opt/graphite/storage", "/opt/graphite/webapp/graphite/functions/custom", "/etc/nginx", "/opt/statsd", "/etc/logrotate.d", "/var/log"]
WORKDIR /
ENV HOME /root
ENV STATSD_INTERFACE udp

CMD ["/sbin/my_init"]
