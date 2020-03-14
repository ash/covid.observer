#!/usr/bin/env raku

use HTTP::UserAgent;
use Locale::Codes::Country;
use DBIish;
use JSON::Tiny;

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

    for get-known-countries() -> $cc {
        generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals);
    }
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

sub get-known-countries() {
    my $sth = dbh.prepare('select distinct countries.cc, countries.country from totals join countries on countries.cc = totals.cc order by countries.country');
    $sth.execute();

    my @countries;
    for $sth.allrows() -> @row {
        @countries.push(@row[0]);
    }

    return @countries;    
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
    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);

    my $content = qq:to/HTML/;
        <h1>COVID-19 World Statistics</h1>
        <div id="block2">
            <h2>Affected World Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of infected people against the total 7.8 billion of the world population.</p>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <canvas id="Chart1"></canvas>
            <p>The whole pie reflects the total number of people infected by coronavirus in the whole world.</p>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                var myDoughnutChart1 = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
            <canvas id="Chart2"></canvas>
            <p>The height of a single bar is the total number of people suffered from Coronavirus. It includes three parts: those who could or could not recover and those who are currently in the active phase of the desease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                var myDoughnutChart2 = new Chart(ctx2, $chart2data);
            </script>
        </div>

        <div id="countries">
            <h2>Statistics per Country</h2>
            <div id="countries-list">
                $country-list
            </div>
        </div>

        HTML

    html_template('/', 'World statistics', $content);
}

sub generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals) {
    say "Generating $cc...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, $cc);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, $cc);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, $cc);

    my $country-list = country-list(%countries, $cc);

    my $country-name = %countries{$cc}[0]<country>;
    my $population = +%countries{$cc}[1]<population>;
    my $population-str = $population <= 1
        ?? sprintf('%i thousand', 1000 * $population.round)
        !! sprintf('%i million', $population.round);

    my $proper-country-name = $country-name;
    $proper-country-name = "the $country-name" if $cc ~~ /US|GB|NL|DO/;

    my $content = qq:to/HTML/;
        <h1>Coronavirus in {$proper-country-name}</h1>

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of infected people against the total $population-str of its population.</p>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <canvas id="Chart1"></canvas>
            <p>The whole pie reflects the total number of people infected by coronavirus in {$proper-country-name}.</p>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                var myDoughnutChart1 = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
            <canvas id="Chart2"></canvas>
            <p>The height of a single bar is the total number of people suffered from Coronavirus in {$proper-country-name}. It includes three parts: those who could or could not recover and those who are currently in the active phase of the desease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                var myDoughnutChart2 = new Chart(ctx2, $chart2data);
            </script>
        </div>

        <div id="countries">
            <h2>Statistics per Country</h2>
            <div id="countries-list">
                $country-list
            </div>
        </div>

        HTML

    html_template('/' ~ $cc.lc, "Coronavirus in {$proper-country-name}", $content);
}

sub country-list(%countries, $current?) {
    my $is_current = !$current ?? ' class="current"' !! '';
    my $html = qq{<p$is_current><a href="/">Whole world</a></p>};

    for get-known-countries() -> $cc {
        next unless %countries{$cc};

        my $path = $cc.lc;
        my $is_current = $current && $current eq $cc ??  ' class="current"' !! '';
        $html ~= qq{<p$is_current><a href="/$path">} ~ %countries{$cc}[0]<country> ~ '</a></p>';
    }

    return $html;
}

sub chart-pie(%countries, %per-day, %totals, %daily-totals, $cc?) {    
    my $confirmed = $cc ?? %totals{$cc}<confirmed> !! [+] %totals.values.map: *<confirmed>;
    my $failed    = $cc ?? %totals{$cc}<failed>    !! [+] %totals.values.map: *<failed>;
    my $recovered = $cc ?? %totals{$cc}<recovered> !! [+] %totals.values.map: *<recovered>;

    my $active = $confirmed - $failed - $recovered;

    my $active-percent = $confirmed ?? sprintf('%i%%', (100 * $active / $confirmed).round) !! '';
    my $failed-percent = $confirmed ?? sprintf('%i%%', (100 * $failed / $confirmed).round) !! '';
    my $recovered-percent = $confirmed ?? sprintf('%i%%', (100 * $recovered / $confirmed).round) !! '';
    my $labels1 = qq{"Recovered $recovered-percent", "Failed to recover $failed-percent", "Active cases $active-percent"};

    my %dataset =
        label => 'Recovery statistics',
        data => [$recovered, $failed, $active],
        backgroundColor => ['green', 'red', 'orange'];
    my $dataset1 = to-json(%dataset);

    # JSON::Tiny refuses to put nested hashes as a single hash.
    my $json = q:to/JSON/;
        {
            "type": "pie",
            "data": {
                "labels": [LABELS1],
                "datasets": [
                    DATASET1
                ]
            },
            "options": {
                "animation": false
            }
        }
        JSON

    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/LABELS1/$labels1/;

    return $json;
}

