#!/usr/bin/perl
use strict 'vars';
use warnings;
use lib q/./;
#use AnyEvent::Loop;
use Coro;
use Socket;
use AnyEvent;
use AnyEvent::Handle::UDP;
use Coro::Twiggy;
use Data::Dumper::Perltidy;
use Prometheus::Tiny;
use experimental 'smartmatch';
use Time::Seconds;
# use utf8;
# binmode( STDOUT, 'utf8:' );

our $prom = Prometheus::Tiny->new;

my %servers = (
    'ANIME LUCHSHE'    => '46.174.52.164:27015',
    'ANIME LUCHSHE WL' => '46.174.50.224:27015',
    'Baguette'         => '148.251.11.171:27215',
    'BHOP.RIP'         => '144.48.37.114:27015',
    'CN BHOP'          => '183.131.85.109:27018',
    'BhopParadise'     => '198.50.245.166:27015',
    'Blank WL'         => '92.38.148.25:27016',
    'DHC BHOP'         => '193.192.58.145:27115',
    'Dystopia AU'      => '27.100.36.6:27015',
    'Dystopia NA'      => '74.91.126.160:27015',
    'EUFrag BHOP'      => '87.98.174.44:27017',
    'Exalted WL'       => '54.38.72.50:27015',
    'fluffytail'       => '74.91.119.40:27015',
    'FuckItHops'       => '95.217.200.57:27015',
    'FuckItHops WL'    => '95.217.200.57:27016',
    'FR ONLY BHOP'     => '92.222.116.243:27015',
    'GAME4X.RU'        => '46.174.51.172:27015',
    'GFLClan BHOP'     => '72.5.195.96:27015',
    'H.D.F. BHOP'      => '213.202.212.239:27015',
    'HyperHops'        => '177.54.144.126:27622',
    'Jiminy Jilikers'  => '118.210.183.239:27016',
    'JP Climb'         => '126.87.115.250:27015',
    'KR AKB BHOP'      => '125.186.11.253:27015',
    'KR AKB KZ'        => '125.186.11.253:27016',
    'Kana'             => '140.143.166.15:27018',
    'Kawaii BHOP'      => '74.201.72.19:27015',
    'Kawaii WL'        => '74.201.72.19:27016',
    'KwikHops NA'      => '74.91.124.75:27015',
    'LacunaHops'       => '104.153.108.15:27015',
    'Lets Bhop!'       => '193.192.58.156:27015',
    'Mac-Infectus'     => '45.235.99.134:27055',
    'mahtava'          => '95.217.39.250:27060',
    'MarcoPlay BHOP'   => '37.230.228.27:35000',
    'Omega-Portal'     => '46.174.53.79:27015',
    'TheSourceElite'   => '192.223.29.6:27015',
    'TrikzTime Cafe'   => '62.122.215.209:2020',
    'Ultima Auto'      => '148.251.11.171:1338',
    'Ultima Scroll'    => '148.251.11.171:1336',
    'Ultima WL'        => '148.251.11.171:27319',
    'XC makes me XD'   => '74.91.124.58:27015',
    ']HeLL[ BHOP'      => '178.32.58.203:27026',
    ']HeLL[ EZ BHOP'   => '178.32.58.203:27035',
    'bhop.pro'         => '148.251.234.158:27000',
    'freakhops wl'     => '47.102.45.144:27115',
    'freakhops'        => '47.102.45.144:27015',
    'gotta go faste'   => '74.91.113.110:27015',
    'slowhops'         => '162.248.88.24:27015',
    'strafersonly'     => '136.243.94.194:27015',
    'strafersonly wl'  => '136.243.94.194:27055',
    'STRAFE.EXPERT'    => '144.48.37.118:27015',
    'StrafesOnFleek'   => '192.223.27.114:27015',
    'Tarik Bhop'       => '178.233.163.31:27015',
    'TRUBHOPING AUTO'  => '176.212.185.161:27018',
    'UA-DV1ZH BHOP'    => '176.104.57.115:27120',
    'sqf wl'           => '60.111.209.149:27018',
    'Yandere BHOP'     => '121.146.157.174:27017',
    'zammyhop'         => '86.2.204.93:27015',
);

my %running;
my %cache;
# my %cache = (
#     'players' => {},
# );

for (keys %servers) {
    $cache{$_} = ();
}

sub parse_a2s_info {
    my( $buf ) = @_;
    # this can definitely be golfed but I don't want to bike-shed it
    my( $type, $version, $str ) = unpack 'x4aca*', $buf;
    my( $sname, $map, $dir, $desc, $remains ) = split /\0/, $str, 5;
    my(
        $app_id, $players, $max,    $bots, $dedicated,
        $os,     $pw,      $secure, $remains2
    ) = unpack 'vcccaacca*', $remains;
    my( $gversion, $remains3 ) = split /\0/, $remains2, 2;

    my $result = {
        type      => $type,
        version   => $version,
        sname     => $sname,
        map       => $map,
        dir       => $dir,
        desc      => $desc,
        app_id    => $app_id,
        players   => $players,
        max       => $max,
        bots      => $bots,
        dedicated => $dedicated,
        os        => $os,
        password  => $pw,
        secure    => $secure,
        gversion  => $gversion,
    };
    my( $edf, $opt ) = unpack 'ca*', $remains3;
    if ( $edf & 0x80 ) {
        my $port;
        ( $port, $opt ) = unpack 'va*', $opt;
        $result->{port} = $port;
    }
    if ( $edf & 0x40 ) {
        # print "opt is spectator port\n";
        $result->{spectator} = '';
    }
    if ( $edf & 0x20 ) {
        chop $opt;
        $result->{game_tag} = $opt;
    }
    return $result;
}

