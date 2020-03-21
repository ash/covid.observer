unit module CovidObserver::Data;

use HTTP::UserAgent;
use Text::CSV;
use IO::String;
use Locale::US;

use CovidObserver::Population;

constant %covid-sources is export =
    confirmed => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Confirmed.csv',
    failed    => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Deaths.csv',
    recovered => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Recovered.csv';

sub fetch-covid-data(%sources) is export {
    my $ua = HTTP::UserAgent.new;
    $ua.timeout = 30;

    my %stats;

    for %sources.kv -> $type, $url {
        say "Getting '$type'...";

        my $response = $ua.get($url);

        if $response.is-success {
            say "Processing '$type'...";
            %stats{$type} = extract-covid-data($response.content);
        }
        else {
            die $response.status-line;
        }
    }

    return %stats;
}

sub extract-covid-data($data) is export {
    my $csv = Text::CSV.new;
    my $fh = IO::String.new($data);

    my @headers = $csv.getline($fh);
    my @dates = @headers[4..*];

    my %per-day;
    my %total;
    my %daily-per-country;
    my %daily-total;

    while my @row = $csv.getline($fh) {
        my $country = @row[1] || '';

        my $cc = country2cc($country);
        next unless $cc;

        for @dates Z @row[4..*] -> ($date, $n) {
            %per-day{$cc}{$date} += $n;
            %daily-per-country{$date}{$cc} += $n;

            my $uptodate = %per-day{$cc}{$date};
            %total{$cc} = $uptodate if !%total{$cc} or $uptodate > %total{$cc};
        }

        if $cc eq 'US' {
            my $state = @row[0];

            if $state && $state !~~ /Princess/ && $state !~~ /','/ {
                my $state-cc = 'US/' ~ state-to-code($state);

                for @dates Z @row[4..*] -> ($date, $n) {
                    %per-day{$state-cc}{$date} += $n;
                    %daily-per-country{$date}{$state-cc} += $n;

                    my $uptodate = %per-day{$state-cc}{$date};
                    %total{$state-cc} = $uptodate if !%total{$state-cc} or $uptodate > %total{$state-cc};
                }
            }
        }
    }

    for %daily-per-country.kv -> $date, %per-country {
        %daily-total{$date} = [+] %per-country.values;
    }

    return 
        per-day => %per-day,
        total => %total,
        daily-total => %daily-total;
}
