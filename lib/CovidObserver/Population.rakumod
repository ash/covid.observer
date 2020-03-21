unit module CovidObserver::Population;

use Locale::Codes::Country;
use Locale::US;
use Text::CSV;

constant $world-population is export = 7_800_000_000;

constant %continents is export =
    # AN => 'Antarctica',
    AF => 'Africa', AS => 'Asia', EU => 'Europe',
    NA => 'North America', OC => 'Oceania', SA => 'South America';

sub parse-population() is export {
    my %population;
    my %countries;

    # Population per country
    # constant $population_source = 'https://data.un.org/_Docs/SYB/CSV/SYB62_1_201907_Population,%20Surface%20Area%20and%20Density.csv';
    my $csv = Text::CSV.new;
    my $io = open 'data/SYB62_1_201907_Population, Surface Area and Density.csv';
    while my $row = $csv.getline($io) {
        my ($n, $country, $year, $type, $value) = @$row;
        next unless $type eq 'Population mid-year estimates (millions)';        

        my $cc = country2cc($country, silent => True);
        next unless $cc;

        $country = 'Iran' if $country ~~ /Iran/;
        $country = 'Venezuela' if $country ~~ /Venezuela/;
        $country = 'Bolivia' if $country ~~ /Bolivia/;
        $country = 'Tanzania' if $country ~~ /Tanzania/;
        $country = 'Moldova' if $country ~~ /Moldova/;
        $country = 'South Korea' if $country ~~ /Korea/;

        %countries{$cc} = $country;
        %population{$cc} = +$value;
    }

    # US population
    # https://www2.census.gov/programs-surveys/popest/tables/2010-2019/state/totals/nst-est2019-01.xlsx from
    # https://www.census.gov/data/datasets/time-series/demo/popest/2010s-state-total.html
    my @us-population = csv(in => 'data/us-population.csv');
    for @us-population -> ($state, $population) {
        my $state-cc = 'US/' ~ state-to-code($state);
        %countries{$state-cc} = $state;
        %population{$state-cc} = +$population / 1_000_000;
    }

    # Continents
    # constant $continents = 'https://pkgstore.datahub.io/JohnSnowLabs/country-and-continent-codes-list/country-and-continent-codes-list-csv_csv/data/b7876b7f496677669644f3d1069d3121/country-and-continent-codes-list-csv_csv.csv'
    my @continent-info = csv(in => 'data/country-and-continent-codes-list-csv_csv.csv');
    my %continent = @continent-info[1..*].map: {$_[3] => $_[1]};

    # Missing countries
    my @more-population = csv(in => 'data/more-population.csv');
    for @more-population -> ($cc, $continent, $country, $population) {
        %countries{$cc} = $country;
        %population{$cc} = +$population / 1_000_000;
        %continent{$cc} = $continent;
    }

    return
        population => %population,
        countries  => %countries,
        continent  => %continent;
}

sub country2cc($country is copy, :$silent = False) is export {
    state %force =
        'United Arab Emirates' => 'AE',
        'North Macedonia' => 'MK',
        'Brunei' => 'BN',
        'Vietnam' => 'VN',
        'Congo (Kinshasa)' => 'CD',
        'Cote d\'Ivoire' => 'CI',
        'Eswatini' => 'SZ',
        'Saint Vincent and the Grenadines' => 'VC',
        'Kosovo' => 'XK',
        'Congo (Brazzaville)' => 'CG',
        'Gambia, The' => 'GM',
        'Bahamas, The' => 'BS',
        'Russian Federation' => 'RU',
        'Russia' => 'RU',
        'Cabo Verde' => 'CV';

    $country = 'Iran' if $country eq 'Iran (Islamic Republic of)';
    $country = 'South Korea' if $country eq 'Republic of Korea';
    $country = 'Czech Republic' if $country eq 'Czechia';
    $country = 'Venezuela' if $country eq 'Venezuela (Boliv. Rep. of)';
    $country = 'Moldova' if $country eq 'Republic of Moldova';
    $country = 'Bolivia' if $country eq 'Bolivia (Plurin. State of)';
    $country = 'Tanzania' if $country eq 'United Rep. of Tanzania';

    $country ~~ s/'Korea, South'/South Korea/;
    $country ~~ s:g/'*'//;
    $country ~~ s/Czechia/Czech Republic/;

    my $cc;
    given $country {
        when %force{$country}:exists {$cc = %force{$country}}
        when 'US'                    {$cc = 'US'}
        default                      {$cc = countryToCode($country)}
    }

    unless $cc {
        note "WARNING: Country code not found for $country" unless $silent;
    }

    return $cc;
}

sub cc2country($cc) is export {
    my $country;

    state %force =
        'AE' => 'United Arab Emirates',
        'MK' => 'North Macedonia',
        'BN' => 'Brunei',
        'VN' => 'Vietnam',
        'CD' => 'Congo (Kinshasa)',
        'CI' => 'Cote d\'Ivoire',
        'SZ' => 'Eswatini',
        'VC' => 'Saint Vincent and the Grenadines',
        'XK' => 'Kosovo',
        'CG' => 'Congo (Brazzaville)',
        'GM' => 'Gambia, The',
        'BS' => 'Bahamas, The',
        'RU' => 'Russian Federation',
        'VE' => 'Venezuela',
        'IR' => 'Iran',
        'BO' => 'Bolivia',
        'TZ' => 'Tanzania',
        'MD' => 'Moldova',
        'KR' => 'South Korea',
        'CV' => 'Cabo Verde';

    given $cc {
        when %force{$cc}:exists {$country = %force{$cc}}
        default                 {$country = codeToCountry($cc)}
    }

    # $country = 'United Arab Emirates' if $country eq 'United Arab Empirates'; # OMG - what a bug in Locale::Codes::Country!

    return $country;
}
