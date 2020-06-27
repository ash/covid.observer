#!/usr/bin/env raku

use lib 'lib';
use CovidObserver::Population;
use CovidObserver::Geo;
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
    my $sth = dbh.prepare('insert into countries (cc, continent, country, population, life_expectancy, area, name_ru, name_in_ru) values (?, ?, ?, ?, ?, ?, ?, ?)');
    for %population<countries>.kv -> $cc, $country {
        my $n = %population<population>{$cc};
        my $age = %population<age>{$cc} || 0;
        my $area = %population<area>{$cc} || 0;
        my $name_ru = %population<translation><ru>{$cc} || '';

        my $continent = $cc ~~ /'/'/ ?? '' !! %population<continent>{$cc};
        # say "$cc, $continent, $country, $n";

        my $name_in_ru = $name_ru ?? "в $name_ru" !! '';
        if %population<cc-translation><ru>{$cc} {
            $name_ru    = %population<cc-translation><ru>{$cc}[0];
            $name_in_ru = %population<cc-translation><ru>{$cc}[1];
        }

        $sth.execute($cc, $continent, $country, $n, $age, $area, $name_ru, $name_in_ru);
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

#| Fetch and generate
multi sub MAIN('update') {
    MAIN('fetch');
    MAIN('generate');
}

#| Fetch the latest COVID-19 data from JHU and rebuild the database
multi sub MAIN('fetch') {
    say "Updating database...";
    dbh.execute('delete from per_day');
    dbh.execute('delete from totals');
    dbh.execute('delete from daily_totals');

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

    say "Importing JHU's data...";
    my $latest-jhu-date = read-jhu-data(%stats); # modifies

    say 'Importing RU data...';
    my $latest-ru-date = read-ru-data(%stats); # modifies

    say 'Importing tests...';
    read-tests(%stats);

    say 'Computing aggregates...';
    data-count-totals(%stats, {World => $latest-jhu-date, RU => $latest-ru-date});
    import-stats-data(%stats);
    import-tests-data(%stats);


    dbh.execute('delete from calendar');
    my $sth = dbh.prepare('insert into calendar (cc, date) values (?, ?)');
    $sth.execute('World', date2yyyymmdd($latest-jhu-date));
    $sth.execute('RU', date2yyyymmdd($latest-ru-date));
    $sth.finish();

    say "Latest JHU data on $latest-jhu-date";
    say "Latest RU data on $latest-ru-date";
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

    my %calendar = get-calendar();
    my %tests = get-tests();

    my %CO =
        countries    => %countries,
        per-day      => %per-day,
        totals       => %totals,
        daily-totals => %daily-totals,
        calendar     => %calendar,
        tests        => %tests,
    ;

    generate-impact-timeline(%CO);
# exit;

    generate-world-stats(%CO, :$skip-excel);
    generate-world-stats(%CO, exclude => 'CN', :$skip-excel);

    generate-pie-diagrams(%CO);
    generate-pie-diagrams(%CO, cc => 'US');
    generate-pie-diagrams(%CO, cc => 'CN');
    generate-pie-diagrams(%CO, cc => 'RU');

    generate-countries-stats(%CO);

    generate-per-capita-stats(%CO);
    generate-per-capita-stats(%CO, cc-only => 'US');
    generate-per-capita-stats(%CO, cc-only => 'CN');
    generate-per-capita-stats(%CO, mode => 'combined');

    generate-china-level-stats(%CO);
    ## generate-common-start-stats(%countries, %per-day, %totals, %daily-totals);

    my %country-stats;
    my $known-countries = get-known-countries();
    for @$known-countries -> $cc {
        %country-stats{$cc} = generate-country-stats($cc, %CO, :%mortality, :%crude, :$skip-excel);
    }

    generate-countries-compare(%country-stats, %countries, limit => 100);
    generate-countries-compare(%country-stats, %countries);
    generate-countries-compare(%country-stats, %countries, prefix => 'US');
    generate-countries-compare(%country-stats, %countries, prefix => 'CN');
    generate-countries-compare(%country-stats, %countries, prefix => 'RU');

    generate-country-stats('CN', %CO, exclude => 'CN/HB');
    ## generate-country-stats('RU', %CO, exclude => 'RU/77');

    generate-continent-graph(%CO);

    for %continents.keys -> $cont {
        generate-continent-stats($cont, %CO, :$skip-excel);
    }

    generate-scattered-age(%CO);
    ## generate-scattered-density(%CO);

    my %levels = generate-overview(%CO);
    generate-world-map(%CO, %levels);

    generate-js-countries(%CO);

    geo-sanity();
    about-pages();
}

#| Re-generate the "About" section pages
multi sub MAIN('about') {
    about-pages();
}

sub about-pages() {
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
