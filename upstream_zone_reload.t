#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for upstream zone module with configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(4);
my $conf = << 'EOF';

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        zone u 1m;
        %%SERV%%
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

###############################################################################

my $p = port(8081);

my $serv = 'server 127.0.0.1:8081;';
$t->write_file_expand('nginx.conf', $conf =~ s/%%SERV%%/$serv/gr)->run();
like(http11_get('/', socket => my $s = http('', start => 1)),
	qr/X-Name: 127.0.0.1:$p/, 'conn 1 - upstream name');

$serv = 'server 127.0.0.1:8081 down;server 127.0.0.1:8081 backup down;';
$t->write_file_expand('nginx.conf', $conf =~ s/%%SERV%%/$serv/gr);
is(reload($t), 1, 'reload config - servers down');

like(http_get('/'), qr/X-Name: u/, 'conn 2 - no live upstreams');

is(http11_get('/', socket => $s) || $s->connected(), undef, 'conn 1 - closed');

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

sub reload {
	my ($t) = @_;

	$t->reload();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log')
			=~ /(cycle exit)|(exited with code)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
