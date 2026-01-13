#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for stream access module with dynamic configuration reload.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_access dynamic_conf/)
	->write_file_expand('nginx.conf',  <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen       127.0.0.1:8081;
        proxy_pass   127.0.0.1:8080;
        allow all;
    }
}

EOF

$t->run_daemon(\&stream_daemon, port(8080));
$t->waitforsocket('127.0.0.1:' . port(8080))
	or die "Can't run daemon at 127.0.0.1:" . port(8080). "\n";

$t->run()->plan(4);

###############################################################################

my $str = 'SEE-THIS';

my $s = stream('127.0.0.1:' . port(8081));
is($s->io($str, read_timeout => 0.5), $str, 'conn1 - allow all');

$t->write_file('nginx.conf',
	$t->read_file('nginx.conf') =~ s/allow all/deny all/gr);
is(update($t), 1, 'nginx reload');

is(stream('127.0.0.1:' . port(8081))->io($str, read_timeout => 0.5), '',
	'conn 2 - deny all');

is($s->io($str, read_timeout => 0.5), $str, 'conn1 - allow all still');

###############################################################################

sub stream_daemon {
	my ($p) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . $p,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read()) {
		foreach my $s (@ready) {
			next if (ref $s ne 'IO::Socket::INET');
			if ($s == $server) {
				$sel->add($server->accept());
			} else {
				my $rv = $s->sysread(my $buffer, 65536);
				if ($rv) {
					$rv = $s->syswrite($buffer);
				}
				if (!$rv) {
					$sel->remove($s);
					$s->close();
				}
			}
		}
	}
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
