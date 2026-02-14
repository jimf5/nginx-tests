#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http header validation.

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

$t->has(qw/http/)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080;
        server_name localhost;

     }
}

EOF

$t->write_file('index.html', '');

$t->run()->plan(16);

###############################################################################

for my $c (split '', '"(),/;<=>?@[\]{}') {
	like(get('/', headers => {"X-Foo$c" => 'Bar'}), qr/ 400 Bad Request/,
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
