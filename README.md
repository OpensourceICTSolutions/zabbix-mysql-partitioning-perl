# Zabbix MySQL partitioning perl script

Disclaimer: This script isn't made by us, but the current author is unknown. We've added it to Github for ease of access. If you are the original creator of this script, please send us a private message. With that out of the way, let's move on.

Important notes/bugs: 
                    #1 The script is no longer working for MySQL 8. Use MariaDB or check out the stored procedures in the guide below.

Welcome to the Opensource ICT Solutions GitHub, where you'll find all kinds of usefull Zabbix resources. This script is a script written in Perl to partition the Zabbix database tables in time based chunks. We can use this script to replace the Zabbix housekeeper process which tends to get too slow once you hit a certain database size.

With the use of MySQL partitioing using fixed History and Trend storage periods for all items we can mitigate this issue and grow our Zabbix database even further.

## How to use the script
Make sure to partition the database first, if you do not know how. Check out this blog post:
https://blog.zabbix.com/partitioning-a-zabbix-mysql-database/13531/

Or check out our Zabbix book for a detailed description:
https://www.amazon.com/Zabbix-Infrastructure-Monitoring-Cookbook-maintaining/dp/1800202237


Place the script in:
```
/usr/share/zabbix/
```

Then make it executable with:
```
chmod +x /usr/share/zabbix/mysql_zbx_part.pl
```

Now add a cronjob with:
```
crontab -e
```

Add the following line:
```
0 23 * * * /usr/share/zabbix/mysql_zbx_part.pl >/dev/null 2>&1
```

We also need to install some Perl dependencies with:

```
yum install perl-DateTime perl-Sys-Syslog

```

or on Debian based systems
```
apt-get install libdatetime-perl liblogger-syslog-perl
```


That's it! You are now done and you have setup MySQL partitioing. We could execute the script manually with:
```
perl /usr/share/zabbix/mysql_zbx_part.pl
```

Then we can check and see if it worked with:
```
journalctl -t mysql_zbx_part
```
