#!/usr/bin/perl
use strict 'vars';
use warnings;
use English qw(-no_match_vars);

use Coro;
use AnyEvent;
use AnyEvent::Util;
use IO::Socket::INET;
use Coro::AnyEvent;
use Coro::Twiggy;
use Plack::Request;

#use Data::Dumper::Perltidy;
use Net::SRCDS::Queries;
use IO::Interface::Simple;
use Term::Encoding qw(term_encoding);
#use YAML;
 
our %stack;
our %procs;
our %inner;
our $virtual;

sub dlog { warn "@_" }

sub random_map {
#	my @files = (</home/steam/css/cstrike/maps/*.bsp>);
#	return (split '.bsp' => (split '/' => $files[rand @files])[-1])[0];
	my @maps = `cat /home/steam/css/cstrike/maps/mapcycle.txt`;
	return $maps[rand @maps];
}

my %daemons = (
    'css',
    {
#        prog => 'taskset -c 3 /home/steam/css/srcds_linux',
        prog => '/home/steam/css/srcds_linux',
        args => ' -secure -tickrate 100 -console -game cstrike -maxplayers 24 -ip 144.48.37.114 -port 27015 +fps_max 1000 +exec server.cfg',
        halt => '/usr/bin/pkill -9 -f 27015', # i sure fucking hope this works
        proc => '27015',
    },
);

my %CONST = (
    'WD_POLL_IV' => 40,
    'WD_CSS_IV'  => 1,
);

my %watchdogs = (
    'WD_POLL_IV'  =>  unblock_sub
    {
#            warn 'detected hang, restarting..';
#            defer_exec($daemons{css}->{halt});

	    my $if       = IO::Interface::Simple->new('enp2s0f0');
            my $addr     = $if->address;
            my $port     = 27015;
            my $encoding = term_encoding;

            my $q = Net::SRCDS::Queries->new(
                        encoding => $encoding,  # set encoding to convert from utf8
                        timeout  => 5,
            );
	    $q->add_server( $addr, $port );
	    my $status = $q->get_all;
#  	    warn Dumper \$status;
		unless ($status) {
	            warn 'detected hang, restarting..';
		    `lsof +D /home/steam/css/cstrike/maps/ >> crashing_maps.txt`;
        	    defer_exec($daemons{css}->{halt});
#			warn "nope";
		}

    },

    'WD_CSS_IV'  =>  unblock_sub
    {
        unless (pidof($daemons{css}->{proc}))
        {
            warn 'spawning server';
            my $exec = $daemons{css}->{prog} . $daemons{css}->{args} . ' +map ' . quotemeta(random_map());
            $procs{$daemons{css}->{proc}} = defer_exec($exec);
        }
        return
    },
);

# will not switch to using h::pid:: memcached b/c checking a hash is faster
sub pidof {
    my $ident = $_[0];
    if (defined $procs{$ident})
    {
        if (kill 0 => $procs{$ident})
        {
            return 1
        }
        else
        {
            $procs{$ident} = undef;
            return undef
        }
    }
    else
    {
        return undef
    }
}

sub get_watchdogs {
    return keys %watchdogs
}

sub defer_exec {
    my $call = "@_";
    $SIG{CHLD} = 'IGNORE';
    my $pid = fork();
    die "unable to fork: $!" unless defined($pid);
    if (!$pid) {
        # exec "$call >/dev/null 2>&1";
	local $ENV{LD_LIBRARY_PATH} .= ':/home/steam/css/bin';
        exec "$call | logger";
        exit;
    }
    return $pid
}

sub stop_watchdogs {
    for my $dog (get_watchdogs())
    {
        dlog("W: $dog stopping");
        $stack{$dog} = undef;
    }
}

sub start_watchdogs {
    for my $dog (get_watchdogs())
    {
        if (defined $stack{$dog})
        {
            dlog('W: skipping initialisation of $dog');
        }
        else
        {
            dlog("W: $dog initialising");
            $stack{$dog} = AnyEvent->timer(
                after     => $CONST{$dog},
                interval  => $CONST{$dog},
                cb        => $watchdogs{$dog});
        }
    }
}

start_watchdogs();

my $app = sub
{
	my ($env) = @_;
	my $req = Plack::Request->new($env);
	my $path = unpack "xA*" => $env->{'PATH_INFO'};
	my $ip = $env->{'HTTP_X_REAL_IP'};
	if ($path eq 'oof')
	{
		warn $ip;
		my @whitelist = split "\n" => `cat /home/steam/whitelist.txt`;
		if ($ip ~~ @whitelist) {
			warn "granted $ip at ".time;
            		defer_exec($daemons{css}->{halt});			
       		        return [
                 	       200 => ['Content-Type' => 'text/html']
				   => ['<meta http-equiv="refresh" content="0; url=http://bhop.rip/done" />']
                	]
		}
		else {
			warn "failed login from $ip at ".time;
        		return [
                		200 => ['Content-Type' => 'text/plain']
                	    	=> ['nah']
       			]
		}
	}
	elsif ($path eq 'done')
	{
		return [
                        200 => ['Content-Type' => 'text/plain']
                        => ['done']
                ]
	}
	else
	{
		return [
			200 => ['Content-Type' => 'text/html']
			    => ['<form action="/oof" method="post"><input type="submit" value="u sure nibba" /></form>']
		]
	}
};

my $http = Coro::Twiggy->new(
	host => '127.0.0.1',
	port => 9999
);

$http->register_service($app);

#$SIG{INT} = sub
#{
#    warn 'interrupt received..';
#};


AE::cv->recv;
