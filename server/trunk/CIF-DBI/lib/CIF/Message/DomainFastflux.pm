package CIF::Message::DomainFastflux;
use base 'CIF::Message::Domain';

use strict;
use warnings;

__PACKAGE__->table('domains_fastflux');
__PACKAGE__->has_a(uuid => 'CIF::Message');

1;