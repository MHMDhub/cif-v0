package CIF::Archive;
use base 'CIF::DBI';

require 5.008;
use strict;
use warnings;

our $VERSION = '0.01_02';
$VERSION = eval $VERSION;  # see L<perlmodstyle>

use Data::Dumper;
use Config::Simple;
use CIF::Utils ':all';

__PACKAGE__->table('archive');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All => qw/id uuid format description data restriction created source/);
__PACKAGE__->columns(Essential => qw/id uuid format description source restriction data created/);
__PACKAGE__->sequence('archive_id_seq');

sub plugins {
    my $class = shift;
    my $type = shift || return(undef);

    my @plugs;
    for(lc($type)){
        if(/^storage$/){
            require CIF::Archive::Storage;
            return CIF::Archive::Storage->plugins();
            last;
        }
        if(/^datatype$/){
            require CIF::Archive::DataType;
            return CIF::Archive::DataType->plugins();
            last;
        }
    }
}

sub data_hash {
    my $class = shift;
    foreach my $p ($class->plugins('storage')){
        if(my $h = $p->data_hash($class->data(),$class->uuid())){
            return($h);
        }
    }
    my $hash = JSON::from_json($class->data());
    $hash->{'uuid'} = $class->uuid();
    return JSON::from_json($class->data());
}

sub insert {
    my $self = shift;
    my $info = shift;

    my $source  = $info->{'source'} || 'localhost';
    $source = genSourceUUID($source) unless(isUUID($source));
    $info->{'source'} = $source;

    # need to run through this first; make sure it's worth doing the insert
    ## TODO -- make this support multiple plugins, we may want to index this 7 ways to sunday.
    my @dt_plugs;
    foreach($self->plugins('datatype')){
        my ($ret,$err) = $_->prepare($info);
        # next unless we have something to work with
        # 0 - means there's something wrong with the value (whitelisted, private address space, etc)
        next unless(defined($ret));
        # if there's an error; return the error (eg: whitelisted...)
        return(undef,$err) if($ret == 0);
        # we do the CIF::Arvhive->insert() first, then insert to this plugin at the end
        push(@dt_plugs,$_);
    }

    # defaults to json
    require CIF::Archive::Storage::Json;
    my $bucket = 'CIF::Archive::Storage::Json';
    if($info->{'storage'} && $info->{'storage'} eq 'binary'){
        $bucket = 'CIF::Archive::Storage::Binary';
    } else {
        foreach($self->plugins('storage')){
            $bucket = $_ if($_->prepare($info));
        }
    }
    delete($info->{'storage'});

    my $msg = $bucket->convert($info);
    unless($info->{'format'}){
        $info->{'format'} = $bucket->format();
    }

    $info->{'uuid'} = genMessageUUID($source,$msg);
    $info->{'data'} = $msg;

    my $id = eval {
        $self->SUPER::insert({
            uuid        => $info->{'uuid'},
            format      => $info->{'format'},
            description => $info->{'description'},
            data        => $info->{'data'},
            restriction => $info->{'restriction'} || 'private',
            source      => $info->{'source'} || 'unknown',
        })
    };
    if($@){
        return($@,undef) unless($@ =~ /duplicate key value violates unique constraint/);
        $id = eval { $self->retrieve(uuid => $info->{'uuid'}) };
    }
    $info->{'uuid'} = $id->uuid();
    delete($info->{'format'});
    # now do the plugin insert
    foreach my $p (@dt_plugs){
        my ($did,$err) = $p->insert($info);
        if($err){
            warn $err;
            $id->delete();
            return($err,undef);
        }
    }
    return(undef,$id);
}

sub lookup {
    my $class = shift;
    my $info = shift;
    $info->{'limit'} = 10000 unless($info->{'limit'});

    my $ret;
    if(isUUID($info->{'query'})){
        $ret = CIF::Archive->retrieve(uuid => $info->{'query'});
    } else {
        foreach my $p ($class->plugins('datatype')){
            $ret = $p->lookup($info);
            last if($ret);
        }
    }

    unless($info->{'nolog'}){
        my $source = genSourceUUID($info->{'source'} || 'unknown');
        my $dt = DateTime->from_epoch(epoch => time());
        $dt = $dt->ymd().'T'.$dt->hour().':00:00Z';
        my $q = lc($info->{'query'});
        my ($md5,$sha1,$addr);
        for($q){
            if(/^[a-f0-9]{32}$/){
                $md5 = $q;
                last;
            }
            if(/^[a-f0-9]{40}$/){
                $sha1 = $q;
                last;
            }
            $addr = $q;
        }

        my ($err,$id) = CIF::Archive->insert({
            address     => $addr,
            source      => $source,
            impact      => 'search',
            description => 'search '.$info->{'query'},
            detecttime  => $dt,
            md5         => $md5,
            sha1        => $sha1,
            confidence  => 50,
            severity    => 'low',
        });
    }
    return($ret);
}

1;
=head1 NAME

CIF::Archive - Perl extension for interfacing with the CIF Archive.

=head1 SYNOPSIS

  use CIF::Archive

  my $a = CIF::Archive->new();
  my $id = $a->insert({
    address     => '1.1.1.1',
    portlist    => '22',
    impact      => 'scanner',
    severity    => 'medium',
    description => 'ssh scanner',
  });

  my @recs = CIF::Archive->search(descripion => 'ssh scanner');

  # ->lookup() is an API into the plugins, searches the index tables automatically
  # the plugin stack figures out which plugin understands '1.1.1.1' (eg: CIF::Archive::DataType::Plugin::Infrastructure::prepare)

  my $qid = $a->lookup({
    query   => '1.1.1.1',
  });

  my $qid = $a->lookup({
    query   => 'scanner',
  });

  my $id = $a->insert({
    address     => 'example.com',
    impact      => 'malware domain',
    description => 'mebroot',
  });

  CIF::Archive->connection('DBI:Pg:database=cif2;host=localhost','postgres','',{ AutoCommit => 1} );

=head1 DESCRIPTION

This module was created to be a generic storage "archive" for the Collective Intelligence Framework. It's simple and is to be exteded both by CIF::Archive::DataType and CIF::Archive::Storage for both custom indicies and storage formats. It's accompanied by CIF::WebAPI as an extensible framework for creating REST based (Apache2::REST) services around these extensions.

=head1 SEE ALSO

 http://code.google.com/p/collective-intelligence-framework/
 CIF::WebAPI
 CIF::Archive::DataType::Plugin::Feed
 CIF::Archive::Storage::Plugin::Iodef
 CIF::FeedParser

=head1 AUTHOR

Wes Young, E<lt>wes@barely3am.comE<gt>

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2011 by Wes Young (claimid.com/wesyoung)
 Copyright (C) 2011 by the Trustee's of Indiana University (www.iu.edu)
 Copyright (C) 2011 by the REN-ISAC (www.ren-isac.net)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
