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

    my %raw;
    my %us-recovered;
    for dir('COVID-19/csse_covid_19_data/csse_covid_19_daily_reports', test => /'.csv'$/).sort(~*.path) -> $path {
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
            my $region = '';

            if @headers[0] ne 'FIPS' {
                $country = @row[1] || '';
                $region  = @row[0] || '';

                ($confirmed, $failed, $recovered) = @row[3..5];
            }
            else {
                $country = @row[3] || '';
                $region  = @row[2] || '';

                ($confirmed, $failed, $recovered) = @row[7..9];
            }

            if $country eq 'Netherlands' && $region {
                $country = $region;
            }
            elsif $country eq 'France' && $region {
                $country = $region if $date ne "03/23/20"; # Wrongly mixed with French Polynesia data for this date
            }
            elsif $country eq 'Channel Islands' {
                $country = 'United Kingdom';
                $region = '';
            }
            elsif $country eq 'United Kingdom' && $region {
                if $region eq 'Channel Islands' {
                    $region = '';
                }
                else {
                    $country = $region;
                }
            }
            elsif $country eq 'Taipei and environs' {
                $country = 'China';
                $region = 'Taiwan';
            }

            if $region eq 'Wuhan Evacuee' {
                # $country = 'US';
                $region = ''; # Currently located in the US regardles nationality?
            }

            my $cc = country2cc($country);
            next unless $cc;

            my $region-cc = '';

            if $cc eq 'US' && $region eq 'Recovered' { # Canada is fine without this
                %us-recovered{$date} = $recovered // 0;
            }

            if $cc eq 'US' && 
               $region && $region !~~ /Princess/ && $region !~~ /','/
               && $region ne 'US' { # What is 'US/US'?

                $region-cc = state2code($region);
                unless $region-cc {
                    say "WARNING: State code not found for US/$region";
                    next;
                }
                $region-cc = 'US/' ~ $region-cc;
            }
            elsif $cc eq 'CN' {
                if $region {
                    $region-cc = 'CN/' ~ chinese-region-to-code($region);
                }
            }
            
            next if $cc eq 'US' && $region-cc eq '';

            %cc{$cc} = 1;
            %cc{$region-cc} = 1 if $region-cc;

            # += as US divides further per state AND further per city
            %raw{$cc}{$region-cc}{$date}<confirmed> += $confirmed // 0;
            %raw{$cc}{$region-cc}{$date}<failed>    += $failed // 0;
            %raw{$cc}{$region-cc}{$date}<recovered> += $recovered // 0;
        }
    }

    # Count per-day data
    for %raw.keys -> $cc { # only countries
        for %raw{$cc}.keys -> $region-cc { # regions or '' for countries without them
            for %raw{$cc}{$region-cc}.keys -> $date {
                my $confirmed = %raw{$cc}{$region-cc}{$date}<confirmed>;
                my $failed    = %raw{$cc}{$region-cc}{$date}<failed>;
                my $recovered = %raw{$cc}{$region-cc}{$date}<recovered>;

                if $region-cc {
                    %stats<confirmed><per-day>{$region-cc}{$date} = $confirmed;
                    %stats<failed><per-day>{$region-cc}{$date}    = $failed;
                    %stats<recovered><per-day>{$region-cc}{$date} = $recovered;
                }

                # += if there's a region, otherwise bare =
                %stats<confirmed><per-day>{$cc}{$date} += $confirmed;
                %stats<failed><per-day>{$cc}{$date}    += $failed;
                %stats<recovered><per-day>{$cc}{$date} += $recovered;
            }
        }
    }

    for %us-recovered.keys -> $date {
        %stats<recovered><per-day><US>{$date} = %us-recovered{$date};
    }

    # Fill zeroes for missing dates/countries
    for %dates.keys -> $date {
        for %cc.keys -> $cc { # including regions
            %stats<confirmed><per-day>{$cc}{$date} //= 0;
            %stats<failed><per-day>{$cc}{$date}    //= 0;
            %stats<recovered><per-day>{$cc}{$date} //= 0;
        }
    }

    # Count totals
    for %cc.keys -> $cc { # including regions    
        # Take the last day, basically
        my $date = %dates.keys.sort[*-1];
        %stats<confirmed><total>{$cc} = %stats<confirmed><per-day>{$cc}{$date};
        %stats<failed><total>{$cc}    = %stats<failed><per-day>{$cc}{$date};
        %stats<recovered><total>{$cc} = %stats<recovered><per-day>{$cc}{$date};
    }

    # Count totals per day
    for %dates.keys.sort -> $date {
        for %cc.keys -> $cc { 
            # only countries
            next if $cc ~~ /'/'/;

            %stats<confirmed><daily-total>{$date} += %stats<confirmed><per-day>{$cc}{$date};
            %stats<failed><daily-total>{$date}    += %stats<failed><per-day>{$cc}{$date};
            %stats<recovered><daily-total>{$date} += %stats<recovered><per-day>{$cc}{$date};
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
