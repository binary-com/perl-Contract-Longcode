package Finance::Contract::Longcode;

use strict;
use warnings;

our $VERSION = '0.001';

use File::ShareDir ();
use Time::Duration::Concise;
use Scalar::Util qw(looks_like_number);
use Finance::Contract::Category;
use Format::Util::Numbers qw(formatnumber);
use Quant::Framework::Underlying;
use Date::Utility;
use Exporter qw(import);

our @EXPORT_OK = qw(shortcode_to_longcode shortcode_to_parameters);

use constant {
    SECONDS_IN_A_DAY         => 86400,
    FOREX_BARRIER_MULTIPLIER => 1e6,
};

my $LONGCODES = LoadFile(File::ShareDir::dist_file('Finance-Contract-Longcode', 'longcodes.yml'));

sub shortcode_to_longcode {
    my ($shortcode, $currency) = @_;

    my $params = shortcode_to_parameters($shortcode, $currency);

    if ($params->{bet_type} !~ /ico/i && !(defined $params->{date_expiry} || defined $params->{tick_count})) {
        die 'Invalid shortcode. No expiry is specified.';
    }

    my $underlying          = Quant::Framework::Underlying->new($params->{underlying});
    my $contract_type       = $params->{bet_type};
    my $is_forward_starting = $params->{starts_as_forward_starting};
    my $date_start          = Date::Utility->new($params->{date_start});
    my $date_expiry         = Date::Utility->new($params->{date_expiry});
    my $expiry_type         = $params->{tick_expiry} ? 'tick' : $date_expiry->epoch - $date_start->epoch >= SECONDS_IN_A_DAY ? 'daily' : 'intraday';
    $expiry_type .= '_fixed_expiry' if $expiry_type eq 'intraday' && !$is_forward_starting && $params->{fixed_expiry};

    my $longcode_key = lc($contract_type . '_' . $expiry_type);

    die 'Could not find longcode for ' . $longcode_key unless $LONGCODES->{$longcode_key};

    my @longcode = ($LONGCODES->{$longcode_key}, $currency, formatnumber('price', $currency, $params->{amount}), $underlying->display_name);

    my ($when_end, $when_start) = ([], []);
    if ($expiry_type eq 'intraday_fixed_expiry') {
        $when_end = [$date_expiry->datetime . ' GMT'];
    } elsif ($expiry_type eq 'intraday') {
        $when_end = [Time::Duration::Concise->new(interval => $date_expiry->epoch - $date_start->epoch)->as_string];
        $when_start = ($is_forward_starting) ? [$date_start->db_timestamp . ' GMT'] : [$LONGCODES->{contract_start_time}];
    } elsif ($expiry_type eq 'daily') {
        $when_end = [$LONGCODES->{close_on}, $date_expiry->date];
    } elsif ($expiry_type eq 'tick') {
        $when_end   = [$params->{tick_count}];
        $when_start = [$LONGCODES->{first_tick}];
    }

    push @longcode, ($when_start, $when_end);

    if ($contract_type =~ /DIGIT/) {
        push @longcode, $params->{barrier};
    } elsif (exists $params->{high_barrier} && exists $params->{low_barrier}) {
        push @longcode, map { _barrier_display_text($_, $underlying) } ($params->{high_barrier}, $params->{low_barrier});
    } elsif (exists $params->{barrier}) {
        push @longcode, _barrier_display_text($params->{barrier}, $underlying);
    } else {
        # the default to this was set by BOM::Product::Contract::Strike but we skipped that for speed reason
        push @longcode, [$underlying->pip_size];
    }

    return \@longcode;
}

