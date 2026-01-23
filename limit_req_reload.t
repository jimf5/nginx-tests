#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for nginx limit_req module with configuration reload.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(12)
	->write_file_expand('nginx.conf', << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=zone:1m   rate=1r/s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            limit_req  zone=zone  burst=1  nodelay;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->run();


###############################################################################

like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 1/1 - ok');
like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 2/1 - ok(burst)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 3/1 - rejected');

is(reload($t), 1, 'reload config - same zone size, same rate');

like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 3/1 (reuse data) - rejected');

$t->write_file('nginx.conf',
	$t->read_file('nginx.conf') =~ s/zone:1m/zone:2m/gr);
is(reload($t), 1, 'reload config - new zone size, same rate');

like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 1/1 - ok');
like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 2/1 - ok(burst)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 3/2 - rejected');

$t->write_file('nginx.conf',
	$t->read_file('nginx.conf') =~ s/rate=1r\/s/rate=2r\/s/gr);
is(reload($t), 1, 'reload config - same zone size, new rate');

select undef, undef, undef, 0.3; # wait to smooth burst
like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 3/2 (reuse data) - ok(burst)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 4/2 (reuse data) - rejected');

###############################################################################

sub reload {
	my ($t) = @_;
	my $offset = -s $t->testdir() . '/error.log' || 0;

	$t->reload();

	for (1 .. 30) {
		return 1 if
			substr($t->read_file('error.log'), $offset)
			=~ /(cycle exit)|(exited with code)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
