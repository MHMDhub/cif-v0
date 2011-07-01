package CIF::Archive::DataType;
use base 'CIF::DBI';

__PACKAGE__->columns(All => qw/id uuid/);
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->has_a(uuid => 'CIF::Archive');

use Module::Pluggable require => 1, except => qr/::Plugin::\S+::/;

__PACKAGE__->set_sql('feed' => qq{
    SELECT __ESSENTIAL__
    FROM __TABLE__
    WHERE detecttime >= ?
    AND confidence >= ?
    AND severity >= ?
    AND restriction <= ?
    ORDER BY confidence ASC, detecttime DESC, created DESC, id DESC
    LIMIT ?
});

# TODO -- re-eval
# this is a work-around for has_a wanting to map
# uuid => id
 __PACKAGE__->add_trigger(select  => \&remap_id);
sub remap_id {
    my $class = shift;
    $class->{'uuid'} = CIF::Archive->retrieve(uuid => $class->uuid->id());
}

sub prepare {
    my $class = shift;
    my $info = shift;

    my @bits = split(/::/,lc($class));
    my $t = $bits[$#bits];
    return(1) if($info->{'impact'} =~ /$t$/);
    return(0);
}

sub set_table {
    my $class = shift;

    my @bits = split(/::/,lc($class));
    my $t = $bits[$#bits];
    if($bits[$#bits-1] ne 'plugin'){
        $t = $bits[$#bits-1].'_'.$bits[$#bits];
    }
    return $class->table($t);
}

sub feed {
    my $class = shift;
    my $info = shift;

    my $key = $info->{'key'};
    my $max = $info->{'maxrecords'} || 10000;
    my $restriction = $info->{'restriction'} || 'need-to-know';
    my $severity = $info->{'severity'} || 'medium';
    my $confidence = $info->{'confidence'} || 85;

    my @bits = split(/::/,lc($class));
    my $feed_name = '';
    if($bits[$#bits-1] eq 'plugin'){
        $feed_name = $bits[$#bits];
    } else {
        $feed_name = $bits[$#bits].' '.$bits[$#bits-1];
    }
    my @recs = $class->search_feed($info->{'detecttime'},$confidence,$severity,$restriction,$max);
    if($recs[0]->{'uuid'}){
        # declassify what we can
        my $hash;
        foreach (reverse(@recs)){
            ## TODO -- test this
            unless($class->table() =~ /_whitelist/){
                next if($class->isWhitelisted($_->{$key}));
            }
            if($hash->{$_->{$key}}){
                if($_->{'restriction'} eq 'private'){
                    next unless($_->{'restriction'} eq 'need-to-know');
                    ## TODO -- fix this, check for greater severity?
                    next unless($_->{'severity'} eq $hash->{$_->{$key}}->{'severity'});
                    next unless($_->{'confidence'} >= $hash->{$_->{$key}}->{'confidence'});
                }

                # take the higher severity
                if($_->{'severity'} eq 'low'){
                    next if($hash->{$_->{$key}}->{'severity'} eq 'low');
                }
                if($_->{'severity'} eq 'medium'){
                    next if($_->{$key}->{'severity'} eq 'medium');
                    next if($_->{$key}->{'confidence'} >= $hash->{$_->{$key}}->{'confidence'});
                }
            }
            $hash->{$_->{$key}} = $_;
        }
        @recs = map { $hash->{$_} } keys(%$hash);

        # sort it out
        @recs = sort { $a->{'detecttime'} cmp $b->{'detecttime'} } @recs;
        require JSON;
        @recs = map { JSON::from_json($_->uuid->data()) } @recs;
    } else {
        my @array;
        foreach (@recs){
            my @keys = grep(!/^_/,keys %$_);
            my $h;
            foreach my $k (@keys){
                $h->{$k} = $_->{$k};
            }
            push(@array,$h);
        }
        @recs = @array;
    }
    my $feed = {
        feed    => {
            title   => $feed_name,
            entry   => \@recs,
        }
    };
    return($feed);
}

sub isWhitelisted { return; }

sub check_params {
    my ($self,$tests,$info) = @_;

    foreach my $key (keys %$info){
        if(exists($tests->{$key})){
            my $test = $tests->{$key};
            next unless($info->{$key});
            unless($info->{$key} =~ m/$test/){
                return(undef,'invaild value for '.$key.': '.$info->{$key});
            }
        }
    }
    return(1);
}

sub lookup {
    my $class = shift;
    my @args = @_;
    return(undef) unless(@args);

    my $ret = $class->search_lookup(@args);
    return($ret);
}

1;