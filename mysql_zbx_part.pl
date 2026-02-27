#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use DateTime;

# the Dockerfile will change the value to 1 in the container build process
my $is_container = 0;

# initializing some variables
my $db_schema;
my $db_host;
my $db_port;
my $dsn;
my $db_user_name;
my $db_password;
my $curr_tz;

# pick DBI driver at runtime (mysql or MariaDB)
my $db_driver = 'MariaDB';

if ($is_container) {
	# check if environment variables exists
	if (not defined $ENV{'DB_HOST'}
		or not defined $ENV{'DB_PORT'}
		or not defined $ENV{'DB_DATABASE'}
		or not defined $ENV{'DB_USER'}
		or not defined $ENV{'DB_PASSWORD'}
		or not defined $ENV{'LOG_PATH'}
		or not defined $ENV{'TZ'}
	) {
		print "Environment variables are missing! Exiting...\n";
		exit 1;
	}

	# open log file
	open( OUTPUT, ">>", $ENV{'LOG_PATH'} ) or die $!;

	# do not manually modify the next lines, they are only used when the script is run in a container
	$db_schema    = $ENV{'DB_DATABASE'};
	$db_host      = $ENV{'DB_HOST'};
	$db_port      = $ENV{'DB_PORT'};
	$db_user_name = $ENV{'DB_USER'};
	$db_password  = $ENV{'DB_PASSWORD'};
	$curr_tz      = $ENV{'TZ'};

	# optional driver override in container (mysql or MariaDB)
	# Example: DB_DRIVER=MariaDB
	$db_driver = $ENV{'DB_DRIVER'} if defined $ENV{'DB_DRIVER'};
}
else {
	use Sys::Syslog qw(:standard :macros);
	openlog("mysql_zbx_part", "ndelay,pid", LOG_LOCAL0);

	# edit login and timezone information if the script is run directly in your server (not for Docker)
	$db_schema    = 'zabbix';
	$db_user_name = 'zabbix';
	$db_password  = 'password';
	$curr_tz      = 'Etc/UTC';             #For example 'Europe/Amsterdam'

	# optional driver override outside container too, if you want it
	$db_driver = $ENV{'DB_DRIVER'} if defined $ENV{'DB_DRIVER'};
}

# normalize driver name (DBI wants MariaDB with that exact casing)
sub normalize_driver {
	my $d = shift // 'mysql';
	return 'MariaDB' if lc($d) eq 'mariadb';
	return 'mysql'   if lc($d) eq 'mysql';
	# fallback: accept whatever was provided
	return $d;
}

$db_driver = normalize_driver($db_driver);

# build DSN in key/value style (portable across DBD::mysql and DBD::MariaDB)
if ($is_container) {
	$dsn = 'DBI:'.$db_driver.':database='.$db_schema.';host='.$db_host.';port='.$db_port;
}
else {
	# socket attribute depends on the DBD driver
	my $socket_attr = (lc($db_driver) eq 'mariadb') ? 'mariadb_socket' : 'mysql_socket';
	$dsn = 'DBI:'.$db_driver.':database='.$db_schema.';'.$socket_attr.'=/var/lib/mysql/mysql.sock';
}

my $tables = {  'history' => { 'period' => 'day', 'keep_history' => '60'},
                'history_log' => { 'period' => 'day', 'keep_history' => '60'},
                'history_str' => { 'period' => 'day', 'keep_history' => '60'},
                'history_text' => { 'period' => 'day', 'keep_history' => '60'},
                'history_uint' => { 'period' => 'day', 'keep_history' => '60'},
# Comment the history_bin line below if you're running Zabbix versions older than 7.0
                'history_bin' => { 'period' => 'day', 'keep_history' => '60'},
                'trends' => { 'period' => 'month', 'keep_history' => '12'},
                'trends_uint' => { 'period' => 'month', 'keep_history' => '12'},

# comment next 5 lines if you partition zabbix database starting from 2.2
# they usually used for zabbix database before 2.2

#		'acknowledges' => { 'period' => 'month', 'keep_history' => '23'},
#		'alerts' => { 'period' => 'month', 'keep_history' => '6'},
#		'auditlog' => { 'period' => 'month', 'keep_history' => '24'},
#		'events' => { 'period' => 'month', 'keep_history' => '12'},
#		'service_alarms' => { 'period' => 'month', 'keep_history' => '6'},
		};
my $amount_partitions = 10;

# name templates for the different periods
my $partition_name_templates = { 'day' => 'p%Y_%m_%d',
		'week' => 'p%Y_w%V',
		'month' => 'p%Y_%m',
	};

my $part_tables;

# connect with sane DBI attributes
my %dbi_attrs = (
	RaiseError => 1,
	PrintError => 0,
	AutoCommit => 1,
);

# Only set mysql-specific attrs when using DBD::mysql
if (lc($db_driver) eq 'mysql') {
	$dbi_attrs{mysql_enable_utf8mb4} = 1;
}

