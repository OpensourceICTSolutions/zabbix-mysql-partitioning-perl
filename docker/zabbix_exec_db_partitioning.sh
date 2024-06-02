#!/bin/bash

echo -e "\n$(date '+%Y-%m-%d %H:%M') - Starting script execution..."

# Runs the table partitioning script and sends Zabbix the value 1 (success) or 0 (fail).
/usr/local/bin/mysql_zbx_part.pl \
  && ITEM_VALUE=1 \
  || ITEM_VALUE=0


if [[ -n "${ZABBIX_SERVER}" ]]; then
  /usr/bin/zabbix_sender -z $ZABBIX_SERVER -s "$ZABBIX_HOST" -k "$ZABBIX_ITEM_KEY" -o $ITEM_VALUE
fi
