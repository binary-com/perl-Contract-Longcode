use strict;
use warnings;

use Test::More;

use Finance::Contract::Longcode qw/shortcode_to_parameters/;

my $params = shortcode_to_parameters('CALLE_R_25_9.073E-05_1594023511_5T_S0P_0', 'BTC');
is_deeply($params, {
        amount => "9.073E-05",
        amount_type => "payout",
        barrier => "S0P",
        bet_type => "CALLE",
        currency => "BTC",
        date_start => "1594023511",
        duration => "5t",
        fixed_expiry => undef,
        is_sold => 0,
        shortcode => "CALLE_R_25_9.073E-05_1594023511_5T_S0P_0",
        starts_as_forward_starting => 0,
        underlying => "R_25",
    }, "is able to parse shortcode with sufficient notation");

$params = shortcode_to_parameters('DIGITODD_R_10_100_1583976032_1T', 'USD');
is_deeply($params, {
        amount => "100",
        amount_type => "payout",
        bet_type => "DIGITODD",
        currency => "USD",
        date_start => "1583976032",
        duration => "1t",
        fixed_expiry => undef,
        is_sold => 0,
        shortcode => "DIGITODD_R_10_100_1583976032_1T",
        starts_as_forward_starting => 0,
        underlying => "R_10",
    });


$params = shortcode_to_parameters('PUT_R_100_0.66_1583976064_1583976079_S0P_0', 'USD');
is_deeply($params, {
        amount => "0.66",
        amount_type => "payout",
        barrier => "S0P",
        bet_type => "PUT",
        currency => "USD",
        date_expiry => "1583976079",
        date_start => "1583976064",
        fixed_expiry => undef,
        is_sold => 0,
        shortcode => "PUT_R_100_0.66_1583976064_1583976079_S0P_0",
        starts_as_forward_starting => 0,
        underlying => "R_100",
    });

done_testing;
