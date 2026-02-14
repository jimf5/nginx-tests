#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http header validation with http_v3 module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new();

plan (skip_all => 'not yet') unless $t->has_version('1.29.6');

$t->has(qw/http http_v3/)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen 127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name localhost;
     }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}
$t->write_file('index.html', '');

$t->run()->plan(19);

###############################################################################

for my $c (split '', '"(),/:;<=>?@[\]{}AZ') {
	is(get3("x-foo$c")->{':status'}, 400, "'$c' not allowed");
}

###############################################################################

sub get3 {
	my ($h) = @_;
	my $s = Test::Nginx::HTTP3->new();
	$s->insert_literal($h, 'bar');
	my $sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 },
	{ name => $h, value => 'bar', mode => 2, dyn => 1 }]});
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers};
}

###############################################################################
