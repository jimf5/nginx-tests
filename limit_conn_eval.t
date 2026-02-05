#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for http eval module with limit conn module.

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

my $t = Test::Nginx->new();

# plan(skip_all => 'no eval support yet') unless $t->has_version('1.29.6');

$t->has(qw/http limit_conn eval/)->write_file_expand('nginx.conf', << 'EOF');

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

        eval dynamic.conf;
    }
}

EOF

$t->write_file_expand('dynamic.conf', <<EOF);
proxy_pass http://127.0.0.1:8081;
limit_conn  zone 1;
EOF

$t->run_daemon(\&http_daemon, port(8081))
	->waitforsocket('127.0.0.1:' . port(8081))
	or die 'http daemon failed to start at 127.0.0.1:' . port(8081). "\n";

$t->run()->plan(4);

###############################################################################

like(http_get('/'), qr/^HTTP\/1.. 200 /m, '1/1 conn - allowed');

push my @hold, http_get('/hold', start => 1);

like(http_get('/'), qr/^HTTP\/1.. 503 /m, '2/1 conn - rejected');

$t->write_file('tmp.conf', $t->read_file('dynamic.conf') =~ s/ 1;/ 2;/gr);
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/dynamic.conf';
select undef, undef, undef, 0.1; # wait for file change to be noticed

like(http_get('/'), qr/^HTTP\/1.. 200 /m, '2/2 conn (updated) - allowed');

push @hold, http_get('/hold', start => 1);

like(http_get('/'), qr/^HTTP\/1.. 503 /m, '3/2 conn (updated) - rejected');

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

EOF

	}

	return 0 if $uri =~ /^\/hold/;
	return 1;
}

###############################################################################
