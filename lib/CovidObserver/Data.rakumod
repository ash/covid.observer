unit module CovidObserver::Data;

use HTTP::UserAgent;
use Text::CSV;
use IO::String;

use CovidObserver::Population;

# constant %covid-sources is export =
#     confirmed => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Confirmed.csv',
#     failed    => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Deaths.csv',
#     recovered => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Recovered.csv';

sub read-covid-data() is export {
    my %stats =
        confirmed => {
            per-day     => {},
            total       => {},
            daily-total => {},
        },
        failed => {
            per-day     => {},
            total       => {},
            daily-total => {},
        },
        recovered => {
            per-day     => {},
            total       => {},
            daily-total => {},
        }
    ;

    my %dates;
    my %cc;

    for dir('COVID-19/csse_covid_19_data/csse_covid_19_daily_reports', test => /'.csv'$/) -> $path {
        $path.path ~~ / (\d\d) '-' (\d\d) '-' \d\d(\d\d) '.csv' /;
        my $month = ~$/[0];
        my $day   = ~$/[1];
        my $year  = ~$/[2];
        my $date = "$month/$day/$year";
        %dates{$date} = 1;

        my $data = $path.slurp;
        my $fh = IO::String.new($data);

        my $csv = Text::CSV.new;
        my @headers = $csv.getline($fh);

        while my @row = $csv.getline($fh) {
            my ($country, $confirmed, $failed, $recovered);

            if @headers[0] ne 'FIPS' {
                $country = @row[1] || '';
                if $country eq 'Netherlands' {
                    $country = @row[0] || '';
                }

                ($confirmed, $failed, $recovered) = @row[3..5];
            }
            else {
                $country = @row[3] || '';
                if $country eq 'Netherlands' {
                    $country = @row[2] || '';
                }

                ($confirmed, $failed, $recovered) = @row[7..9];
            }

            my $cc = country2cc($country);
            next unless $cc;

            %cc{$cc} = 1;

            %stats<confirmed><per-day>{$cc}{$date} += $confirmed;
            %stats<failed><per-day>{$cc}{$date}    += $failed;
            %stats<recovered><per-day>{$cc}{$date} += $recovered;

            %stats<confirmed><total>{$cc} += $confirmed;
            %stats<failed><total>{$cc}    += $failed;
            %stats<recovered><total>{$cc} += $recovered;

            %stats<confirmed><daily-total>{$date} += $confirmed;
            %stats<failed><daily-total>{$date}    += $failed;
            %stats<recovered><daily-total>{$date} += $recovered;
        }
    }

    # Fill zeroes for missing dates/countries
    for %dates.keys -> $date {
        for %cc.keys -> $cc {
            %stats<confirmed><per-day>{$cc}{$date} //= 0;
            %stats<failed><per-day>{$cc}{$date}    //= 0;
            %stats<recovered><per-day>{$cc}{$date} //= 0;

            %stats<confirmed><total>{$cc} //= 0;
            %stats<failed><total>{$cc}    //= 0;
            %stats<recovered><total>{$cc} //= 0;

            %stats<confirmed><daily-total>{$date} //= 0;
            %stats<failed><daily-total>{$date}    //= 0;
            %stats<recovered><daily-total>{$date} //= 0;
        }
    }

    return %stats;
}

# sub fetch-covid-data() is export {
#     my $ua = HTTP::UserAgent.new;
#     $ua.timeout = 30;

#     my %stats;

#     for %covid-sources.kv -> $type, $url {
#         say "Getting '$type'...";

#         my $response = $ua.get($url);

#         if $response.is-success {
#             say "Processing '$type'...";
#             %stats{$type} = extract-covid-data($response.content);
#         }
#         else {
#             die $response.status-line;
#         }
#     }

#     return %stats;
# }

# sub extract-covid-data($data) is export {
#     my $csv = Text::CSV.new;
#     my $fh = IO::String.new($data);

#     my @headers = $csv.getline($fh);
#     my @dates = @headers[4..*];

#     my %per-day;
#     my %total;
#     my %daily-per-country;
#     my %daily-total;

#     while my @row = $csv.getline($fh) {
#         my $country = @row[1] || '';

#         if $country eq 'Netherlands' {
#             $country = @row[0] || '';
#         }

#         my $cc = country2cc($country);
#         next unless $cc;

#         for @dates Z @row[4..*] -> ($date, $n) {
#             %per-day{$cc}{$date} += $n;
#             %daily-per-country{$date}{$cc} += $n;

#             %total{$cc} = %per-day{$cc}{$date};
#         }

#         if $cc eq 'US' {
#             my $state = @row[0];

#             if $state && $state !~~ /Princess/ && $state !~~ /','/ && $state ne 'US' { # What is 'US/US'?
#                 my $state-cc = state2code($state);
#                 unless $state-cc {
#                     say "WARNING: State code not found for US/$state";
#                     next;
#                 }
#                 $state-cc = 'US/' ~ $state-cc;

#                 for @dates Z @row[4..*] -> ($date, $n) {
#                     %per-day{$state-cc}{$date} += $n;
#                     %daily-per-country{$date}{$state-cc} += $n;

#                     %total{$state-cc} = %per-day{$state-cc}{$date};
#                 }
#             }
#         }

#         if $cc eq 'CN' {
#             my $region = @row[0];

#             if $region {
#                 my $region-cc = 'CN/' ~ chinese-region-to-code($region);

#                 for @dates Z @row[4..*] -> ($date, $n) {
#                     %per-day{$region-cc}{$date} += $n;
#                     %daily-per-country{$date}{$region-cc} += $n;

#                     %total{$region-cc} = %per-day{$region-cc}{$date};
#                 }
#             }
#         }
#     }

#     for %daily-per-country.kv -> $date, %per-country {
#         %daily-total{$date} = 0 unless %daily-total{$date}:exists;
#         for %per-country.keys -> $cc {
#             next if $cc ~~ /'/'/;
#             %daily-total{$date} += %per-country{$cc};
#         }
#     }

#     return
#         per-day => %per-day,
#         total => %total,
#         daily-total => %daily-total;
# }
