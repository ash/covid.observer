#!/usr/bin/env raku

use HTTP::UserAgent;
use Locale::Codes::Country;
use Locale::US;
use DBIish;
use JSON::Tiny;

constant %covid-sources =
    confirmed => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Confirmed.csv',
    failed    => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Deaths.csv',
    recovered => 'https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_19-covid-Recovered.csv';

constant $world-population = 7_800_000_000;

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

    geo-sanity();
}

multi sub MAIN('sanity') {
    geo-sanity();
}

sub geo-sanity() {
    my $sth = dbh.prepare('select per_day.cc from per_day left join countries using (cc) where countries.cc is null group by 1');
    $sth.execute();

    for $sth.allrows() -> $cc {
        my $variant = '';
        $variant = codeToCountry(~$cc) if $cc.chars == 2;
        say "Missing country information $cc $variant";
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

        $country = 'Iran' if $country eq 'Iran (Islamic Republic of)';
        $country = 'South Korea' if $country eq 'Republic of Korea';
        $country = 'Czech Republic' if $country eq 'Czechia';
        $country = 'Venezuela' if $country eq 'Venezuela (Boliv. Rep. of)';
        $country = 'Moldova' if $country eq 'Republic of Moldova';
        $country = 'Bolivia' if $country eq 'Bolivia (Plurin. State of)';
        $country = 'Tanzania' if $country eq 'United Rep. of Tanzania';

        my $cc = countryToCode($country);
        next unless $cc;

        %countries{$cc} = $country;
        %population{$cc} = +$value;
    }

    # US population
    # https://www2.census.gov/programs-surveys/popest/tables/2010-2019/state/totals/nst-est2019-01.xlsx from
    # https://www.census.gov/data/datasets/time-series/demo/popest/2010s-state-total.html
    for 'us-population.csv'.IO.lines() -> $line {
        my ($state, $value) = split ',', $line;
        my $state-cc = 'US/' ~ state-to-code($state);

        %countries{$state-cc} = $state;
        %population{$state-cc} = +$value / 1_000_000;
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
        }
        else {
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

    for @lines -> $line is rw {
        $line ~~ s/'Korea, South'/South Korea/;
        $line ~~ s/Russia/Russian Federation/;
        $line ~~ s:g/'*'//;
        $line ~~ s/Czechia/Czech Republic/;

        my @data = $line.split(',');

        my $country = @data[1] || '';
        $country ~~ s:g/\"//; #"
        my $cc = countryToCode($country) || '';
        $cc = 'US' if $country eq 'US';

        next unless $cc;

        for @dates Z @data[4..*] -> ($date, $n) {
            %per-day{$cc}{$date} += $n;
            %daily-per-country{$date}{$cc} += $n;

            my $uptodate = %per-day{$cc}{$date};
            %total{$cc} = $uptodate if !%total{$cc} or $uptodate > %total{$cc};
        }

        if $cc eq 'US' {
            my $state = @data[0];

            if $state && $state !~~ /Princess/ {
                my $state-cc = 'US/' ~ state-to-code($state);

                for @dates Z @data[4..*] -> ($date, $n) {
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

sub get-countries() {
    my $sth = dbh.prepare('select cc, country, population from countries');
    $sth.execute();

    my %countries;
    for $sth.allrows(:array-of-hash) -> %row {
        my $country = %row<country>;
        $country = "US/$country" if %row<cc> ~~ /US'/'/;
        %countries{%row<cc>} = 
            country => $country,
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
    say 'Generating world data...';

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals);

    # my $chart4data = number-percent-graph(%countries, %per-day, %totals, %daily-totals);
        # <div id="block4">
        #     <h3>Affected population timeline</h3>
        #     <canvas id="Chart4"></canvas>
        #     <p>This is how the above-show number changes over time. The vertical axis’ unit is % of the total world population.</p>
        #     <script>
        #         var ctx4 = document.getElementById('Chart4').getContext('2d');
        #         var chart4 = new Chart(ctx4, $chart4data);
        #     </script>
        # </div>

    my $country-list = country-list(%countries);

    my $content = qq:to/HTML/;
        <h1>COVID-19 World Statistics</h1>

        <div id="block2">
            <h2>Affected World Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of confirmed infection cases against the total 7.8 billion of the world population.</p>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <canvas id="Chart1"></canvas>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in the whole world.</p>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                var chart1 = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
            <canvas id="Chart2"></canvas>
            <p>The height of a single bar is the total number of people suffered from Coronavirus confirmed to be infected in the world. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                var chart2 = new Chart(ctx2, $chart2data);
            </script>
        </div>

        $country-list

        HTML

    html-template('/', 'World statistics', $content);
}

sub generate-countries-stats(%countries, %per-day, %totals, %daily-totals) {
    say 'Generating countries data...';

    my %chart5data = countries-first-appeared(%countries, %per-day, %totals, %daily-totals);
    my $chart4data = countries-per-capita(%countries, %per-day, %totals, %daily-totals);
    my $countries-appeared = countries-appeared-this-day(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);

    my $percent = sprintf('%.1f', 100 * %chart5data<current-n> / %chart5data<total-countries>);

    my $content = qq:to/HTML/;
        <h1>Coronavirus in different countries</h1>

        <div id="block5">
            <h2>Number of Countires Affected</h2>
            <p>%chart5data<current-n> countires are affected, which is {$percent}&thinsp;\% from the total %chart5data<total-countries> countries.</p>
            <canvas style="height: 400px" id="Chart5"></canvas>
            <p>On this graph, you can see how many countries did have data about confirmed coronavirus invection for a given date over the last months.</p>
            <script>
                var ctx5 = document.getElementById('Chart5').getContext('2d');
                var chart5 = new Chart(ctx5, %chart5data<json>);
            </script>
        </div>

        <div id="block6">
            <h2>Countries Appeared This Day</h2>
            <p>This list gives you the overview of when the first confirmed case was reported in the given country. Or, you can see here, which countries entered the chart in the recent days. The number in parentheses is the number of confirmed cases in that country on that date.</p>
            $countries-appeared
        </div>

        <div id="block4">
            <h2>Top 30 Affected per Million</h2>
            <canvas style="height: 400px" id="Chart4"></canvas>
            <p>This graph shows the number of affected people per each million of the population. Countries with more than one million are shown only.</p>
            <script>
                var ctx4 = document.getElementById('Chart4').getContext('2d');
                var chart4 = new Chart(ctx4, $chart4data);
            </script>
        </div>

        $country-list

        HTML

    html-template('/countries', 'Coronavirus in different countries', $content);
}

sub generate-china-level-stats(%countries, %per-day, %totals, %daily-totals) {
    say 'Generating stats vs China...';

    my $chart6data = countries-vs-china(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);

    my $content = qq:to/HTML/;
        <h1>Countries vs China</h1>

        <script>
            var randomColorGenerator = function () \{
                return '#' + (Math.random().toString(16) + '0000000').slice(2, 8);
            \};
        </script>

        <div id="block6">
            <h2>Confirmed population timeline</h2>
            <p>On this graph, you see how the fraction (in %) of the confirmed infection cases changes over time in different countries or the US states.</p>
            <p>The almost-horizontal red line displays China. The number of confirmed infections in China almost stopped growing.</p>
            <p>Click on the bar in the legend to turn the line off and on.</p>
            <br/>
            <canvas style="height: 400px" id="Chart6"></canvas>
            <p>1. Note that only countries and US states with more than 1 million population are taken into account. The smaller countries such as <a href="/va">Vatican</a> or <a href="/sm">San Marino</a> would have shown too high nimbers due to their small population.</p>
            <p>2. The line for the country is drawn only if it reaches at least 80% of the corresponding maximum parameter in China.</p>
            <script>
                var ctx6 = document.getElementById('Chart6').getContext('2d');
                var chart6 = new Chart(ctx6, $chart6data);
            </script>
        </div>

        $country-list

        HTML

    html-template('/vs-china', 'Countries vs China', $content);
}

sub countries-vs-china(%countries, %per-day, %totals, %daily-totals) {
    my %date-cc;
    for %per-day.keys -> $cc {
        for %per-day{$cc}.keys -> $date {
            %date-cc{$date}{$cc} = %per-day{$cc}{$date}<confirmed>;
        }
    }

    my %max-cc;
    # my $max = 0;

    my %data;
    for %date-cc.keys.sort -> $date {
        for %date-cc{$date}.keys -> $cc {
            next unless %countries{$cc};
            my $confirmed = %date-cc{$date}{$cc} || 0;
            %data{$cc}{$date} = sprintf('%.6f', 100 * $confirmed / (1_000_000 * +%countries{$cc}[1]<population>));

            %max-cc{$cc} = %data{$cc}{$date};# if %max-cc{$cc} < %data{$cc}{$date};
            # $max = %max-cc{$cc} if $max < %max-cc{$cc};
        }
    }

    my @labels;
    my %dataset;

    for %date-cc.keys.sort -> $date {
        next if $date le '2020-02-20';
        @labels.push($date);

        for %date-cc{$date}.keys.sort -> $cc {
            next unless %max-cc{$cc};
            next if %countries{$cc}[1]<population> < 1;

            next if %max-cc{$cc} < 0.8 * %max-cc<CN>;

            %dataset{$cc} = [] unless %dataset{$cc};
            %dataset{$cc}.push(%data{$cc}{$date});
        }
    }

    my @ds;
    for %dataset.keys.sort -> $cc {
        my $color = $cc eq 'CN' ?? 'red' !! 'RANDOMCOLOR';
        my %ds =
            label => %countries{$cc}[0]<country>,
            data => %dataset{$cc},
            fill => False,
            borderColor => $color,
            lineTension => 0;
        push @ds, to-json(%ds);
    }

    my $json = q:to/JSON/;
        {
            "type": "line",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASETS
                ]
            },
            "options": {
                "animation": false,
            }
        }
        JSON

    my $datasets = @ds.join(",\n");
    my $labels = to-json(@labels);

    $json ~~ s/DATASETS/$datasets/;
    $json ~~ s/LABELS/$labels/;
    $json ~~ s:g/\"RANDOMCOLOR\"/randomColorGenerator()/; #"

    return $json;
}

sub generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals) {
    say "Generating $cc...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, $cc);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, $cc);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, $cc);

    # my $chart4data = number-percent-graph(%countries, %per-day, %totals, %daily-totals, $cc);
        # <div id="block4">
        #     <h3>Affected population timeline</h3>
        #     <canvas id="Chart4"></canvas>
        #     <p>This is how the above-show number changes over time. The vertical axis’ unit is % of the total world population in {$proper-country-name}.</p>
        #     <script>
        #         var ctx4 = document.getElementById('Chart4').getContext('2d');
        #         var chart4 = new Chart(ctx4, $chart4data);
        #     </script>
        # </div>

    my $country-list = country-list(%countries, $cc);

    my $country-name = %countries{$cc}[0]<country>;
    my $population = +%countries{$cc}[1]<population>;
    my $population-str = $population <= 1
        ?? sprintf('%i thousand', (1000 * $population).round)
        !! sprintf('%i million', $population.round);

    my $proper-country-name = $country-name;
    $proper-country-name = "the $country-name" if $cc ~~ /[US|GB|NL|DO|CZ]$/;

    my $content = qq:to/HTML/;
        <h1>Coronavirus in {$proper-country-name}</h1>

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of confirmed infection cases against the total $population-str of its population.</p>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <canvas id="Chart1"></canvas>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in {$proper-country-name}.</p>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                var chart1 = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
            <canvas id="Chart2"></canvas>
            <p>The height of a single bar is the total number of people suffered from Coronavirus in {$proper-country-name} and confirmed to be infected. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                var chart2 = new Chart(ctx2, $chart2data);
            </script>
        </div>

        $country-list

        HTML

    html-template('/' ~ $cc.lc, "Coronavirus in {$proper-country-name}", $content);
}

sub country-list(%countries, $current?) {
    my $is_current = !$current ?? ' class="current"' !! '';
    my $html = qq{<p$is_current><a href="/">Whole world</a></p>};

    my $us_html = '';
    for get-known-countries() -> $cc {
        next unless %countries{$cc};

        if $cc ~~ /US'/'/ {
            if $current && $current ~~ /US/ {
                my $path = $cc.lc;
                my $is_current = $current && $current eq $cc ??  ' class="current"' !! '';
                my $state = %countries{$cc}[0]<country>;
                $state ~~ s/US'/'//;
                $us_html ~= qq{<p$is_current><a href="/$path">} ~ $state ~ '</a></p>';
            }
        }
        else {
            my $path = $cc.lc;
            my $is_current = $current && $current eq $cc ??  ' class="current"' !! '';
            $html ~= qq{<p$is_current><a href="/$path">} ~ %countries{$cc}[0]<country> ~ '</a></p>';
        }
    }

    if $current && $current ~~ /US/ {
        $us_html = qq:to/USHTML/;
            <a name="states"></a>
            <h2>Coronavirus in the USA</h2>
            <p><a href="/us/#">Cumulative USA statistics</a></p>
            <div id="countries-list">
                $us_html
            </div>
        USHTML
    }

    return qq:to/HTML/;
        <div id="countries">
            $us_html
            <h2>Statistics per Country</h2>
            <p><a href="/">Whole world</a></p>
            <p><a href="/countries">More statistics on countries</a></p>
            <p><a href="/vs-china">Countries vs China</a></p>
            <div id="countries-list">
                $html
            </div>
        </div>
        HTML
}

sub countries-first-appeared(%countries, %per-day, %totals, %daily-totals) {
    my $sth = dbh.prepare('select confirmed, cc, date from per_day where confirmed != 0 and cc not like "%/%" order by date');
    $sth.execute();    

    my %data;
    for $sth.allrows(:array-of-hash) -> %row {
        %data{%row<date>}++;        
    }

    my @dates;
    my @n;
    my @percent;
    for %data.keys.sort -> $date {
        @dates.push($date);
        @n.push(%data{$date}); 
    }
    
    my $labels = to-json(@dates);

    my %dataset1 =
        label => 'The number of affected countries',
        data => @n,
        backgroundColor => 'lightblue',
        yAxisID => "axis1";
    my $dataset1 = to-json(%dataset1);

    my $json = q:to/JSON/;
        {
            "type": "bar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET1
                ]
            },
            "options": {
                "animation": false,
                scales: {
                    yAxes: [
                        {
                            type: "linear",
                            display: true,
                            position: "left",
                            id: "axis1",
                            ticks: {
                                min: 0,
                                max: 208,
                                stepSize: 10
                            },
                            scaleLabel: {
                                display: true,
                                labelString: "The number of affected countries"
                            }
                        },
                        {
                            type: "linear",
                            display: true,
                            position: "right",
                            id: "axis2",
                            gridLines: {
                                drawOnChartArea: false
                            },
                            ticks: {
                                min: 0,
                                max: 100,
                                stepSize: 10
                            },
                            scaleLabel: {
                                display: true,
                                labelString: "Part of the total number of countries, in %"
                            }
                        }
                    ]
                }
            }
        }
        JSON

    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/LABELS/$labels/;

    my $total-countries = +%countries.keys.grep(* !~~ /'/'/);
    my $current-n = @n[*-1];

    return 
        json => $json,
        total-countries => $total-countries,
        current-n => $current-n;
}

sub countries-appeared-this-day(%countries, %per-day, %totals, %daily-totals) {
    my $sth = dbh.prepare('select confirmed, cc, date from per_day where confirmed != 0 order by date');
    $sth.execute();

    my %cc;
    my %data;
    for $sth.allrows(:array-of-hash) -> %row {
        my $cc = %row<cc>;
        next if %cc{$cc};
        %cc{$cc} = 1; # "Bag" datatype should be used here

        %data{%row<date>}{$cc} = 1; # and here
    }

    my $html;    
    for %data.keys.sort.reverse -> $date {        
        $html ~= "<h4>{$date}</h4><p>";

        my @countries;
        for %data{$date}.keys.sort -> $cc {
            next unless %countries{$cc}; # TW is skipped here
            my $confirmed = %per-day{$cc}{$date}<confirmed>;
            @countries.push('<a href="/' ~ $cc.lc ~ '">' ~ %countries{$cc}[0]<country> ~ "</a> ($confirmed)");
        }

        $html ~= @countries.join(', ');
        $html ~= '</p>';
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

    my $percent = '%.2g'.sprintf(100 * $confirmed / $world-population);

    return $percent;
}

multi sub number-percent(%countries, %per-day, %totals, %daily-totals, $cc) {
    my $confirmed = %totals{$cc}<confirmed>;

    my $population = %countries{$cc}[1]<population>; # omg, should be fixed in sub get-countries
    return 0 unless $population;

    $population *= 1_000_000;
    my $percent = '%.2g'.sprintf(100 * $confirmed / $population);

    return '<&thinsp;0.001' if $percent ~~ /e/;

    return $percent;
}

# sub number-percent-graph(%countries, %per-day, %totals, %daily-totals, $cc?) {
#     my %data;

#     my @dates;
#     my @confirmed;
#     my @active;
#     my @failed;
#     my @recovered;

#     my $population = $cc ?? (1_000_000 * %countries{$cc}[1]<population>).round !! $world-population;

#     for %daily-totals.keys.sort -> $date {
#         @dates.push($date);

#         my %data = $cc ?? %per-day{$cc}{$date} !! %daily-totals{$date};

#         my $confirmed = 100 * %data<confirmed> / $population;
#         my $failed = 100 * %data<failed> / $population;
#         my $recovered = 100 * %data<recovered> / $population;

#         my $active = $confirmed - $failed - $recovered;

#         @confirmed.push($confirmed);
#         @failed.push($failed);
#         @recovered.push($recovered);
#         @active.push($active);
#     }

#     my $labels = to-json(@dates);

#     my %dataset1 =
#         label => 'Recovered',
#         data => @recovered,
#         fill => False,
#         borderColor => 'green';
#     my $dataset1 = to-json(%dataset1);

#     my %dataset2 =
#         label => 'Failed to recover',
#         data => @failed,
#         fill => False,
#         borderColor => 'red';
#     my $dataset2 = to-json(%dataset2);

#     my %dataset3 =
#         label => 'Active cases',
#         data => @active,
#         fill => False,
#         borderColor => 'orange';
#     my $dataset3 = to-json(%dataset3);

#     my %dataset4 =
#         label => 'Total confirmed',
#         data => @confirmed,
#         fill => False,
#         borderColor => 'lightblue';
#     my $dataset4 = to-json(%dataset4);

#     my $json = q:to/JSON/;
#         {
#             "type": "line",
#             "data": {
#                 "labels": LABELS,
#                 "datasets": [
#                     DATASET4,
#                     DATASET2,
#                     DATASET3,
#                     DATASET1
#                 ]
#             },
#             "options": {
#                 "animation": false,
#             }
#         }
#         JSON

#     $json ~~ s/DATASET1/$dataset1/;
#     $json ~~ s/DATASET2/$dataset2/;
#     $json ~~ s/DATASET3/$dataset3/;
#     $json ~~ s/DATASET4/$dataset4/;
#     $json ~~ s/LABELS/$labels/;

#     return $json;
# }

sub countries-per-capita(%countries, %per-day, %totals, %daily-totals) {
    my %per-mln;
    for get-known-countries() -> $cc {
        my $population-mln = %countries{$cc}[1]<population>;

        next if $population-mln < 1;
        
        %per-mln{$cc} = sprintf('%.2f', %totals{$cc}<confirmed> / $population-mln);
    }

    my @labels;
    my @recovered;
    my @failed;
    my @active;

    my $count = 0;
    for %per-mln.sort(+*.value).reverse -> $item {
        last if ++$count > 30;

        my $cc = $item.key;
        my $population-mln = %countries{$cc}[1]<population>;

        @labels.push(%countries{$cc}[0]<country>);

        my $per-capita-confirmed = $item.value;
        
        my $per-capita-failed = %totals{$cc}<failed> / $population-mln;
        $per-capita-failed = 0 if $per-capita-failed < 0;
        @failed.push('%.2f'.sprintf($per-capita-failed));

        my $per-capita-recovered = %totals{$cc}<recovered> / $population-mln;
        $per-capita-recovered = 0 if $per-capita-recovered < 0;
        @recovered.push('%.2f'.sprintf($per-capita-recovered));

        @active.push('%.2f'.sprintf(($per-capita-confirmed - $per-capita-failed - $per-capita-recovered)));
    }

    my $labels = to-json(@labels);

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
            "type": "horizontalBar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET2,
                    DATASET3,
                    DATASET1
                ]
            },
            "options": {
                "animation": false,
                "scales": {
                    "xAxes": [{
                        "stacked": true,
                    }],
                    "yAxes": [{
                        "stacked": true,
                        "ticks": {
                            "autoSkip": false
                        }
                    }],                   
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

sub html-template($path, $title, $content) {
    my $style = q:to/CSS/;
        body, html {
            width: 100%;
            padding: 0;
            margin: 0;
            text-align: center;
            font-family: 'Nanum Gothic', Helvetica, Arial, sans-serif;
            color: #333333;
            background: white;
        }
        #block2 {
            padding-top: 10%;
            background: #f5f5ea;
            padding-bottom: 10%;
        }
        #block4 {
            padding-top: 5%;
            background: #f5f5ea;
            padding-bottom: 10%;
            margin-bottom: 10%;
            padding-left: 2%;
            padding-right: 2%;
        }
        #block5 {
            padding-top: 5%;
            padding-bottom: 5%;
            margin-bottom: 5%;
            padding-left: 2%;
            padding-right: 2%;
        }
        #block6 {
            padding-bottom: 10%;
            margin-bottom: 5%;
            padding-left: 2%;
            padding-right: 2%;
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
        h3 {
            font-weight: normal;
            font-size: 200%;
        }
        h4 {
            font-weight: bold;
            padding-bottom: 0;
            margin-bottom: 0;
            font-size: 120%;
        }
        p {
            line-height: 140%;
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
        a {
            color: #1d7cf8;
            text-decoration: none;
        }
        a:hover {
            color: #1d7cf8;
            text-decoration: underline;
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

        @media screen and (max-width: 850px) {
            h1 {
                font-size: 300%;
            }
            #percent {
                font-size: 450%;
            }
            #countries-list {
                column-count: 2;
            }
            #block4 {
                display: none;
            }
        }

        CSS

    my $ga = q:to/GA/;
        <script async src="https://www.googletagmanager.com/gtag/js?id=UA-160707541-1"></script>
        <script>
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', 'UA-160707541-1');
        </script>
        GA

    my $template = qq:to/HTML/;
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>$title | Coronavirus COVID-19 Observer</title>

            $ga

            <script src="/Chart.min.js"></script>
            <link href="https://fonts.googleapis.com/css?family=Nanum+Gothic&display=swap" rel="stylesheet">
            <style>
                $style
            </style>
        </head>
        <body>
            <p>
                <a href="/">Home</a>
                |
                New:
                <a href="/countries">Affected countries</a>
                |
                <a href="/vs-china">Countries vs China</a>
                |
                <a href="/us#states">US states</a>
            </p>

            $content

            <div id="about">
                <p>Based on <a href="https://github.com/CSSEGISandData/COVID-19">data</a> collected by the Johns Hopkins University Center for Systems Science and Engineering.</p>
                <p>This website presents the very same data but from a less-panic perspective. Updated daily around 8 a.m. European time.</p>
                <p>Created by <a href="https://andrewshitov.com">Andrew Shitov</a>. Source code: <a href="https://github.com/ash/covid.observer">GitHub</a>. Powered by <a href="https://raku.org">Raku</a>.</p>
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
