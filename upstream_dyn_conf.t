#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for upstream moudule with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http proxy dynamic_conf/)
	->write_file_expand('nginx.conf', my $conf = << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {}
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Name $upstream_addr always;

        location / {
            proxy_pass http://u/;
        }
    }
}

EOF

$t->write_file('index.html', '');

$t->run()->plan(10);

###############################################################################

my $p = port(8081);

like(http11_get('/', socket => my $s = http('', start => 1)),
	qr/X-Name: 127.0.0.1:$p/, 'conn1 - upstream name');

$t->write_file_expand('nginx.conf',
	$conf =~ s/server 127\.0\.0\.1:8081/server 127.0.0.1:8081 down/gr);
is(update($t), 1, 'reload config(update) - marked upstream down');

like(http_get('/'), qr/X-Name: u/, 'conn2 - no live upstreams');

like(http11_get('/', socket => $s), qr/X-Name: 127.0.0.1:$p/,
	'conn1 - upstream name still');

$t->write_file_expand('nginx.conf',
	$conf =~ s/server 127\.0\.0\.1:8081/zone u 1m;server 127.0.0.1:8081/gr);
is(reload($t), 1, 'config reloaded - added zone');

is(http11_get('/', socket => $s) || $s->connected(), undef, 'conn1 - closed');

like(http11_get('/', socket => my $s3 = http('', start => 1)),
	qr/X-Name: 127.0.0.1:$p/, 'conn3 - upstream name');
is(update($t), 1, 'reload config(update) - zone reused');

like(http_get('/'), qr/X-Name: 127.0.0.1:$p/, 'conn4 - upstream name');
like(http11_get('/', socket => $s3), qr/X-Name: 127.0.0.1:$p/,
	'conn3 - upstream name still');

###############################################################################

sub http11_get {
	my ($url, %extra) = @_;

	my $s = http(<<EOF, start => 1, %extra);
GET $url HTTP/1.1
Host: localhost
Connection: keep-alive

EOF

	return undef unless $s;

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

	my $offset = -s $t->testdir() . '/error.log' || 0;

	$t->update();

	for (1 .. 30) {
		return 1 if
			substr($t->read_file('error.log'), $offset)
			=~ /(dynamic conf load)/;
		select undef, undef, undef, 0.2;
	}
}

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
