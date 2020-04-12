#!/usr/bin/env raku

use lib 'lib';
use CovidObserver::Population;
use CovidObserver::Data;
use CovidObserver::Statistics;
use CovidObserver::DB;
use CovidObserver::HTML;
use CovidObserver::Generation;
use CovidObserver::Format;

#| Update the database with the population data from the CSV files
multi sub MAIN('population') {
    my %population = parse-population();

    say "Updating database...";

    dbh.execute('delete from countries');
    my $sth = dbh.prepare('insert into countries (cc, continent, country, population, life_expectancy, area) values (?, ?, ?, ?, ?, ?)');
    for %population<countries>.kv -> $cc, $country {
        my $n = %population<population>{$cc};
        my $age = %population<age>{$cc} || 0;
        my $area = %population<area>{$cc} || 0;

        my $continent = $cc ~~ /'/'/ ?? '' !! %population<continent>{$cc};
        say "$cc, $continent, $country, $n";

        $sth.execute($cc, $continent, $country, $n, $age, $area);
    }
    $sth.finish();

    dbh.execute('delete from mortality');
    $sth = dbh.prepare('insert into mortality (cc, year, month, n) values (?, ?, ?, ?)');
    for %population<mortality>.keys -> $cc {
        my $years = 0;
        for %population<mortality>{$cc}.keys.sort.reverse -> $year {
            last if ++$years > 5; # Take last 5 non-empty years of data
            for %population<mortality>{$cc}{$year}.keys -> $month {
                $sth.execute($cc, $year, $month, %population<mortality>{$cc}{$year}{$month} || 0);
            }
        }
    }
    $sth.finish();

    dbh.execute('delete from crude');
    $sth = dbh.prepare('insert into crude (cc, year, deaths) values (?, ?, ?)');
    for %population<crude>.keys -> $cc {
        for %population<crude>{$cc}.keys.sort -> $year {
            $sth.execute($cc, $year, %population<crude>{$cc}{$year} || 0);
        }
    }
    $sth.finish();
}

#| Fetch the latest COVID-19 data from JHU and rebuild the database
multi sub MAIN('fetch') {
    my %stats = read-covid-data();

    say "Updating database...";

    dbh.execute('delete from per_day');
    dbh.execute('delete from totals');
    dbh.execute('delete from daily_totals');

    for %stats<confirmed><per-day>.keys -> $cc {
        my @values;
        for %stats<confirmed><per-day>{$cc}.keys -> $date {
            my $confirmed = %stats<confirmed><per-day>{$cc}{$date} || 0;
            my $failed = %stats<failed><per-day>{$cc}{$date} || 0;
            my $recovered = %stats<recovered><per-day>{$cc}{$date} || 0;

            @values.push("('$cc','{date2yyyymmdd($date)}',$confirmed,$failed,$recovered)");  # Safe here
        }

        my $values-sql = join ',', @values;
        my $sth = dbh.prepare("insert into per_day (cc, date, confirmed, failed, recovered) values $values-sql");
        $sth.execute();
        $sth.finish();

        $sth = dbh.prepare('insert into totals (cc, confirmed, failed, recovered) values (?, ?, ?, ?)');
        $sth.execute($cc, %stats<confirmed><total>{$cc}, %stats<failed><total>{$cc}, %stats<recovered><total>{$cc});
        $sth.finish();
    }

    for %stats<confirmed><daily-total>.keys -> $date {
        my $confirmed = %stats<confirmed><daily-total>{$date} || 0;
        my $failed = %stats<failed><daily-total>{$date} || 0;
        my $recovered = %stats<recovered><daily-total>{$date} || 0;

        my $sth = dbh.prepare('insert into daily_totals (date, confirmed, failed, recovered) values (?, ?, ?, ?)');
        $sth.execute(date2yyyymmdd($date), $confirmed, $failed, $recovered);
        $sth.finish();
    }
}

