# NAME

Finance::Contract::Longcode - contains utility functions to convert a shortcode to human readable longcode and shortcode to a hash reference parameters.

# SYNOPSIS

    use Finance::Contract::Longcode qw(shortcode_to_longcode);

    my $longcode = shortcode_to_longcode('PUT_FRXEURNOK_100_1394590423_1394591143_S0P_0','USD');

## shortcode\_to\_longcode

Converts shortcode to human readable longcode. Requires a shortcode and currency.

Returns an array reference of strings.

## shortcode\_to\_parameters

Converts shortcode to a hash reference parameters. Requires shortcode and currency.

Returns a hash reference.
