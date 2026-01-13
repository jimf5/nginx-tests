#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for UDP stream with dynamic configuration reload.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ dgram /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return udp dynamic_conf/)
	->plan(4);

my $conf = <<'EOF';

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_timeout   1s;

    server {
        listen      127.0.0.1:%%PORT_8980_UDP%% udp;
        proxy_pass  127.0.0.1:%%PORT_%%NUM%%_UDP%%;
    }

    server {
        listen      127.0.0.1:%%PORT_8981_UDP%% udp;
        return      1;
    }

    server {
        listen      127.0.0.1:%%PORT_8982_UDP%% udp;
        return      2;
    }
}

EOF

###############################################################################

$t->write_file_expand('nginx.conf', $conf =~ s/%%NUM%%/8981/gr)->run();
my $s = dgram('127.0.0.1:' . port(8980));
is($s->io('1', read_timeout => 0.5), '1', 'udp_stream 1');

$t->write_file_expand('nginx.conf', $conf =~ s/%%NUM%%/8982/gr);
is(update($t), 1, 'nginx reload');

is(dgram('127.0.0.1:' . port(8980))->io('1', read_timeout => 0.5), '2',
	'udp_stream 2');

is($s->io('1', read_timeout => 0.5), '1', 'udp_stream 1 still');

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
