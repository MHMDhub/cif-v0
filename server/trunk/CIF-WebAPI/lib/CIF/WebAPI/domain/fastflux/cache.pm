package CIF::WebAPI::domain::fastflux::cache;
use base 'CIF::WebAPI';

use strict;
use warnings;

sub GET {
    my ($self,$req,$resp) = @_;
    return $self->cachedFeed($req,$resp);
}

1;