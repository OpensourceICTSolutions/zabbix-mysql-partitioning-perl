#!/usr/bin/perl
use strict;
use DBI;
use Sys::Syslog qw(:standard :macros);
use DateTime;

openlog("mysql_zbx_part", "ndelay,pid", LOG_LOCAL0);

my $db_schema = 'zabbix';
my $dsn = 'DBI:mysql:'.$db_schema.':mysql_socket=/var/lib/mysql/mysql.sock';
my $db_user_name = 'zabbix';
my $db_password = 'password';
my $tables = {	'history' => { 'period' => 'day', 'keep_history' => '60'},
		'history_log' => { 'period' => 'day', 'keep_history' => '60'},
		'history_str' => { 'period' => 'day', 'keep_history' => '60'},
		'history_text' => { 'period' => 'day', 'keep_history' => '60'},
		'history_uint' => { 'period' => 'day', 'keep_history' => '60'},
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

my $curr_tz = 'Etc/UTC';

# name templates for the different periods
my $partition_name_templates = { 'day' => 'p%Y_%m_%d',
		'week' => 'p%Y_w%W',
		'month' => 'p%Y_%m',
	};

my $part_tables;

my $dbh = DBI->connect($dsn, $db_user_name, $db_password);

unless ( check_have_partition() ) {
	print "Your installation of MySQL does not support table partitioning.\n";
	syslog(LOG_CRIT, 'Your installation of MySQL does not support table partitioning.');
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
		syslog(LOG_ERR, 'Partitioning for "'.$key.'" is not found! The table might be not partitioned.');
		next;
	}

	create_next_partition($key, $part_tables->{$key}, $tables->{$key}->{'period'});
	remove_old_partitions($key, $part_tables->{$key}, $tables->{$key}->{'period'}, $tables->{$key}->{'keep_history'})
}

delete_old_data();

$dbh->disconnect();

sub check_have_partition {
# MySQL 5.5
#	#my $sth = $dbh->prepare(qq{SELECT variable_value FROM information_schema.global_variables WHERE variable_name = 'have_partitioning'});
#return 1 if $row eq 'YES';
#
# End of Mysql 5.5

# MySQL 5.6 + MariaDB
	my $sth = $dbh->prepare(qq{SELECT plugin_status FROM information_schema.plugins WHERE plugin_name = 'partition'});

	$sth->execute();

	my $row = $sth->fetchrow_array();

	$sth->finish();
        return 1 if $row eq 'ACTIVE';

# End of MySQL 5.6 + MariaDB

# MySQL 8.x (NOT MariaDB!)
#	my $sth = $dbh->prepare(qq{select version();});
#	$sth->execute();
#	my $row = $sth->fetchrow_array();
	
#	$sth->finish();
#       return 1 if $row >= 8;
#
# End of MySQL 8.x

# Do not uncomment last }	
}

sub create_next_partition {
	my $table_name = shift;
	my $table_part = shift;
	my $period = shift;

	for (my $curr_part = 0; $curr_part < $amount_partitions; $curr_part++) {
		my $next_name = name_next_part($period, $curr_part);

		if (grep { $_ eq $next_name } keys %{$table_part}) {
			syslog(LOG_INFO, "Next partition for $table_name table has already been created. It is $next_name");
		}
		else {
			syslog(LOG_INFO, "Creating a partition for $table_name table ($next_name)");
			my $query = 'ALTER TABLE '."$db_schema.$table_name".' ADD PARTITION (PARTITION '.$next_name.
						' VALUES less than (UNIX_TIMESTAMP("'.date_next_part($period, $curr_part).'") div 1))';
			syslog(LOG_DEBUG, $query);
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
			syslog(LOG_INFO, "Removing old $partition partition from $table_name table");

			my $query = "ALTER TABLE $db_schema.$table_name DROP PARTITION $partition";

			syslog(LOG_DEBUG, $query);
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
	$dbh->do("TRUNCATE housekeeper");
	$dbh->do("DELETE FROM auditlog_details WHERE NOT EXISTS (SELECT NULL FROM auditlog WHERE auditlog.auditid = auditlog_details.auditid)");
}