sub shortcode_to_parameters {
    my ($shortcode, $currency, $is_sold) = @_;

    my ($bet_type, $underlying_symbol, $payout, $date_start, $date_expiry, $barrier, $barrier2, $prediction, $fixed_expiry, $tick_expiry,
        $how_many_ticks, $forward_start, $binaryico_per_token_bid_price,
        $binaryico_number_of_tokens);

    my ($initial_bet_type) = split /_/, $shortcode;

    my $legacy_params = {
        bet_type   => 'Invalid',    # it doesn't matter what it is if it is a legacy
        underlying => 'config',
        currency   => $currency,
    };

    return $legacy_params if (not exists Finance::Contract::Category::get_all_contract_types()->{$initial_bet_type} or $shortcode =~ /_\d+H\d+/);

    # List of lookbacks
    my $nonbinary_list = 'LBFIXEDCALL|LBFIXEDPUT|LBFLOATCALL|LBFLOATPUT|LBHIGHLOW';

    if ($shortcode =~ /^([^_]+)_([\w\d]+)_(\d*\.?\d*)_(\d+)(?<start_cond>F?)_(\d+)(?<expiry_cond>[FT]?)_(S?-?\d+P?)_(S?-?\d+P?)$/) {

        # Both purchase and expiry date are timestamp (e.g. a 30-min bet)

        $bet_type          = $1;
        $underlying_symbol = $2;
        $payout            = $3;
        $date_start        = $4;
        $forward_start     = 1 if $+{start_cond} eq 'F';
        $barrier           = $8;
        $barrier2          = $9;
        $fixed_expiry      = 1 if $+{expiry_cond} eq 'F';
        if ($+{expiry_cond} eq 'T') {
            $tick_expiry    = 1;
            $how_many_ticks = $6;
        } else {
            $date_expiry = $6;
        }
    }

    # Contract without barrier
    elsif ($shortcode =~ /^([^_]+)_(R?_?[^_\W]+)_(\d*\.?\d*)_(\d+)_(\d+)(?<expiry_cond>[T]?)$/) {
        $bet_type          = $1;
        $underlying_symbol = $2;
        $payout            = $3;
        $date_start        = $4;
        if ($+{expiry_cond} eq 'T') {
            $tick_expiry    = 1;
            $how_many_ticks = $5;
        }
    } elsif ($shortcode =~ /^BINARYICO_(\d+\.?\d*)_(\d+)$/) {
        $bet_type                      = 'BINARYICO';
        $underlying_symbol             = 'BINARYICO';
        $binaryico_per_token_bid_price = $1;
        $binaryico_number_of_tokens    = $2;

    }

    else {
        return $legacy_params;
    }

    $barrier = _strike_string($barrier, $underlying_symbol, $bet_type)
        if defined $barrier;
    $barrier2 = _strike_string($barrier2, $underlying_symbol, $bet_type)
        if defined $barrier2;
    my %barriers =
        ($barrier and $barrier2)
        ? (
        high_barrier => $barrier,
        low_barrier  => $barrier2
        )
        : (defined $barrier) ? (barrier => $barrier)
        :                      ();

    my $bet_parameters = {

        shortcode   => $shortcode,
        bet_type    => $bet_type,
        underlying  => $underlying_symbol,
        amount_type => $bet_type eq 'BINARYICO' ? 'stake' : 'payout',
        amount      => $bet_type eq 'BINARYICO' ? $binaryico_per_token_bid_price : $payout,
        ($bet_type =~ /$nonbinary_list/) ? (unit => $payout) : (),

        date_start   => $date_start,
        date_expiry  => $date_expiry,
        prediction   => $prediction,
        currency     => $currency,
        fixed_expiry => $fixed_expiry,
        tick_expiry  => $tick_expiry,
        tick_count   => $how_many_ticks,
        is_sold      => $is_sold,
        ($forward_start) ? (starts_as_forward_starting => $forward_start) : (),
        (
            $bet_type eq 'BINARYICO'
            ? (
                binaryico_number_of_tokens    => $binaryico_number_of_tokens,
                binaryico_per_token_bid_price => $binaryico_per_token_bid_price
                )
            : ()
        ),
        %barriers,
    };

    return $bet_parameters;
}

sub _barrier_display_text {
    my ($supplied_barrier, $underlying) = @_;

    return $underlying->pipsized_value($supplied_barrier) if $supplied_barrier =~ /^\d+(?:\.\d{0,12})?$/;

    my ($string, $pips);
    if ($supplied_barrier =~ /^S[-+]?\d+P$/) {
        ($pips) = $supplied_barrier =~ /S([+-]?\d+)P/;
    } elsif ($supplied_barrier =~ /^[+-](?:\d+\.?\d{0,12})/) {
        $pips = $supplied_barrier / $underlying->pip_size;
    } else {
        die "Unrecognized supplied barrier [$supplied_barrier]";
    }

    return [$LONGCODES->{entry_spot}] if abs($pips) == 0;

    if ($underlying->market->name eq 'forex') {
        $string = $pips > 0 ? $LONGCODES->{entry_spot_plus_plural} : $LONGCODES->{entry_spot_minus_plural};
        # taking the absolute value of $pips because the sign will be taken care of in the $string, e.g. entry spot plus/minus $pips.
        $pips = abs($pips);
    } else {
        $string = $pips > 0 ? $LONGCODES->{entry_spot_plus} : $LONGCODES->{entry_spot_minus};
        # $pips is multiplied by pip size to convert it back to a relative value, e.g. entry spot plus/minus 0.001.
        $pips *= $underlying->pip_size;
        $pips = $underlying->pipsized_value(abs($pips));
    }

    return [$string, $pips];
}

sub _strike_string {
    my ($string, $underlying_symbol, $contract_type_code) = @_;

    # do not use create_underlying because this is going to be very slow due to dependency on chronicle.
    my $underlying = Quant::Framework::Underlying->new($underlying_symbol);

    $string /= FOREX_BARRIER_MULTIPLIER
        if ($contract_type_code !~ /^DIGIT/ and $string and looks_like_number($string) and $underlying->market->absolute_barrier_multiplier);

    return $string;
}

1;
