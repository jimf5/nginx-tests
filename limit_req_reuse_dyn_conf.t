#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for nginx limit_req module with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http limit_req dynamic_conf/)
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

$t->run()->plan(6);

###############################################################################

like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 1/1 - ok');
like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 2/1 - ok(burst)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 3/1 - rejected');

$t->write_file('nginx.conf', $t->read_file('nginx.conf') =~ s/1r/2r/gr);
is(update($t), 1, 'config reloaded');
select undef, undef, undef, 0.3; # wait to smooth burst
like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 3/2 (reuse data) - ok(burst)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 4/2 (reuse data) - rejected');

###############################################################################

sub update {
	my ($t) = @_;

	$t->update();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log') =~ /(dynamic conf load)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
