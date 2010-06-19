#!/usr/bin/perl -w

use strict;
use XML::RSS;
use LWP::Simple;
use Data::Dumper;
use Net::Abuse::Utils qw(:all);
use Regexp::Common qw/net/;
use DateTime::Format::DateParse;
use DateTime;
use Net::DNS;

use CIF::Message::Infrastructure;
use CIF::Message::Domain;

my $timeout = 5;
my $res = Net::DNS::Resolver->new(
    nameservers => ['8.8.8.8'],
);

my $partner = 'zeustracker.abuse.ch';
my $url = 'https://zeustracker.abuse.ch/rss.php';
my $content;
my $rss = XML::RSS->new();

$content = get($url);
$rss->parse($content);

foreach my $item (@{$rss->{items}}){
    my ($host,$addr,$sbl,$status,$level,$a,$country) = split(/,/,$item->{description});
    $host =~ s/Host: //;
    $addr =~ s/ IP address: //;
    $status =~ s/ status: //;
    $level =~ s/ level: //;

    for($level){
        $level = 'bulletproof hosted' if(/^1$/);
        $level = 'hacked webserver' if(/^2$/);
        $level = 'free hosting service' if(/^3$/);
        $level = 'unknown' if(/^4$/);
        $level = 'hosted on a fastflux botnet' if(/^5$/);
    }

    my $reporttime;
    if($item->{title} =~ /\((\d{4}\-\d{2}\-\d{2} \d{2}:\d{2}:\d{2})\)/){
        $reporttime = DateTime::Format::DateParse->parse_datetime($1);
    }
    $reporttime .= 'Z';

    my $uuid;
    if($host =~ /^$RE{net}{IPv4}$/){
        my ($as,$network,$ccode,$rir,$date,$as_desc) = asninfo($host); 
        $uuid = CIF::Message::Infrastructure->insert({
                source      => $partner,
                address     => $addr,
                impact      => 'botnet infrastructure zeus',
                description => 'botnet infrastructure zeus level:'.$level.' - '.$addr,
                confidence  => 5,
                severity    => 'medium',
                reporrtime  => $reporttime,
                asn         => $as,
                asn_desc    => $as_desc,
                cidr        => $network,
                cc          => $ccode,
                rir         => $rir,
                restriction => 'need-to-know',
                externalid => 'https://zeustracker.abuse.ch/monitor.php?ipaddress='.$addr,
                externalid_restriction => 'public',
        });
        warn $uuid;
    } else {  
        my $bgsock = $res->bgsend($host);
        my $sel = IO::Select->new($bgsock);

        my @rdata;
        my @ready = $sel->can_read($timeout);
        if(@ready){
            foreach my $sock (@ready){
                if($sock == $bgsock){
                    my $packet = $res->bgread($bgsock);
                    foreach my $rr ($packet->answer()){
                        my $x = (uc($rr->{'type'}) eq 'A') ? $rr->address() : $rr->cname();
                        push(@rdata,{ address => $x, type => $rr->type(), class => $rr->class(), ttl => $rr->ttl() });
                    }
                    $bgsock = undef;
                }
                $sel->remove($sock);
                $sock = undef;
            }
        } else {
            warn "timed out after $timeout seconds\n";
        }
        
        if($#rdata < 0){
            push(@rdata,{ address => undef, type => 'A', class => 'IN', ttl => undef });
        }

        foreach my $r (@rdata){
            my ($as,$network,$ccode,$rir,$date,$as_desc) = asninfo($r->{'address'});
            my $impact = 'malicious domain zeus';
            $uuid = CIF::Message::Domain->insert({
                address     => $host,
                source      => $partner,
                confidence  => 5,
                severity    => 'medium',
                impact      => $impact,
                description => $impact.' level:'.$level.' - '.$host,
                reporttime  => $reporttime,
                class       => $r->{'class'},
                rrtype      => $r->{'type'},
                rdata       => $r->{'address'},
                ttl         => $r->{'ttl'},
                asn         => $as,
                asn_desc    => $as_desc,
                cidr        => $network,
                cc          => $ccode,
                rir         => $rir,
                externalid => 'https://zeustracker.abuse.ch/monitor.php?host='.$host,
                externalid_restriction => 'public',
                restriction => 'need-to-know',
            });
            $uuid = $uuid->uuid();
           
            next unless($r->{'address'} && $r->{'address'} =~ /^$RE{net}{IPv4}$/);
            CIF::Message::Infrastructure->insert({
                relatedid   => $uuid,
                source      => $partner,
                address     => $r->{'address'},
                impact      => 'botnet infrastructure zeus',
                description => 'botnet infrastructure zeus level:'.$level.' - '.$r->{'address'},
                confidence  => 5,
                severity    => 'medium',
                reporttime  => $reporttime,
                asn         => $as,
                asn_desc    => $as_desc,
                cidr        => $network,
                cc          => $ccode,
                rir         => $rir,
                restriction => 'need-to-know',
                externalid => 'https://zeustracker.abuse.ch/monitor.php?ipaddress='.$addr,
                externalid_restriction => 'public',
            });
            warn $uuid;
        }
    }
}

sub asninfo {
    my $a = shift;
    return undef unless($a);
    my ($as,$network,$ccode,$rir,$date) = get_asn_info($a);
    my $as_desc;
    $as_desc = get_as_description($as) if($as);

    $as         = undef if($as && $as eq 'NA');
    $network    = undef if($network && $network eq 'NA');
    $ccode      = undef if($ccode && $ccode eq 'NA');
    $rir        = undef if($rir && $rir eq 'NA');
    $date       = undef if($date && $date eq 'NA');
    $as_desc    = undef if($as_desc && $as_desc eq 'NA');
    $a          = undef if($a eq '');
    return ($as,$network,$ccode,$rir,$date,$as_desc);
}