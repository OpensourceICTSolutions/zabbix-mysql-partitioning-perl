## Important notes:

Follow the instructions in the [main README](../README.md) to uncomment the correct lines of the script to make it work with your database environment.

Assuming you are in the root directory of this Git repository, enter the docker directory:

```
cd docker
```

# Zabbix MySQL partitioning Perl script - Docker

Allows you to run the Zabbix database partitioning script through a container.

## Build Docker image

Edit the Dockerfile and uncomment the `ZABBIX_REPOSITORY` argument line according to your Docker host architecture (x86_64 or arm64).

Then build the Docker image:

```
docker build -t zabbix-db-partitioning .
```

## Create log directory

This folder will be mounted as a volume in the container, thus persisting the logs for future reference.

```
mkdir logs
chgrp 999 logs/
chmod 775 logs/
```

## Configure .env file

Create the `.env` file based on the [template](.env.example) and edit it as per your environment.

```
cp .env.example .env
chown root. .env
chmod 400 .env
```

## The Docker command

This command runs the container to perform the partitioning tasks and, when the perl script finishes executing, the container is automatically stopped and deleted.

Change `project_dir` to the directory where you ran the "git clone" of this repository.

```
docker run --rm \
  --name zabbix-db-partitioning \
  -v /project_dir/docker/logs:/logs \
  --env-file /project_dir/docker/.env \
  zabbix-db-partitioning \
  sh -c 'exec zabbix_exec_db_partitioning.sh >> $LOG_PATH 2>&1'
```

## Crontab

Edit crontab:

```
crontab -e
```

Add the line in the crontab, adjusting the schedule.

Change `project_dir` to the root directory of this Git repository on your file system.

```
55 22 * * * docker run --rm --name zabbix-db-partitioning -v /project_dir/docker/logs:/logs --env-file /project_dir/docker/.env zabbix-db-partitioning sh -c 'exec zabbix_exec_db_partitioning.sh >> $LOG_PATH 2>&1'
```

## Zabbix Template

To monitor Perl script execution:

- Import the [zbx_mysql_partitioning_template.yaml](zbx_mysql_partitioning_template.yaml) template into your Zabbix;
- Add the template to an existing host or create a new host;
- Configure the `zabbix_sender` variables in the `.env` file;

With that the container will send the result of executing the Perl script to your Zabbix and a trigger will be fired if an error occurs or if the script has not been executed in the last 2 days.