sub chart-daily(%countries, %per-day, %totals, %daily-totals, $cc?) {
    my @dates;
    my @recovered;
    my @failed;
    my @active;

    for %daily-totals.keys.sort(*[0]) -> $date {
        @dates.push($date);

        my %data = $cc ?? %per-day{$cc}{$date} !! %daily-totals{$date};        

        @failed.push(%data<failed>);
        @recovered.push(%data<recovered>);

        @active.push([-] %data<confirmed recovered failed>);
    }

    my $labels = to-json(@dates);

    my %dataset1 =
        label => 'Recovered',
        data => @recovered,
        backgroundColor => 'green';
    my $dataset1 = to-json(%dataset1);

    my %dataset2 =
        label => 'Failed to recover',
        data => @failed,
        backgroundColor => 'red';
    my $dataset2 = to-json(%dataset2);

    my %dataset3 =
        label => 'Active cases',
        data => @active,
        backgroundColor => 'orange';
    my $dataset3 = to-json(%dataset3);

    my $json = q:to/JSON/;
        {
            "type": "bar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET2,
                    DATASET3,
                    DATASET1
                ]
            },
            "responsive": true,
            "options": {
                "animation": false,
                "scales": {
                    "xAxes": [{
                        "stacked": true,
                    }],
                    "yAxes": [{
                        "stacked": true
                    }]
                }
            }
        }
        JSON

    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;
    $json ~~ s/DATASET3/$dataset3/;
    $json ~~ s/LABELS/$labels/;

    return $json;
}

multi sub number-percent(%countries, %per-day, %totals, %daily-totals) {
    my $confirmed = [+] %totals.values.map: *<confirmed>;

    my $percent = '%.2g'.sprintf(100 * $confirmed / 7_800_000_000);

    return $percent;
}

multi sub number-percent(%countries, %per-day, %totals, %daily-totals, $cc) {
    my $confirmed = %totals{$cc}<confirmed>;

    my $population = %countries{$cc}[1]<population>; # omg, should be fixed in sub get-countries
    return 0 unless $population;

    $population *= 1_000_000;
    my $percent = '%.2g'.sprintf(100 * $confirmed / $population);

    return '<&thinsp;0.0001&thinsp;' if $percent ~~ /e/;

    return $percent;
}

sub html_template($path, $title, $content) {
    my $style = q:to/CSS/;
        body, html {
            width: 100%;
            padding: 0;
            margin: 0;
            text-align: center;
            font-family: Helvetica, Arial, sans-serif;
            color: #333333;
        }
        #block2 {
            padding-top: 10%;
            background: #f5f5ea;
            padding-bottom: 10%;
            margin-bottom: 10%;
        }
        #block1 {
            margin-bottom: 10%;
        }
        #block3 {
            margin-bottom: 10%;    
            padding-left: 2%;
            padding-right: 2%;            
        }
        h1 {
            font-weight: normal;
            font-size: 400%;
            padding-top: 0.7em;
        }
        h2 {
            font-weight: normal;
            font-size: 300%;
        }
        #percent {
            font-size: 900%;
        }
        #countries {
            padding-bottom: 10%;
        }
        #countries-list {
            column-count: 4;
            text-align: left;
            padding-left: 3%;
            padding-right: 3%;            
        }
        #countries-list a {
            color: #333333;
            text-decoration: none;
        }
        #countries-list a:hover {
            color: #333333;
            text-decoration: underline;
        }
        #countries-list p.current {
            font-weight: bold;
        }
        #about {
            border-top: 1px solid lightgray;
        }
        CSS

    my $template = qq:to/HTML/;
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>$title | Coronavirus COVID-19 Observer</title>
            <script src="/Chart.min.js"></script>
            <style>
                $style
            </style>
        </head>
        <body>
            $content

            <div id="about">
                <p>Bases on <a href="https://github.com/CSSEGISandData/COVID-19">data</a> collected by the Johns Hopkins University Center for Systems Science and Engineering.</p>
                <p>Updated daily around midnight European time.</p>
                <p>Created by <a href="https://andrewshitov.com">Andrew Shitov</a>. Source code: <a href="https://github.com/ash/covid.observer">GitHub</a>.</p>
            </div>
        </body>
        </html>
        HTML    

    mkdir("www$path");
    my $filepath = "./www$path/index.html";
    given $filepath.IO.open(:w) {
        .say: $template
    }
}
