#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http header validation with proxy module.

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

my $t = Test::Nginx->new();

plan (skip_all => 'not yet') unless $t->has_version('1.29.6');

$t->has(qw/http proxy/)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}

EOF

$t->write_file('index.html', '');

$t->run_daemon(\&http_daemon)->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start http daemon: $!\n";

$t->run()->plan(16);

###############################################################################

for my $c (split '', '"(),/;<=>?@[\]{}') {
	like(get('/', headers => {"X-Foo" => $c }), qr/ 502 Bad Gateway/,
		"'$c' not allowed");
}

###############################################################################

sub get {
	my ($uri, %extra) = @_;

	my $headers = '';
	for my $k (keys %{$extra{headers}}) {
		$headers .= "$k: $extra{headers}{$k}\r\n";
	}
	return http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
Connection: close
$headers
EOF
}

###############################################################################

sub http_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$headers =~ /^X-Foo: (\S+)/m;

		print $client <<EOF if $1;
HTTP/1.1 204 OK
Connection: close
X-Foo-$1: bar

EOF

	}
}

###############################################################################
