#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for ssl module with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl socket_ssl dynamic_conf/)
	->has_daemon('openssl')
	->write_file_expand('nginx.conf', << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate 1.example.com.crt;
        ssl_certificate_key 1.example.com.key;
    }
}

EOF

my $d = $t->testdir();

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run()->plan(3);

###############################################################################

like(get_cert_cn(8443), qr!/CN=1.example.com!, 'certificate 1');

$t->write_file('nginx.conf', $t->read_file('nginx.conf') =~ s/ 1\./ 2./gr);
is(update($t), 1, 'config reloaded');

like(get_cert_cn(8443), qr!/CN=2.example.com!, 'certificate 2');

###############################################################################

sub get_cert_cn {
	my ($port) = @_;
	my $s = http('',
		start => 1,
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1);
	return $s->dump_peer_certificate();
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
