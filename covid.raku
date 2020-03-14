#!/usr/bin/env raku

use HTTP::UserAgent;
use Locale::Codes::Country;
use DBIish;

constant %covid_sources = 
    confirmed => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Confirmed.csv',
    failed    => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Deaths.csv',
    recovered => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Recovered.csv';

sub dbh() {
    state $dbh = DBIish.connect('mysql', :host<localhost>, :user<covid>, :password<covid>, :database<covid>);
    return $dbh;
}

multi sub MAIN('population') {
    my %population = parse-population();

    say "Updating database...";

    dbh.execute('delete from countries');

    for %population<countries>.kv -> $cc, $country {
        my $n = %population<population>{$cc};
        say "$cc, $country, $n";
        my $sth = dbh.prepare('insert into countries (cc, country, population) values (?, ?, ?)');
        $sth.execute($cc, $country, $n);
    }
}

multi sub MAIN('fetch') {
    my %stats = fetch-covid-data(%covid_sources);
    
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

multi sub MAIN('generate') {
    my %countries = get-countries();

    my %per-day = get-per-day-stats();
    my %totals = get-total-stats();
    my %daily-totals = get-daily-totals-stats();

    generate-world-stats(%countries, %per-day, %totals, %daily-totals);
}

sub parse-population() {
    my %population;
    my %countries;

    #constant $population_source = 'https://data.un.org/_Docs/SYB/CSV/SYB62_1_201907_Population,%20Surface%20Area%20and%20Density.csv';

    my $io = 'SYB62_1_201907_Population, Surface Area and Density.csv'.IO;
    for $io.lines -> $line {
        my ($n, $country, $year, $type, $value) = $line.split(',');
        next unless $type eq 'Population mid-year estimates (millions)';        

        my $cc = countryToCode($country);
        next unless $cc;

        %countries{$cc} = $country;
        %population{$cc} = +$value;
    }

    return
        population => %population,
        countries => %countries;
}

sub fetch-covid-data(%sources) {
    my $ua = HTTP::UserAgent.new;
    $ua.timeout = 30;

    my %stats;

    for %sources.kv -> $type, $url {
        say "Getting '$type'...";

        my $response = $ua.get($url);

        if $response.is-success {
            say "Processing '$type'...";
            %stats{$type} = extract-covid-data($response.content);
        } else {
            die $response.status-line;
        }
    }

    return %stats;
}

sub extract-covid-data($data) {
    my @lines = $data.lines;

    my @headers = @lines.shift.split(',');
    my @dates = @headers[4..*];

    my %per-day;
    my %total;
    my %daily-per-country;
    my %daily-total;

    for @lines -> $line {
        my @data = $line.split(',');           
     
        my $cc = countryToCode(@data[1]) || '';
        next unless $cc;

        for @dates Z @data[4..*] -> ($date, $n) {
            %per-day{$cc}{$date} += $n;
            %daily-per-country{$date}{$cc} += $n;

            my $uptodate = %per-day{$cc}{$date};
            %total{$cc} = $uptodate if !%total{$cc} or $uptodate > %total{$cc};
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

sub get-countries() {
    my $sth = dbh.prepare('select cc, country, population from countries');
    $sth.execute();

    my %countries;
    for $sth.allrows(:array-of-hash) -> %row {
        %countries{%row<cc>} = 
            country => %row<country>,
            population => %row<population>;        
    }

    return %countries;
}

sub get-total-stats() {
    my $sth = dbh.prepare('select cc, confirmed, failed, recovered from totals');
    $sth.execute();

    my %stats;
    for $sth.allrows(:array-of-hash) -> %row {
        my %data =
            confirmed => %row<confirmed>,
            failed => %row<failed>,
            recovered => %row<recovered>;
        %stats{%row<cc>} = %data;
    }

    return %stats;
}

sub get-per-day-stats() {
    my $sth = dbh.prepare('select cc, date, confirmed, failed, recovered from per_day');
    $sth.execute();

    my %stats;
    for $sth.allrows(:array-of-hash) -> %row {
        my %data =
            confirmed => %row<confirmed>,
            failed => %row<failed>,
            recovered => %row<recovered>;
        %stats{%row<cc>}{%row<date>} = %data;
    }

    return %stats;
}

sub get-daily-totals-stats() {
    my $sth = dbh.prepare('select date, confirmed, failed, recovered from daily_totals');
    $sth.execute();

    my %stats;
    for $sth.allrows(:array-of-hash) -> %row {
        my %data =
            confirmed => %row<confirmed>,
            failed => %row<failed>,
            recovered => %row<recovered>;
        %stats{%row<date>} = %data;
    }

    return %stats;
}

sub generate-world-stats(%countries, %per-day, %totals, %daily-totals) {
    my $total_confirmed = [+] %totals.values.map: *<confirmed>;
    my $total_failed = [+] %totals.values.map: *<failed>;
    my $total_recovered = [+] %totals.values.map: *<recovered>;

    say "$total_confirmed/$total_failed/$total_recovered";

    my $percent = '%.2g'.sprintf(100 * $total_confirmed / 7_800_000_000;);
    say $percent;

    my @dates;
    my @recovered;
    my @failed;
    my @active;

    for %daily-totals.keys.sort(*[0]) -> $date {
        @dates.push($date);

        my %data = %daily-totals{$date};
        @failed.push(%data<failed>);
        @recovered.push(%data<recovered>);
        @active.push(%data<confirmed> - %data<recovered> - %data<failed>);
    }

    say @dates;
    say @recovered;
    say @failed;
    say @active;
}
