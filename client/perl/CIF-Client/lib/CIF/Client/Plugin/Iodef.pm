package CIF::Client::Plugin::Iodef;
use base 'CIF::Client::Plugin::Parser';

use Module::Pluggable search_path => [__PACKAGE__], require => 1, except => qr/SUPER$/;

sub prepare {
    my $class = shift;
    my $hash = shift;
    return unless($hash->{'xsi:schemaLocation'});
    return unless($hash->{'xsi:schemaLocation'} eq 'urn:ietf:params:xmls:schema:iodef-1.0');
    return(1);
}

sub hash_simple {
    my $class = shift;
    my $data = shift;

    my @incidents;
    if(ref($data->{'Incident'}) eq 'ARRAY'){
        @incidents = @{$data->{'Incident'}};
    } else {
        push(@incidents,$data->{'Incident'});
    }

    my @return;
    foreach my $i (@incidents){
        my $impact = $i->{'Assessment'}->{'Impact'};
        $impact = $i->{'Assessment'}->{'Impact'}->{'content'} if(ref($impact) eq 'HASH');
        my $h = {
            uuid                        => $i->{'IncidentID'}->{'content'},
            relatedid                   => $i->{'RelatededActivity'}->{'IncidentID'}->{'content'},
            description                 => $i->{'Description'},
            impact                      => $impact,
            severity                    => $i->{'Assessment'}->{'Impact'}->{'severity'},
            confidence                  => $i->{'Assessment'}->{'Confidence'}->{'content'},
            source                      => $i->{'IncidentID'}->{'name'},
            restriction                 => $i->{'restriction'},
            alternativeid               => $i->{'AlternativeID'}->{'IncidentID'}->{'content'},
            alternativeid_restriction   => $i->{'AlternativeID'}->{'IncidentID'}->{'restriction'},
            detecttime                  => $i->{'DetectTime'},
            purpose                     => $i->{'purpose'},
        };

        foreach my $p ($class->plugins()){
            my $ret = eval { $p->hash_simple($i,$h) };
            warn $@ if($@);
            next unless($ret);
            map { $h->{$_} = $ret->{$_} } keys %$ret;
        }
        push(@return,$h);
    }
    return(\@return);
}

1;