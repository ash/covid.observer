#!/usr/bin/env raku

use lib 'lib';
use CovidObserver::Population;
use CovidObserver::Data;
use CovidObserver::Statistics;
use CovidObserver::DB;
use CovidObserver::HTML;
use CovidObserver::Generation;

#| Print SQL instructions to set up the database, tables and permissions.
multi sub MAIN('setup', Bool :$force=False, Bool :$verbose=False) {
    my $schema = q:to<EOSQL>;
        DROP DATABASE IF EXISTS covid;
        CREATE DATABASE IF NOT EXISTS covid;
        CREATE USER IF NOT EXISTS 'covid'@'localhost' IDENTIFIED BY 'covid';
        GRANT CREATE      ON covid.* TO 'covid'@'localhost';
        GRANT DROP        ON covid.* TO 'covid'@'localhost';
        GRANT INSERT      ON covid.* TO 'covid'@'localhost';
        GRANT DELETE      ON covid.* TO 'covid'@'localhost';
        GRANT LOCK TABLES ON covid.* TO 'covid'@'localhost';
        GRANT SELECT      ON covid.* TO 'covid'@'localhost';

        USE covid;

        DROP TABLE IF EXISTS countries;
        CREATE TABLE countries (
          cc varchar(5) DEFAULT NULL,
          country varchar(50) DEFAULT NULL,
          continent char(2) DEFAULT '',
          population double DEFAULT 0,
          life_expectancy double DEFAULT 0
        );

        DROP TABLE IF EXISTS daily_totals;
        CREATE TABLE daily_totals (
          date date DEFAULT NULL,
          confirmed int DEFAULT 0,
          failed int DEFAULT 0,
          recovered int DEFAULT 0
        );

        DROP TABLE IF EXISTS per_day;
        CREATE TABLE per_day (
          cc varchar(5) DEFAULT NULL,
          date date DEFAULT NULL,
          confirmed int DEFAULT 0,
          failed int DEFAULT 0,
          recovered int DEFAULT 0
        );

        DROP TABLE IF EXISTS totals;
        CREATE TABLE totals (
          cc varchar(5) DEFAULT NULL,
          confirmed int DEFAULT 0,
          failed int DEFAULT 0,
          recovered int DEFAULT 0
        );

    EOSQL

    if $force {
        # This can be piped to sh/bash for fast teardown & setup
        say "sudo -u root mysql <<SETUPSQL";
        say $schema;
        say "SETUPSQL";
        exit;
    }

    with try dbh() {
        note "Application database 'covid' already exists. No setup needed.";
        note $schema if $verbose;
    }
    else {
        note "Application database 'covid' NOT found. Please run this:";
        # This can be piped to sh/bash for fast teardown & setup
        say "sudo -u root mysql <<SETUPSQL";
        say $schema;
        say "SETUPSQL";
    }
}

#| Update the database with the population data from the CSV files
multi sub MAIN('population') {
    my %population = parse-population();

    say "Updating database...";

    dbh.execute('delete from countries');
    for %population<countries>.kv -> $cc, $country {
        my $n = %population<population>{$cc};
        my $age = %population<age>{$cc} || 0;

        my $continent = $cc ~~ /'/'/ ?? '' !! %population<continent>{$cc};
        say "$cc, $continent, $country, $n";

        my $sth = dbh.prepare('insert into countries (cc, continent, country, population, life_expectancy) values (?, ?, ?, ?, ?)');
        $sth.execute($cc, $continent, $country, $n, $age);
    }
}

#| Fetch the latest COVID-19 data from JHU and rebuild the database
multi sub MAIN('fetch') {
    my %stats = fetch-covid-data(%covid-sources);
    
    say "Updating database...";

    dbh.execute('delete from per_day');
    dbh.execute('delete from totals');
    dbh.execute('delete from daily_totals');

    my %confirmed = %stats<confirmed>;
    my %failed = %stats<failed>;
    my %recovered = %stats<recovered>;

    for %confirmed<per-day>.keys -> $cc {
        for %confirmed<per-day>{$cc}.kv -> $date, $confirmed {
            my $failed = %failed<per-day>{$cc}{$date};
            my $recovered = %recovered<per-day>{$cc}{$date};

            my $sth = dbh.prepare('insert into per_day (cc, date, confirmed, failed, recovered) values (?, ?, ?, ?, ?)');
            $sth.execute($cc, date2yyyymmdd($date), $confirmed, $failed, $recovered);
        }

        my $sth = dbh.prepare('insert into totals (cc, confirmed, failed, recovered) values (?, ?, ?, ?)');
        $sth.execute($cc, %confirmed<total>{$cc}, %failed<total>{$cc}, %recovered<total>{$cc});
    }

    for %confirmed<daily-total>.kv -> $date, $confirmed {
        my $failed = %failed<daily-total>{$date};
        my $recovered = %recovered<daily-total>{$date};

        my $sth = dbh.prepare('insert into daily_totals (date, confirmed, failed, recovered) values (?, ?, ?, ?)');
        $sth.execute(date2yyyymmdd($date), $confirmed, $failed, $recovered);
    }
}

sub date2yyyymmdd($date) {
    my ($month, $day, $year) = $date.split('/');
    $year += 2000;
    my $yyyymmdd = '%i%02i%02i'.sprintf($year, $month, $day);

    return $yyyymmdd;
}

#| Generate web pages based on the current data from the database
multi sub MAIN('generate') {
    my %countries = get-countries();

    my %per-day = get-per-day-stats();
    my %totals = get-total-stats();
    my %daily-totals = get-daily-totals-stats();

    generate-world-stats(%countries, %per-day, %totals, %daily-totals);

    generate-countries-stats(%countries, %per-day, %totals, %daily-totals);
    generate-china-level-stats(%countries, %per-day, %totals, %daily-totals);

    for get-known-countries() -> $cc {
        generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals);
    }

    for %continents.keys -> $cont {
        generate-continent-stats($cont, %countries, %per-day, %totals, %daily-totals);
    }

    generate-continent-graph(%countries, %per-day, %totals, %daily-totals);

    generate-scattered-age(%countries, %per-day, %totals, %daily-totals);

    geo-sanity();
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

