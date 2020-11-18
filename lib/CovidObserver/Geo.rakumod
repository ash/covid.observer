unit module CovidObserver::Geo;

use Locale::Codes::Country;
use Locale::US;
use Text::CSV;

use CovidObserver::DB;

constant %continents is export =
    # AN => 'Antarctica',
    AF => 'Africa', AS => 'Asia', EU => 'Europe',
    NA => 'North America', OC => 'Oceania', SA => 'South America';

sub country2cc($country is copy, :$silent = False) is export {
    $country.=trim();

    state %force =
        'United Arab Emirates' => 'AE',
        'North Macedonia' => 'MK',
        'Brunei' => 'BN',
        'Vietnam' => 'VN',
        'Congo (Kinshasa)' => 'CD',
        'Democratic Republic of the Congo' => 'CD',
        'Cote d\'Ivoire' => 'CI',
        'Eswatini' => 'SZ',
        'Saint Vincent and the Grenadines' => 'VC',
        'Kosovo' => 'XK',
        'Congo (Brazzaville)' => 'CG',
        'Gambia, The' => 'GM',
        'Bahamas, The' => 'BS',
        'Russian Federation' => 'RU',
        'Russia' => 'RU',
        'Cabo Verde' => 'CV',
        'Sierra Leone' => 'SL',
        'Syrian Arab Republic' => 'SY',
        'Curaçao' => 'CW',
        'Curacao' => 'CW',
        'Sint Maarten' => 'SX',
        'Saint Martin' => 'SX',
        'Reunion' => 'RE',
        'The Bahamas' => 'BS',
        'The Gambia' => 'GM',
        'Mainland China' => 'CN',
        'UK' => 'GB',
        'Laos' => 'LA',
        'Macau' => 'MO',
        'Ivory Coast' => 'CI',
        'Saint Barthelemy' => 'BL',
        'Saint Barthélemy' => 'BL',
        'Palestine' => 'PS',
        'Dem. Rep. of the Congo' => 'CD',
        'Republic of the Congo' => 'CG',
        'East Timor' => 'TL',
        'West Bank and Gaza' => 'IL',
        'Falkland Islands (Islas Malvinas)' => 'FK',
        'Falkland Islands (Malvinas)' => 'FK';

    $country = 'Lao People\'s Democratic Republic' if $country eq 'Lao People\'s Dem. Rep.';
    $country = 'Iran' if $country eq 'Iran (Islamic Republic of)';
    $country = 'South Korea' if $country eq 'Republic of Korea';
    $country = 'South Korea' if $country eq 'Korea (Republic of)';
    $country = 'Czech Republic' if $country eq 'Czechia';
    $country = 'Venezuela' if $country ~~ /Venezuela/;
    $country = 'Moldova' if $country eq 'Republic of Moldova';
    $country = 'Bolivia' if $country ~~ /Bolivia/;
    $country = 'Tanzania' if $country eq 'United Rep. of Tanzania';
    $country = 'Micronesia' if $country ~~ /Micronesia/;
    $country = 'North Macedonia' if $country ~~ /'North Macedonia'/;
    $country = 'North Macedonia' if $country eq 'The Former Yugoslav Rep. of Macedonia';
    $country = 'United Kingdom' if $country ~~ /'United Kingdom of Great Britain'/;
    $country = 'Saint Martin' if $country ~~ / 'St. Martin' | 'St Martin' /;
    $country = 'Hong Kong' if $country ~~ /'Hong Kong SAR'/;
    $country = 'Palestine' if $country ~~ /Palestine|Palestinian/;
    $country = 'Macau' if $country ~~ /'Macao SAR'/;
    $country = 'French Guiana' if $country eq 'Fench Guiana'; # typo in the source data
    $country = 'Myanmar' if $country eq 'Burma';
    $country = 'Bonaire' if $country ~~ /Bonaire/;
    $country = 'Slovakia' if $country ~~ /'Slovak Republic'/;

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
        'CV' => 'Cabo Verde',
        'SL' => 'Sierra Leone',
        'CW' => 'Curaçao',
        'SX' => 'Saint Martin',
        'LA' => 'Laos',
        'FM' => 'Micronesia',
        'BL' => 'Saint Barthélemy',
        'PS' => 'Palestine',
        'CD' => 'Democratic Republic of the Congo',
        'CG' => 'Republic of the Congo',
        'FK' => 'Falkland Islands';

    given $cc {
        when %force{$cc}:exists {$country = %force{$cc}}
        default                 {$country = codeToCountry($cc)}
    }

    return $country;
}

sub chinese-region-to-code($code) is export {
    state %provinces;

    unless %provinces.keys {
        my $sth = dbh.prepare('select cc, country from countries where cc like "CN/%"');
        $sth.execute();

        for $sth.allrows(:array-of-hash) -> %row {
            my $code = %row<cc>;
            $code ~~ s/'CN/'//;
            %provinces{%row<country>} = $code;
        }

        # different names
        %provinces{'Guangxi'} = 'GX';
        %provinces{'Xinjiang'} = 'XJ';
        %provinces{'Inner Mongolia'} = 'NM';
        %provinces{'Ningxia'} = 'NX';
        %provinces{'Macau'} = 'MO';
        %provinces{'Tibet'} = 'XZ';
    }

    return %provinces{$code};
}

sub state2code($state) is export {
    return 'VI' if $state eq 'United States Virgin Islands';

    return state-to-code($state);
}

sub ru-region-to-code($region is copy) is export {
    state %regions;

    $region.=trim();

    unless %regions.keys {
        my $sth = dbh.prepare('select cc, name_ru from countries where cc like "RU/%"');
        $sth.execute();
        for $sth.allrows(:array-of-hash) -> %row {
            my $code = %row<cc>;
            $code ~~ s/'RU/'//;
            %regions{%row<name_ru>} = $code;
        }

        %regions{'Кемеровская область'} = 42;
        %regions{'Татарстан'} = 16;
        %regions{'Ханты-Мансийский АО'} = 86;
        %regions{'Чувашская республика'} = 21;
        %regions{'Республика Чувашия'} = 21;
        %regions{'Башкортостан'} = '02';
        %regions{'Республика Северная Осетия - Алания'} = 15;
        %regions{'Республика Северная Осетия — Алания'} = 15;
        %regions{'Республика Ингушетия'} = '06';
        %regions{'Еврейская автономная область'} = 79;
        %regions{'Ямало-Ненецкий автономный округ'} = 89;
        %regions{'Ненецкий автономный округ'} = 83;
        %regions{'Чукотский автономный округ'} = 87;
    }

    say "WARNING: Region code not found for $region" unless %regions{$region};

    return %regions{$region};
}
