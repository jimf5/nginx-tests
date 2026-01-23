#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Test for nginx limit_conn module with configuration reload.

###############################################################################

use warnings;
use strict;

use Test::More;
use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy limit_conn/)->plan(9)
	->write_file_expand('nginx.conf', << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_conn_zone  $binary_remote_addr  zone=zone:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081;
            limit_conn zone 1;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081))
	->waitforsocket('127.0.0.1:' . port(8081))
	or die 'http daemon failed to start at 127.0.0.1:' . port(8081). "\n";

$t->run();

###############################################################################

like(http_get('/'), qr/^HTTP\/1.. 200 /m, '1/1 conn - allowed');
push my @__, http_get('/hold', start => 1);
like(http_get('/'), qr/^HTTP\/1.. 503 /m, '2/1 conn - rejected');

is(reload($t), 1, 'reload config - same zone size, same limit');

like(http_get('/'), qr/^HTTP\/1.. 503 /m, '2/1 conn (reuse data) - rejected');

$t->write_file('nginx.conf',
	$t->read_file('nginx.conf') =~ s/zone 1;/zone 2;/gr);
is(reload($t), 1, 'reload config - same zone size, new limit');

like(http_get('/'), qr/^HTTP\/1.. 200 /m, '2/2 conn (reuse data) - allowed');
push @__, http_get('/hold', start => 1);
like(http_get('/'), qr/^HTTP\/1.. 503 /m, '3/2 conn (reuse data) - rejected');

$t->write_file('nginx.conf',
	$t->read_file('nginx.conf') =~ s/zone:1m;/zone:2m;/gr);
is(reload($t), 1, 'reload config - new zone size, same limit');

like(http_get('/'), qr/^HTTP\/1.. 200 /m, '3/2 conn - allowed');

###############################################################################

sub reload {
	my ($t) = @_;
	my $offset = -s $t->testdir() . '/error.log' || 0;

	$t->reload();

	for (1 .. 30) {
		return 1
			if substr($t->read_file('error.log'), $offset)
				=~ /(cycle p:.* exiting:1)|(worker process is shutting down)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################

sub http_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'tcp',
		Listen => 5,
		Reuse => 1,
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read()) {
		foreach my $s (@ready) {
			next if ref $s ne 'IO::Socket::INET';
			if ($s == $server) {
				$sel->add($s->accept());
			} else {
				if (http_handler($s)) {
					$sel->remove($s);
					$s->close();
				}
			}
		}
	}
}

sub http_handler {
	my ($client) = @_;

	my $headers = '';

	while (<$client>) {
		$headers .= $_;
		last if (/^\x0d?\x0a?$/);
	}

	my $uri = $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i ? $1 : '';

	if ($uri eq '/') {
		print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

SEE-THIS
EOF

	}

	return 0 if $uri =~ /^\/hold/;
	return 1;
}

###############################################################################