sub parse_a2s_player {
    my( $buf ) = @_;
    my( $type, $num_players, $followings ) = unpack 'x4aca*', $buf;
    my $player_info;
    while ($followings) {
        my( $index, $r1 ) = unpack 'ca*', $followings;
        my( $name, $r2 ) = ( split /\0/, $r1, 2 );
        my( $kills, $connected, $r3 ) = unpack 'lfa*', $r2;
        push @{$player_info},
            {
            name      => $name,
            kills     => $kills,
            connected => $connected,
            };
        $followings = $r3;
    }

    my $result = {
        type        => $type,
        num_players => $num_players,
        player_info => $player_info,
    };
    return $result;
}

warn sprintf "initialising %d servers", scalar keys %servers;
for my $server (keys %servers) {
    $running{$server} = AnyEvent::Handle::UDP->new(
        #connect => [split ':', $servers{$server}],
        on_recv => unblock_sub {
            my ($data, $ae_handle, $client_addr) = @_;
            # get whether multipart or not
            my $multipack = unpack 'i', $data;
            # get type of response
            my $t = unpack 'x4a', $data;

            my ($port, $addr) = unpack_sockaddr_in($client_addr);
            my $host = inet_ntoa($addr);

            # warn $host, $port;

            # could use a translation table or some shit
            my $key = (grep { $servers{$_} eq "$host:$port" } keys %servers)[0];

            # warn $key;

            if ($t eq 'A') {
                my( $type, $cnum ) = unpack 'x4aa4', $data;
                $ae_handle->push_send("\xFF\xFF\xFF\xFF\x55".$cnum);
            }
            elsif ($t eq 'I') {
                # server info
                # warn Dumper \parse_a2s_info($data);
            }
            elsif ($t eq 'D') {
                # player info
                my $players = parse_a2s_player($data);
                # print Dumper \$players;
                my @real = grep { $_->{'name'} !~ /(^Main|^Bonus|BOT|No Record|Will|Jason|Glenn|Perry|Gary|Wyatt|Yahn|Nate|Xavier|Colin|Bill|Derek|replay|\d\d?(\:|\.)\d|bhopmania)/i and $_->{name} ne '' } @{$players->{'player_info'}};
                map { printf '% 16s %32s (%s)%s', $key, $_->{name}, Time::Seconds->new($_->{connected})->pretty, "\n" } @real if @real;
				#warn 'setting for '.$key;
                $cache{$key} = [time, scalar @real];
                $prom->set('players_online', scalar @real, { server => $key, address => $servers{$key} });
            }
            elsif ($t eq 'E') {
                # rules
            }
            else {
                warn "got: $data";
            }
        },
        on_connect => unblock_sub {
            my ($ae_handle, $server_addr) = @_;
            # $ae_handle->push_send("\xFF\xFF\xFF\xFFTSource Engine Query\0");
            # $ae_handle->push_send("\xFF\xFF\xFF\xFF\x57");
        },
        on_error => sub {
            my ($self, $fatal, $message) = @_;
             #warn Dumper \@_;
             warn "destroying";
             $self->destroy;
        },
        on_timeout => sub { warn Dumper \@_ },
    );
}
warn "players online:";

my $loop = AnyEvent->timer(
    after    =>   0,
    interval =>   10,
    cb       =>   sub {
        for my $server (keys %servers) {
				#warn ref $running{$server};
                if (ref $running{$server} eq 'AnyEvent::Handle::UDP') {
				$running{$server}->connect_to([split ':', $servers{$server}]);
                $running{$server}->push_send("\xFF\xFF\xFF\xFFTSource Engine Query\0");
                $running{$server}->push_send("\xFF\xFF\xFF\xFF\x57");
            }
        }
    }
);

my $setter = AnyEvent->timer(
    after => 10,
    interval => 10,
    cb => sub {
        for my $key (keys %servers) {
            if ($cache{$key} && time() - $cache{$key}->[0] > 30) {
                $prom->set('players_online', 0, { server => $key, address => $servers{$key} });
            }
        }
    }
);

my $exporter = sub {
  my $env = shift;
  return [ 200, [ 'Content-Type' => 'text/plain' ], [ $prom->format ] ];
};

my $promserv = Coro::Twiggy->new(host => '0.0.0.0', port => 9110);
$promserv->register_service( $exporter );

AE::cv->recv;
