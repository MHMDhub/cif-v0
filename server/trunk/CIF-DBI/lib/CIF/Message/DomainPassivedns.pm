package CIF::Message::DomainPassivedns;
use base 'CIF::Message::Domain';

use strict;
use warnings;

__PACKAGE__->table('domains_passivedns');
__PACKAGE__->has_a(uuid => 'CIF::Message');

1;