my $dbh = DBI->connect($dsn, $db_user_name, $db_password, \%dbi_attrs);

unless ( check_have_partition() ) {
	print "Your installation of MySQL does not support table partitioning.\n";
	log_writer('Your installation of MySQL does not support table partitioning.', LOG_CRIT);
	exit 1;
}

my $sth = $dbh->prepare(qq{SELECT table_name as table_name, partition_name as partition_name,
       				lower(partition_method) as partition_method,
				rtrim(ltrim(partition_expression)) as partition_expression,
				partition_description as partition_description, table_rows
				FROM information_schema.partitions
				WHERE partition_name IS NOT NULL AND table_schema = ?});
$sth->execute($db_schema);

while (my $row =  $sth->fetchrow_hashref()) {
	$part_tables->{$row->{'table_name'}}->{$row->{'partition_name'}} = $row;
}

$sth->finish();

foreach my $key (sort keys %{$tables}) {
	unless (defined($part_tables->{$key})) {
		log_writer('Partitioning for "'.$key.'" is not found! The table might be not partitioned.', LOG_ERR);
		next;
	}

	create_next_partition($key, $part_tables->{$key}, $tables->{$key}->{'period'});
	remove_old_partitions($key, $part_tables->{$key}, $tables->{$key}->{'period'}, $tables->{$key}->{'keep_history'})
}

delete_old_data();

$dbh->disconnect();

sub check_have_partition {
	# Minimal + driver-agnostic: if information_schema.partitions is queryable,
	# partition support is effectively present (or permissions exist).
	my $sth;
	my $ok = eval {
		$sth = $dbh->prepare('SELECT 1 FROM information_schema.partitions LIMIT 1');
		$sth->execute();
		1;
	};
	eval { $sth->finish() if $sth; };
	return $ok ? 1 : 0;
}

sub create_next_partition {
	my $table_name = shift;
	my $table_part = shift;
	my $period = shift;

	for (my $curr_part = 0; $curr_part < $amount_partitions; $curr_part++) {
		my $next_name = name_next_part($period, $curr_part);

		if (grep { $_ eq $next_name } keys %{$table_part}) {
			log_writer("Next partition for $table_name table has already been created. It is $next_name", LOG_INFO);
		}
		else {
			log_writer("Creating a partition for $table_name table ($next_name)", LOG_INFO);
			my $query = 'ALTER TABLE '."$db_schema.$table_name".' ADD PARTITION (PARTITION '.$next_name.
						' VALUES less than (UNIX_TIMESTAMP("'.date_next_part($period, $curr_part).'") div 1))';
			log_writer($query, LOG_DEBUG);
			$dbh->do($query);
		}
	}
}

sub remove_old_partitions {
	my $table_name = shift;
	my $table_part = shift;
	my $period = shift;
	my $keep_history = shift;

	my $curr_date = DateTime->now( time_zone => $curr_tz );

	$curr_date->subtract($period.'s' => $keep_history);
	$curr_date->truncate(to => $period);

	foreach my $partition (sort keys %{$table_part}) {
		if ($table_part->{$partition}->{'partition_description'} <= $curr_date->epoch) {
			log_writer("Removing old $partition partition from $table_name table", LOG_INFO);

			my $query = "ALTER TABLE $db_schema.$table_name DROP PARTITION $partition";

			log_writer($query, LOG_DEBUG);
			$dbh->do($query);
		}
	}
}

sub name_next_part {
	my $period = shift;
	my $curr_part = shift;

	unless (defined $partition_name_templates->{$period}) {
		die "unsupported partitioning period '$period'\n";
	}

	my $curr_date = DateTime->now( time_zone => $curr_tz );

	$curr_date->truncate( to => $period );
	$curr_date->add( $period.'s' => $curr_part );

	return $curr_date->strftime($partition_name_templates->{$period});
}

sub date_next_part {
	my $period = shift;
	my $curr_part = shift;

	my $curr_date = DateTime->now( time_zone => $curr_tz );

	$curr_date->truncate( to => $period );
	$curr_date->add( $period.'s' => 1 + $curr_part );

	return $curr_date->strftime('%Y-%m-%d');
}

sub delete_old_data {
	$dbh->do("DELETE FROM sessions WHERE lastaccess < UNIX_TIMESTAMP(NOW() - INTERVAL 1 MONTH)");
	$dbh->do("DELETE FROM housekeeper WHERE `tablename` !='events'");

# Uncomment the following line for Zabbix 5.4 and earlier
#	$dbh->do("DELETE FROM auditlog_details WHERE NOT EXISTS (SELECT NULL FROM auditlog WHERE auditlog.auditid = auditlog_details.auditid)");
}

sub log_writer {
	my $log_line = shift;

	if ($is_container) {
		print OUTPUT $log_line . "\n";
	}
	else {
		my $log_priority = shift;
		syslog($log_priority, $log_line);
	}
}
