#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol with dynamic configuration reload.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_ssl http_v2 http_v3 socket_ssl_alpn rewrite cryptx/)
	->has(qw/dynamic_conf/)->has_daemon('openssl')
	->write_file_expand('nginx.conf', << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        http2 on;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        location / {
            return 200 before;
        }
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

$t->run()->plan(10);

###############################################################################

my $h1s = http('', start => 1,
	SSL => 1,
	SSL_alpn_protocols => ['http/1.1']);
my $h2s = Test::Nginx::HTTP2->new(undef,
	socket => http('', start => 1,
		SSL => 1,
		SSL_alpn_protocols => ['h2']));
my $h3s = Test::Nginx::HTTP3->new(8980);
is(get11($h1s), 'before', 'h1 conn1 - before');
is(get23($h2s), 'before', 'h2 conn1 - before');
is(get23($h3s), 'before', 'h3 conn1 - before');

$t->write_file('nginx.conf', $t->read_file('nginx.conf') =~ s/before/after/gr);
is(update($t), 1, 'config reloaded');

my $h1s2 = http('', start => 1,
	SSL => 1,
	SSL_alpn_protocols => ['http/1.1']);
my $h2s2 = Test::Nginx::HTTP2->new(undef,
	socket => http('', start => 1,
		SSL => 1,
		SSL_alpn_protocols => ['h2']));
my $h3s2 = Test::Nginx::HTTP3->new(8980);
is(get11($h1s2), 'after', 'h1 conn2 - after');
is(get23($h2s2), 'after', 'h2 conn2 - after');
is(get23($h3s2), 'after', 'h3 conn2 - after');

is(get11($h1s), 'before', 'h1 conn1 - before still');
is(get23($h2s), 'before', 'h2 conn1 - before still');
is(get23($h3s), 'before', 'h3 conn1 - before still');

###############################################################################

sub get11 {
	my ($s) = @_;

	http(<<EOF, start => 1, socket => $s);
GET / HTTP/1.1
Host: localhost
Connection: keep-alive

EOF

	my $response = '';
	while (my $line = <$s>) {
		$response .= $line;
		last if $line =~ /^\r?\n$/;
	}
	my $body = '';
	if ($response =~ /Content-Length:\s*(\d+)/i) {
		read($s, $body, $1);
		$response .= $body;
	}
	log_in($response);
	return $body;
}

sub get23 {
	my ($s) = @_;
	my $sid = $s->new_stream();
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
	return $frame->{data};
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
