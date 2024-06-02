## Important notes/bugs: 

#1 The script is FIXED for MySQL 8. It works for both MySQL and MariaDB latest versions and should still work with older versions as well.

#2 The weekly partitioning is FIXED. Thanks @beinvisible

#3 Zabbix 6 removed the auditlog_details table. The script is compatible with this version now, make sure to uncomment the fix for older Zabbix versions.

#4 For RHEL9 based systems use the CRB repository (Rocky Linux 9 specific) to get Perl-DataTime. dnf config-manager --set-enabled crb

#5 For ZBX7.0 a new table was added (history_bin). As such, for older version we can comment the line that partitions this table.

Make sure to uncomment the correct lines (see blog post), the default is setup for MySQL 5.6 or MariaDB and Zabbix version higher than 7.0.

Also, see common issues at the bottom of the blog post.

# Zabbix MySQL partitioning Perl script

Disclaimer: This script isn't made by us, the original author is https://github.com/dotneft and the script was initially (slightly) modified by Rihards Olups. We've added it to Github so we can maintain it and provide easy access to the entire Zabbix community.

Welcome to the Opensource ICT Solutions GitHub, where you'll find all kinds of useful Zabbix resources. This script is a script written in Perl to partition the Zabbix database tables in time based chunks. We can use this script to replace the Zabbix housekeeper process which tends to get too slow once you hit a certain database size.

With the use of MySQL partitioing using fixed History and Trend storage periods for all items we can mitigate this issue and grow our Zabbix database even further.

## How to use the script
Make sure to partition the database first. If you do not know how, check out this blog post:
https://blog.zabbix.com/partitioning-a-zabbix-mysql-database/13531/

Or check out our Zabbix book for a detailed description:
https://www.amazon.com/Zabbix-Infrastructure-Monitoring-Cookbook-maintaining/dp/1801078327

MAKE SURE TO UNCOMMENT THE CORRECT LINES FOR THE VERSION YOU NEED. Check the blog post for more information.
```
# MySQL 5.5
# MySQL 5.6 + MariaDB
# MySQL 8.x (NOT MariaDB!)
```

Uncomment the following line for Zabbix 5.4 and OLDER:
```
#       $dbh->do("DELETE FROM auditlog_details WHERE NOT EXISTS (SELECT NULL FROM auditlog WHERE auditlog.auditid = auditlog_details.auditid)");
```

Comment the following line for Zabbix 6.4 and OLDER:
```
'history_bin' => { 'period' => 'day', 'keep_history' => '60'},
```

[Run directly on your server](#run-directly-on-your-server) or [run in a Docker container](#run-in-a-docker-container).

### Run directly on your server

Place the script in (create the folder if it doesn't exist):
```
/usr/lib/zabbix/
```

Then make it executable with:
```
chmod 750 /usr/lib/zabbix/mysql_zbx_part.pl
```

Now add a cronjob with:
```
crontab -e
```

Add the following line:
```
55 22 * * * /usr/lib/zabbix/mysql_zbx_part.pl >/dev/null 2>&1
```

We also need to install some Perl dependencies with:

```
yum install perl-DateTime perl-Sys-Syslog perl-DBI perl-DBD-mysql

```

If perl-DateTime isn't available on your RHEL based installation make sure to install the powertools repo with:
```
yum config-manager --set-enabled powertools
```
On RHEL 9 based:
```
dnf config-manager --enable crb
```

or for genuine-RedHat:

```
subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms

```
Or Oracle Linux

```
dnf config-manager --set-enabled ol8_codeready_builder
```

On a Debian based systems (like Ubuntu) run:
```
apt-get install libdatetime-perl liblogger-syslog-perl libdbd-mysql-perl
```

That's it! You are now done and you have setup MySQL partitioning. We could execute the script manually with:
```
perl /usr/share/zabbix/mysql_zbx_part.pl
```

Then we can check and see if it worked with:
```
journalctl -t mysql_zbx_part
```

### Run in a Docker container

#1 Assuming you are in the root directory of this Git repository.

Edit the Dockerfile and uncomment the `ZABBIX_REPOSITORY` argument line according to your Docker host architecture (x86_64 or arm64), then build the Docker image:

```
docker build -t zabbix-db-partitioning .
```

Create log directory. This folder will be mounted as a volume in the container, thus persisting the logs for future reference.

```
mkdir logs
sudo chgrp 999 logs/
chmod 775 logs/
```

Create the `.env` file based on the [template](docker/.env.example) and edit it as per your environment.

```
cp docker/.env.example .env
sudo chown root: .env
sudo chmod 400 .env
```

The command below runs the container to perform the partitioning tasks and, when the perl script finishes executing, the container is automatically stopped and deleted.

```
sudo docker run --rm \
  --name zabbix-db-partitioning \
  -v ./logs:/logs \
  --env-file ./.env \
  zabbix-db-partitioning
```

After running the container, you can check the logs:
```
cat logs/mysql_zbx_part.log
```

Edit `root` user crontab:

```
crontab -e
```

Add the line in the crontab, adjusting the schedule. Change `project_dir` to the root directory of this Git repository on your file system.

```
55 22 * * * docker run --rm --name zabbix-db-partitioning -v /project_dir/logs:/logs --env-file /project_dir/.env zabbix-db-partitioning
```

To monitor Perl script execution:

- Import the [zbx_mysql_partitioning_template.yaml](docker/zbx_mysql_partitioning_template.yaml) template into your Zabbix;
- Add the template to an existing host or create a new host;
- Uncomment and configure the `zabbix_sender` variables in the `.env` file;

With that the container will send the result of executing the Perl script to your Zabbix and a trigger will be fired if an error occurs or if the script has not been executed in the last 2 days.

### Partitioning by week
NOTE: See version 2.1 for older (before 20-09-2021) partitioned databases. Otherwise use 3.0+ upwards (recommended to use current).

By default history tables are partitioned by day and trends are partitioned by month. It is also possible to partition both types of tables by **week**.

To do so change the **period** value to **week** under **my $tables =**. Also make sure to use a different naming convention for your partition names (2021_w36) and while partitioning make sure to use the correct UNIXTIMESTAMP.

The weekly partitioning setup IS NOT described in the Zabbix blog.

