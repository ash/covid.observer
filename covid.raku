#!/usr/bin/env raku

use HTTP::UserAgent;
use IO::String;
use Locale::Codes::Country;
use DBIish;

constant %covid_sources = 
    confirmed => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Confirmed.csv',
    failed    => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Deaths.csv',
    recovered => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Recovered.csv';


multi sub MAIN('population') {
    my %population = parse_population();

    say "Updating database...";

    my $dbh = DBIish.connect('mysql', :host<localhost>, :user<covid>, :password<covid>, :database<covid>);
    $dbh.execute('delete from countries');

    for %population<countries>.kv -> $cc, $country {
        my $n = %population<population>{$cc};
        say "$cc, $country, $n";
        my $sth = $dbh.prepare('insert into countries (cc, country, population) values (?, ?, ?)');
        $sth.execute($cc, $country, $n);
    }
}

multi sub MAIN('fetch') {
    my %stats = fetch_covid_data(%covid_sources);
    
    say "Updating database...";

    my $dbh = DBIish.connect('mysql', :host<localhost>, :user<covid>, :password<covid>, :database<covid>);
    $dbh.execute('delete from per_day');

    my %confirmed = %stats<confirmed>;
    my %failed = %stats<failed>;
    my %recovered = %stats<recovered>;

    for %confirmed<per-day>.keys -> $cc {
        for %confirmed<per-day>{$cc}.kv -> $date, $confirmed {
            my ($month, $day, $year) = $date.split('/');
            $year += 2000;
            my $yyyymmdd = '%i%02i%02i'.sprintf($year, $month, $day);

            my $failed = %failed<per-day>{$cc}{$date};
            my $recovered = %recovered<per-day>{$cc}{$date};

            my $sth = $dbh.prepare('insert into per_day (cc, date, confirmed, failed, recovered) values (?, ?, ?, ?, ?)');
            $sth.execute($cc, $yyyymmdd, $confirmed, $failed, $recovered);
        }

        my $sth = $dbh.prepare('insert into totals (cc, confirmed, failed, recovered) values (?, ?, ?, ?)');
        $sth.execute($cc, %confirmed<total>{$cc}, %failed<total>{$cc}, %recovered<total>{$cc});
    }
}

multi sub MAIN('stats') {
    
}

sub parse_population() {
    my %population;
    my %countries;

    #constant $population_source = 'https://data.un.org/_Docs/SYB/CSV/SYB62_1_201907_Population,%20Surface%20Area%20and%20Density.csv';

    my $io = 'SYB62_1_201907_Population, Surface Area and Density.csv'.IO;
    for $io.lines -> $line {
        my ($n, $country, $year, $type, $value) = $line.split(',');
        next unless $type eq 'Population mid-year estimates (millions)';        

        $value = +$value;        

        my $cc = countryToCode($country);
        next unless $cc;

        %countries{$cc} = $country;
        %population{$cc} = $value;
    }

    return
        population => %population,
        countries => %countries;
}

sub fetch_covid_data(%sources) {
    my $ua = HTTP::UserAgent.new;
    $ua.timeout = 30;

    my %stats;

    for %sources.kv -> $type, $url {
        say "Getting '$type'...";

        my $response = $ua.get($url);

        if $response.is-success {
            say "Processing '$type'...";
            %stats{$type} = extract_covid_data($response.content);
        } else {
            die $response.status-line;
        }
    }

    return %stats;
}

sub extract_covid_data($data) {
    my @lines = $data.lines;

    my @headers = @lines.shift.split(',');
    my @dates = @headers[4..*];

    my %per-day;
    my %total;

    for @lines -> $line {
        my @data = $line.split(',');           
     
        my $cc = countryToCode(@data[1]) || '';
        next unless $cc;

        for @dates Z @data[4..*] -> ($date, $n) {            
            %per-day{$cc}{$date} += $n;
            my $uptodate = %per-day{$cc}{$date};            
            %total{$cc} = $uptodate if !%total{$cc} or $uptodate > %total{$cc};
        }
    }

    return 
        per-day => %per-day,
        total => %total;
}