#| Generate web pages based on the current data from the database
multi sub MAIN('generate', Bool :$skip-excel = False) {
    my %countries = get-countries();

    my %per-day = get-per-day-stats();
    my %totals = get-total-stats();
    my %daily-totals = get-daily-totals-stats();

    add-country-arrows(%countries, %per-day);
    my %mortality = get-mortality-data();
    my %crude = get-crude-data();

    generate-world-stats(%countries, %per-day, %totals, %daily-totals, :$skip-excel);
    generate-world-stats(%countries, %per-day, %totals, %daily-totals, exclude => 'CN', :$skip-excel);

    generate-countries-stats(%countries, %per-day, %totals, %daily-totals);

    generate-per-capita-stats(%countries, %per-day, %totals, %daily-totals);
    generate-per-capita-stats(%countries, %per-day, %totals, %daily-totals, cc-only => 'US');
    generate-per-capita-stats(%countries, %per-day, %totals, %daily-totals, cc-only => 'CN');
    generate-per-capita-stats(%countries, %per-day, %totals, %daily-totals, mode => 'combined');

    generate-china-level-stats(%countries, %per-day, %totals, %daily-totals);
    # generate-common-start-stats(%countries, %per-day, %totals, %daily-totals);

    my %country-stats;
    for get-known-countries() -> $cc {
        %country-stats{$cc} = generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals, :%mortality, :%crude, :$skip-excel);
    }

    generate-countries-compare(%country-stats, %countries, limit => 100);
    generate-countries-compare(%country-stats, %countries);
    generate-countries-compare(%country-stats, %countries, prefix => 'US');
    generate-countries-compare(%country-stats, %countries, prefix => 'CN');

    generate-country-stats('CN', %countries, %per-day, %totals, %daily-totals, exclude => 'CN/HB');
    generate-continent-graph(%countries, %per-day, %totals, %daily-totals);

    for %continents.keys -> $cont {
        generate-continent-stats($cont, %countries, %per-day, %totals, %daily-totals, :$skip-excel);
    }


    generate-scattered-age(%countries, %per-day, %totals, %daily-totals);
    generate-scattered-density(%countries, %per-day, %totals, %daily-totals);

    my %levels = generate-overview(%countries, %per-day, %totals, %daily-totals);
    generate-world-map(%countries, %per-day, %totals, %daily-totals, %levels);

    generate-js-countries(%countries, %per-day, %totals, %daily-totals);

    geo-sanity();
}

#| Re-generate the "About" section pages
multi sub MAIN('about') {
    html-template('/about', 'About the project', 'html/about.html'.IO.slurp);
    html-template('/sources', 'Data sources', 'html/sources.html'.IO.slurp);
    html-template('/news', 'Covid.observer news and updates', 'html/news.html'.IO.slurp);
}

#| Check if there are country mismatches
multi sub MAIN('sanity') {
    geo-sanity();
}

#| Generate the 404 page
multi sub MAIN('404') {
    html-template('/404', '404 Virus Not Found', q:to/HTML/);
        <h1 style="margin-top: 2em; margin-bottom: 3em">Error 404<br/>Virus Not Found</h1>
    HTML
}

#| Run as: ./covid.raku series > misc/series.cpp
multi sub MAIN('series') {
    my %countries = get-countries();
    my %per-day = get-per-day-stats();
    my %totals = get-total-stats();

    for <confirmed failed recovered> -> $series-type {
        my $comma = '';
        say "series $series-type = \{";
        for %per-day.keys.sort -> $cc {
            next if %totals{$cc}<confirmed> < 1000;

            my @data;
            my $prev-date;
            for %per-day{$cc}.keys.sort[1..*] -> $date {
                unless ($prev-date) {
                    $prev-date = $date;
                    next;
                }

                @data.push(
                    %per-day{$cc}{$date}{$series-type} -
                    %per-day{$cc}{$prev-date}{$series-type}
                );

                $prev-date = $date;
            }

            # NB. join and push would drastically slow Rakudo down at this point. So printing asap.
            say "\t" ~ $comma ~ '{"' ~ $cc ~ '", {' ~ @data.join(', ') ~ "}}";
            $comma = ',' unless $comma;
        }
        say "};";
    }
}
