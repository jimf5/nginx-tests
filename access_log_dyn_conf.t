#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for access_log with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http dynamic_conf/)
	->write_file_expand('nginx.conf', my $conf = << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format addr "$remote_addr:$remote_port:$server_addr:$server_port";

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
           access_log off;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');

$t->run()->plan(5);

###############################################################################

like(http11_get('/', socket => my $s = http('', start => 1)),
	qr/^HTTP\/1.. 200 /m, 'conn 1 - no logging');

$t->write_file_expand('nginx.conf',
	$conf =~ s/access_log off/access_log %%TESTDIR%%\/access.log addr/gr);
is(update($t), 1, 'config reloaded');

like(http11_get('/', socket => my $s2 = http('', start => 1)),
	qr/^HTTP\/1.. 200 /m, 'conn 2 - logging enabled');
my $addr = $s2->sockhost();
my $port = $s2->sockport();
my $remote_addr = $s2->peerhost();
my $remote_port = $s2->peerport();

like(http11_get('/', socket => $s), qr/^HTTP\/1.. 200 /m,
	'conn 1 - no logging still');

close $s2;
close $s;
$t->stop();

is($t->read_file('access.log'), "$addr:$port:$remote_addr:$remote_port\n",
	'conn 2 in access.log only');

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
