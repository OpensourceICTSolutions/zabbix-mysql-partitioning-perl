FROM ubuntu:22.04

# repo for x86_64
ARG ZABBIX_REPOSITORY=https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu22.04_all.deb
# repo for arm64
#ARG ZABBIX_REPOSITORY=https://repo.zabbix.com/zabbix/6.0/ubuntu-arm64/pool/main/z/zabbix-release/zabbix-release_6.0-5+ubuntu22.04_all.deb

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y libdatetime-perl liblogger-syslog-perl libdbd-mysql-perl libdbi-perl curl tzdata \
  && curl -LO ${ZABBIX_REPOSITORY} \
  && dpkg -i zabbix-release*.deb && rm -f zabbix-release*.deb \
  && apt-get update && apt-get install -y zabbix-sender \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -r -u 999 zabbix

COPY ./docker-entrypoint.sh /usr/local/bin/
COPY ./mysql_zbx_part.pl /usr/local/bin/
COPY ./docker/zabbix_exec_db_partitioning.sh /usr/local/bin/

RUN sed -i 's~my $is_container = 0;~my $is_container = 1;~g' /usr/local/bin/mysql_zbx_part.pl \
  && chmod 755 /usr/local/bin/mysql_zbx_part.pl \
    /usr/local/bin/zabbix_exec_db_partitioning.sh \
    /usr/local/bin/docker-entrypoint.sh

USER zabbix

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
