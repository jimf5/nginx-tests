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

    limit_req_zone  $remote_port  zone=zone:1m   rate=1r/s;

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

$t->run()->plan(8);

###############################################################################

like(http11_get('/', socket => my $s = http('', start => 1)),
	qr/^HTTP\/1.. 200 /m, 'conn 1, req 1/1 - ok');

$t->write_file('nginx.conf', $t->read_file('nginx.conf') =~ s/1r/2r/gr);
is(update($t), 1, 'config reloaded');

like(http11_get('/', socket => my $s2 = http('', start => 1)),
	qr/^HTTP\/1.. 200 /m, 'conn 2, req 1/2 - ok');
select undef, undef, undef, 0.3; # wait to smooth burst
like(http11_get('/', socket => $s2), qr/^HTTP\/1.. 200 /m,
	'conn 2, req 2/2 - ok');
select undef, undef, undef, 0.3; # wait to smooth burst
like(http11_get('/', socket => $s2), qr/^HTTP\/1.. 200 /m,
	'conn 2, req 3/2 - ok(burst)');
like(http11_get('/', socket => $s2), qr/^HTTP\/1.. 503 /m,
	'conn 2, req 4/2 - rejected');

like(http11_get('/', socket => $s), qr/^HTTP\/1.. 200 /m,
	'conn 1, req 2/1 - ok (burst)');
like(http11_get('/', socket => $s), qr/^HTTP\/1.. 503 /m,
	'conn 1, req 3/1 - rejected');

###############################################################################

sub http11_get {
	my ($url, %extra) = @_;

	my $s = http(<<EOF, start => 1, %extra);
GET $url HTTP/1.1
Host: localhost
Connection: keep-alive

EOF

	my $response = '';
	while (my $line = <$s>) {
		$response .= $line;
		last if $line =~ /^\r?\n$/;
	}
	if ($response =~ /Content-Length:\s*(\d+)/i) {
		read($s, $_, $1);
		$response .= $_;
	}
	close $s unless $extra{socket};
	log_in($response);
	return $response;
}

sub update {
	my ($t) = @_;

	$t->update();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log') =~ /(dynamic conf load)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
