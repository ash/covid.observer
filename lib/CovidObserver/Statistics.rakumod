unit module CovidObserver::Statistics;

use JSON::Tiny;

use CovidObserver::DB;
use CovidObserver::Population;
use CovidObserver::Format;

sub geo-sanity() is export {
    my $sth = dbh.prepare('select per_day.cc from per_day left join countries using (cc) where countries.cc is null group by 1');
    $sth.execute();

    for $sth.allrows() -> $cc {
        my $variant = '';
        $variant = cc2country(~$cc) if $cc.chars == 2;
        say "Missing country information $cc $variant";
    }
}

sub get-countries() is export {
    my $sth = dbh.prepare('select cc, country, continent, population, life_expectancy, area from countries');
    $sth.execute();

    my %countries;
    for $sth.allrows(:array-of-hash) -> %row {
        my $country = %row<country>;
        $country = "US/$country" if %row<cc> ~~ /US'/'/;
        $country = "China/$country" if %row<cc> ~~ /'CN/'/;
        my %data =
            country => $country,
            population => %row<population>,
            continent => %row<continent>,
            age => %row<life_expectancy>,
            area => %row<area>;
        %countries{%row<cc>} = %data;
    }
    $sth.finish();

    return %countries;
}

sub get-known-countries() is export {
    my $sth = dbh.prepare('select distinct countries.cc, countries.country from totals join countries on countries.cc = totals.cc order by countries.country');
    $sth.execute();

    my @countries;
    for $sth.allrows() -> @row {
        @countries.push(@row[0]);
    }
    $sth.finish();

    return @countries;    
}

sub get-total-stats() is export {
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
    $sth.finish();

    return %stats;
}

sub get-per-day-stats() is export {
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
    $sth.finish();

    return %stats;
}

sub get-daily-totals-stats() is export {
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
    $sth.finish();

    return %stats;
}

sub get-mortality-data() is export {
    my $sth = dbh.prepare('select cc, year, month, n from mortality');
    $sth.execute();

    my %mortality;
    for $sth.allrows(:array-of-hash) -> %row {
        %mortality{%row<cc>}{%row<year>}{%row<month>} = %row<n>;
    }
    $sth.finish();

    return %mortality;
}

sub get-crude-data() is export {
    my $sth = dbh.prepare('select cc, year, deaths from crude');
    $sth.execute();

    my %crude;
    for $sth.allrows(:array-of-hash) -> %row {
        %crude{%row<cc>}{%row<year>} = %row<deaths>;
    }
    $sth.finish();

    return %crude;
}

sub countries-vs-china(%countries, %per-day, %totals, %daily-totals) is export {
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
            next if $cc ~~ /'/'/ && $cc ne 'CN/HB';
            next unless %countries{$cc};

            my $confirmed = %date-cc{$date}{$cc} || 0;
            %data{$cc}{$date} = sprintf('%.6f', 100 * $confirmed / (1_000_000 * +%countries{$cc}<population>));

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
            next if %countries{$cc}<population> < 1;

            next if %max-cc{$cc} < 0.85 * %max-cc<CN>;

            %dataset{$cc} = [] unless %dataset{$cc};
            %dataset{$cc}.push(%data{$cc}{$date});
        }
    }

    my @ds;
    for %dataset.sort: -*.value[*-1] -> $data {
        my $cc = $data.key;
        my $color = $cc eq 'CN' ?? 'red' !! 'RANDOMCOLOR';
        my %ds =
            label => %countries{$cc}<country>,
            data => $data.value,
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

sub countries-first-appeared(%countries, %per-day, %totals, %daily-totals) is export {
    my $sth = dbh.prepare('select confirmed, cc, date from per_day where confirmed != 0 and cc not like "%/%" order by date');
    $sth.execute();    

    my %data;
    for $sth.allrows(:array-of-hash) -> %row {
        %data{%row<date>}++;        
    }
    $sth.finish();

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
                                max: TOTALCOUNTRIES,
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

    $json ~~ s/TOTALCOUNTRIES/$total-countries/;

    return 
        json => $json,
        total-countries => $total-countries,
        current-n => $current-n;
}

sub countries-appeared-this-day(%countries, %per-day, %totals, %daily-totals) is export {
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
    $sth.finish();

    my $html;    
    for %data.keys.sort.reverse -> $date {
        $html ~= "<h4>{$date}</h4><p>";

        my @countries;
        for %data{$date}.keys.sort -> $cc {
            next unless %countries{$cc};
            my $confirmed = %per-day{$cc}{$date}<confirmed>;
            @countries.push('<a href="/' ~ $cc.lc ~ '">' ~ %countries{$cc}<country> ~ "</a> ($confirmed)");
        }

        $html ~= @countries.join(', ');
        $html ~= '</p>';
    }

    return $html;
}

sub chart-pie(%countries, %per-day, %totals, %daily-totals, :$cc?, :$cont?, :$exclude?) is export {
    my $confirmed = 0;
    my $failed = 0;
    my $recovered = 0;

    if $cc {
        $confirmed = %totals{$cc}<confirmed>;
        $failed    = %totals{$cc}<failed>;
        $recovered = %totals{$cc}<recovered>;

        if $exclude {
            $confirmed -= %totals{$exclude}<confirmed>;
            $failed    -= %totals{$exclude}<failed>;
            $recovered -= %totals{$exclude}<recovered>;
        }
    }
    elsif $cont {
        for %totals.keys -> $cc-code {
            next unless %countries{$cc-code} && %countries{$cc-code}<continent> eq $cont;

            $confirmed += %totals{$cc-code}<confirmed>;
            $failed    += %totals{$cc-code}<failed>;
            $recovered += %totals{$cc-code}<recovered>;
        }
    }
    else {
        for %totals.keys -> $cc-code {
            next if $cc-code ~~ /'/'/;
            next if $exclude && $exclude eq $cc-code;

            $confirmed += %totals{$cc-code}<confirmed>;
            $failed    += %totals{$cc-code}<failed>;
            $recovered += %totals{$cc-code}<recovered>;
        }
    }

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

sub chart-daily(%countries, %per-day, %totals, %daily-totals, :$cc?, :$cont?, :$exclude?) is export {
    my @dates;
    my @confirmed;
    my @recovered;
    my @failed;
    my @active;

    for %daily-totals.keys.sort(*[0]) -> $date {
        @dates.push($date);

        my %data =
            confirmed => 0,
            failed    => 0,
            recovered => 0;

        if $cc {
            %data = %per-day{$cc}{$date};
        }
        elsif $cont {
            for %totals.keys -> $cc-code {
                next if $cc-code ~~ /'/'/;
                next unless %countries{$cc-code} && %countries{$cc-code}<continent> eq $cont;

                %data<confirmed> += %per-day{$cc-code}{$date}<confirmed>;
                %data<failed>    += %per-day{$cc-code}{$date}<failed>;
                %data<recovered> += %per-day{$cc-code}{$date}<recovered>;
            }
        }
        else {
            for %totals.keys -> $cc-code {
                next if $cc-code ~~ /'/'/;

                %data<confirmed> += %per-day{$cc-code}{$date}<confirmed>;
                %data<failed>    += %per-day{$cc-code}{$date}<failed>;
                %data<recovered> += %per-day{$cc-code}{$date}<recovered>;
            }
        }

        if $exclude {
            %data<confirmed> -= %per-day{$exclude}{$date}<confirmed>;
            %data<failed>    -= %per-day{$exclude}{$date}<failed>;
            %data<recovered> -= %per-day{$exclude}{$date}<recovered>;
        }

        @confirmed.push(%data<confirmed>);
        @failed.push(%data<failed>);
        @recovered.push(%data<recovered>);

        my $active = [-] %data<confirmed recovered failed>;
        @active.push($active);
    }

    my $labels = to-json(@dates);

    # Current values
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
                    DATASET3,
                    DATASET2,
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
                            callback: function(value, index, values) {
                                value = value.toString();
                                if (value.length > 10) return '';
                                return value;
                            }
                        }
                    }]
                }
            }
        }
        JSON

    my $json-small = q:to/JSON/;
        {
            type: "bar",
            data: {
                labels: LABELS,
                datasets: [
                    DATASET3,
                    DATASET2,
                    DATASET1
                ]
            },
            options: smallOptions
        }
        JSON

    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;
    $json ~~ s/DATASET3/$dataset3/;
    $json ~~ s/LABELS/$labels/;

    $json-small ~~ s/DATASET1/$dataset1/;
    $json-small ~~ s/DATASET2/$dataset2/;
    $json-small ~~ s/DATASET3/$dataset3/;
    $json-small ~~ s/LABELS/$labels/;

    # Deltas
    my @delta-confirmed = @confirmed[1..*] >>->> @confirmed;
    my @delta-recovered = @recovered[1..*] >>->> @recovered;
    my @delta-failed    = @failed[1..*]    >>->> @failed;
    my @delta-active    = @active[1..*]    >>->> @active;

    @delta-confirmed.unshift(0);
    @delta-recovered.unshift(0);
    @delta-failed.unshift(0);
    @delta-active.unshift(0);

    my %delta-dataset0 =
        label => 'Confirmed',
        data => @delta-confirmed,
        backgroundColor => 'lightblue';
    my $delta-dataset0 = to-json(%delta-dataset0);

    my %delta-dataset1 =
        label => 'Recovered',
        data => @delta-recovered,
        backgroundColor => 'green';
    my $delta-dataset1 = to-json(%delta-dataset1);

    my %delta-dataset2 =
        label => 'Failed to recover',
        data => @delta-failed,
        backgroundColor => 'red';
    my $delta-dataset2 = to-json(%delta-dataset2);

    my %delta-dataset3 =
        label => 'Active cases',
        data => @delta-active,
        backgroundColor => 'orange';
    my $delta-dataset3 = to-json(%delta-dataset3);

    my $delta-json = q:to/JSON/;
        {
            "type": "bar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET2,
                    DATASET3,
                    DATASET1,
                    DATASET0
                ]
            },
            "options": {
                "animation": false,
            }
        }
        JSON

    my $delta-json-small = q:to/JSON/;
        {
            type: "bar",
            data: {
                labels: LABELS,
                datasets: [
                    DATASET2,
                    DATASET3,
                    DATASET1,
                    DATASET0
                ]
            },
            options: smallOptions
        }
        JSON

    $delta-json ~~ s/DATASET0/$delta-dataset0/;
    $delta-json ~~ s/DATASET1/$delta-dataset1/;
    $delta-json ~~ s/DATASET2/$delta-dataset2/;
    $delta-json ~~ s/DATASET3/$delta-dataset3/;
    $delta-json ~~ s/LABELS/$labels/;

    $delta-json-small ~~ s/DATASET0/$delta-dataset0/;
    $delta-json-small ~~ s/DATASET1/$delta-dataset1/;
    $delta-json-small ~~ s/DATASET2/$delta-dataset2/;
    $delta-json-small ~~ s/DATASET3/$delta-dataset3/;
    $delta-json-small ~~ s/LABELS/$labels/;

    my %return =
        date => @dates[*-1],

        json => $json,
        json-small => $json-small,

        confirmed => @confirmed[*-1],
        failed => @failed[*-1],
        recovered => @recovered[*-1],
        active => @active[*-1],        

        delta-json => $delta-json,
        delta-json-small => $delta-json-small,

        delta-confirmed => @delta-confirmed[*-1],
        delta-failed => @delta-failed[*-1],
        delta-recovered => @delta-recovered[*-1],
        delta-active => @delta-active[*-1],

        table => {
            dates     => @dates,
            confirmed => @confirmed,
            failed    => @failed,
            recovered => @recovered,
            active    => @active,
        };

    return %return;
}

multi sub number-percent(%countries, %per-day, %totals, %daily-totals, :$exclude?) is export {
    my $confirmed = 0;

    for %totals.keys -> $cc {
        next if $cc ~~ /'/'/;
        $confirmed += %totals{$cc}<confirmed>;
    }

    my $population = $world-population;

    if $exclude {
        $confirmed -= %totals{$exclude}<confirmed>;
        $population -= %countries{$exclude}<population>;
    }

    my $percent = '%.2g'.sprintf(100 * $confirmed / $population);

    return $percent;
}

multi sub number-percent(%countries, %per-day, %totals, %daily-totals, :$cc!, :$exclude?) is export {
    my $confirmed = %totals{$cc}<confirmed>;

    my $population = %countries{$cc}<population>;
    return 0 unless $population;

    if $exclude {
        $confirmed  -= %totals{$exclude}<confirmed>;
        $population -= %countries{$exclude}<population>;
    }

    $population *= 1_000_000;
    my $percent = '%.2g'.sprintf(100 * $confirmed / $population);

    return '<&thinsp;0.001' if $percent ~~ /e/;

    return $percent;
}

multi sub number-percent(%countries, %per-day, %totals, %daily-totals, :$cont!) is export {
    my $confirmed = 0;
    my $population = 0;

    for %countries.keys -> $cc {
        next unless %countries{$cc}<continent>;
        next unless %countries{$cc}<continent> eq $cont;

        $population += %countries{$cc}<population>;

        next unless %totals{$cc};
        $confirmed += %totals{$cc}<confirmed>;
    }

    my $percent = '%.2g'.sprintf(100 * $confirmed / (1_000_000 * $population));

    $percent = '<&thinsp;0.001' if $percent ~~ /e/;

    return
        percent => $percent,
        population => $population;
}

sub countries-per-capita(%countries, %per-day, %totals, %daily-totals, :$limit = 50, :$param = 'confirmed', :$mode = '', :$cc-only = '') is export {
    my %per-mln;
    for get-known-countries() -> $cc {
        if $cc-only {
            next unless $cc ~~ /^ $cc-only '/' /;
        }
        if !$cc-only && $mode ne 'combined' {
            next if $cc ~~ / '/' /;
        }

        my $population-mln = %countries{$cc}<population>;

        next if !$cc-only && $population-mln < 1;

        %per-mln{$cc} = sprintf('%.2f', %totals{$cc}{$param} / $population-mln);
    }

    my @labels;
    my @recovered;
    my @failed;
    my @active;

    my $count = 0;
    for %per-mln.sort(+*.value).reverse -> $item {
        last if ++$count > $limit;

        my $cc = $item.key;
        my $population-mln = %countries{$cc}<population>;

        @labels.push($count ~ '. ' ~ %countries{$cc}<country>);

        my $per-capita-confirmed = %totals{$cc}<confirmed> / $population-mln;
        $per-capita-confirmed = 0 if $per-capita-confirmed < 0;
        
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
        label => $cc-only !~~ /US/ ?? 'Active cases' !! 'Active or recovered cases',
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
                        "ticks": {
                            "min": 0
                        }
                    }],
                    "yAxes": [{
                        "stacked": true,
                        "ticks": {
                            "autoSkip": false
                        }
                    }],
                },
                "maintainAspectRatio": false
            }
        }
        JSON

    if $cc-only !~~ /US/ {
        $json ~~ s/DATASET1/$dataset1/;
    }
    else {
        $json ~~ s/DATASET1//;
    }

    $json ~~ s/DATASET2/$dataset2/;
    $json ~~ s/DATASET3/$dataset3/;
    $json ~~ s/LABELS/$labels/;
    
    return $json;
}

sub continent-joint-graph(%countries, %per-day, %totals, %daily-totals) is export {
    my @labels;
    my %datasets-active;
    my %datasets-confirmed;

    for %daily-totals.keys.sort -> $date {
        push @labels, $date;

        my %day-data-active;
        my %day-data-confirmed;

        for %per-day.keys -> $cc {
            next unless %countries{$cc} && %countries{$cc}<continent>;

            my $continent = %countries{$cc}<continent>;

            my $confirmed = %per-day{$cc}{$date}<confirmed> || 0;
            my $failed    = %per-day{$cc}{$date}<failed>    || 0;
            my $recovered = %per-day{$cc}{$date}<recovered> || 0;

            %day-data-active{$continent}    += $confirmed - $failed - $recovered;
            %day-data-confirmed{$continent} += $confirmed;
        }

        for %day-data-confirmed.keys -> $cont {
            %datasets-active{$cont} = [] unless %datasets-active{$cont};
            %datasets-active{$cont}.push(%day-data-active{$cont});

            %datasets-confirmed{$cont} = [] unless %datasets-confirmed{$cont};
            %datasets-confirmed{$cont}.push(%day-data-confirmed{$cont});
        }
    }

    my $labels = to-json(@labels);

    my %continent-color =
        AF => '#f5494d', AS => '#c7b53e', EU => '#477ccc',
        NA => '#d256d7', OC => '#40d8d3', SA => '#35ad38';

    my %json-active;
    my %json-confirmed;
    for %datasets-confirmed.keys -> $cont {
        my %ds-active =
            label => %continents{$cont},
            data => %datasets-active{$cont},
            backgroundColor => %continent-color{$cont};
        my %ds-confirmed =
            label => %continents{$cont},
            data => %datasets-confirmed{$cont},
            backgroundColor => %continent-color{$cont};

        %json-active{$cont}    = to-json(%ds-active);
        %json-confirmed{$cont} = to-json(%ds-confirmed);
    }

    my $json = q:to/JSON/;
        {
            "type": "bar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASETAF,
                    DATASETAS,
                    DATASETEU,
                    DATASETNA,
                    DATASETSA,
                    DATASETOC
                ]
            },
            "options": {
                "animation": false,
            }
        }
        JSON

    my $json-active = $json;
    my $json-confirmed = $json;

    $json-active ~~ s/LABELS/$labels/;
    $json-confirmed ~~ s/LABELS/$labels/;

    for %continents.keys -> $cont {
        $json-active ~~ s/DATASET$cont/%json-active{$cont}/;
        $json-confirmed ~~ s/DATASET$cont/%json-confirmed{$cont}/;
    }

    my %results =
        active    => $json-active,
        confirmed => $json-confirmed;

    return %results;
}

sub daily-speed(%countries, %per-day, %totals, %daily-totals, :$cc?, :$cont?, :$exclude?) is export {
    my @labels;
    my @confirmed;
    my @failed;
    my @recovered;
    my @active;

    my %data;

    if $cc {
        for %per-day{$cc}.keys -> $date {
            my $confirmed = %per-day{$cc}{$date}<confirmed> || 0;
            my $failed    = %per-day{$cc}{$date}<failed>    || 0;
            my $recovered = %per-day{$cc}{$date}<recovered> || 0;

            %data{$date} = {
                confirmed => $confirmed,
                failed => $failed,
                recovered => $recovered,
            };
        }

        if $exclude {
            for %per-day{$exclude}.keys -> $date {
                %data{$date}<confirmed> -= %per-day{$exclude}{$date}<confirmed>;
                %data{$date}<failed>    -= %per-day{$exclude}{$date}<failed>;
                %data{$date}<recovered> -= %per-day{$exclude}{$date}<recovered>;
            }
        }
    }
    elsif $cont {
        for %per-day.keys -> $cc-code {
            next if $cc-code ~~ /'/'/;
            next unless %countries{$cc-code} && %countries{$cc-code}<continent> eq $cont;

            for %per-day{$cc-code}.keys -> $date {
                %data{$date} = Hash.new unless %data{$date};

                %data{$date}<confirmed> += %per-day{$cc-code}{$date}<confirmed>;
                %data{$date}<failed>    += %per-day{$cc-code}{$date}<failed>;
                %data{$date}<recovered> += %per-day{$cc-code}{$date}<recovered>;
            }
        }
    }
    elsif $exclude {
        for %per-day.keys -> $cc-code {
            next if $cc-code ~~ /'/'/;
            next if $cc-code eq $exclude;

            for %per-day{$cc-code}.keys -> $date {
                %data{$date} = Hash.new unless %data{$date};

                %data{$date}<confirmed> += %per-day{$cc-code}{$date}<confirmed>;
                %data{$date}<failed>    += %per-day{$cc-code}{$date}<failed>;
                %data{$date}<recovered> += %per-day{$cc-code}{$date}<recovered>;
            }
        }
    }
    else {
        for %per-day.keys -> $cc-code {
            next if $cc-code ~~ /'/'/;

            for %per-day{$cc-code}.keys -> $date {
                %data{$date} = Hash.new unless %data{$date};

                %data{$date}<confirmed> += %per-day{$cc-code}{$date}<confirmed>;
                %data{$date}<failed>    += %per-day{$cc-code}{$date}<failed>;
                %data{$date}<recovered> += %per-day{$cc-code}{$date}<recovered>;
            }
        }
    }

    my @dates = %data.keys.sort;

    my $skip-days = $cc ?? 0 !! 0;
    my $skip-days-confirmed = $skip-days;
    my $skip-days-failed    = $skip-days;
    my $skip-days-recovered = $skip-days;
    my $skip-days-active    = $skip-days;

    my $avg-width = 1;

    for $avg-width ..^ @dates -> $index {
        @labels.push(@dates[$index]);

        my $day0 = @dates[$index];
        my $day1 = @dates[$index - 1];
        # my $day2 = @dates[$index - 2];
        # my $day3 = @dates[$index - 3];

        # Skip the first days in the graph to avoid a huge peak after first data appeared;
        $skip-days-confirmed-- if %data{$day0}<confirmed> && $skip-days-confirmed;
        $skip-days-failed--    if %data{$day0}<failed> && $skip-days-failed;
        $skip-days-recovered-- if %data{$day0}<recovered> && $skip-days-recovered;
        $skip-days-active--    if [-] %data{$day0}<confirmed failed recovered> && $skip-days-active;

        # my $r = (%data{$day0}<confirmed> + %data{$day1}<confirmed> + %data{$day2}<confirmed>) / 3;
        # my $l = (%data{$day1}<confirmed> + %data{$day2}<confirmed> + %data{$day3}<confirmed>) / 3;
        my $r = %data{$day0}<confirmed>;
        my $l = %data{$day1}<confirmed>;
        my $delta = $r - $l;
        my $speed = $l ?? sprintf('%.2f', 100 * $delta / $l) !! 0;
        @confirmed.push($skip-days-confirmed ?? 0 !! $speed);

        # $r = (%data{$day0}<failed> + %data{$day1}<failed> + %data{$day2}<failed>) / 3;
        # $l = (%data{$day1}<failed> + %data{$day2}<failed> + %data{$day3}<failed>) / 3;
        $r = %data{$day0}<failed>;
        $l = %data{$day1}<failed>;
        $delta = $r - $l;
        $speed = $l ?? sprintf('%.2f', 100 * $delta / $l) !! 0;
        @failed.push($skip-days-failed ?? 0 !! $speed);

        # $r = (%data{$day0}<recovered> + %data{$day1}<recovered> + %data{$day2}<recovered>) / 3;
        # $l = (%data{$day1}<recovered> + %data{$day2}<recovered> + %data{$day3}<recovered>) / 3;
        $r = %data{$day0}<recovered>;
        $l = %data{$day1}<recovered>;
        $delta = $r - $l;
        $speed = $l ?? sprintf('%.2f', 100 * $delta / $l) !! 0;
        @recovered.push($skip-days-recovered ?? 0 !! $speed);

        # $r = ([-] %data{$day0}<confirmed failed recovered> + [-] %data{$day1}<confirmed failed recovered> + [-] %data{$day2}<confirmed failed recovered>) / 3;
        # $l = ([-] %data{$day1}<confirmed failed recovered> + [-] %data{$day2}<confirmed failed recovered> + [-] %data{$day3}<confirmed failed recovered>) / 3;
        $r = [-] %data{$day0}<confirmed failed recovered>;
        $l = [-] %data{$day1}<confirmed failed recovered>;
        $delta = $r - $l;
        $speed = $l ?? sprintf('%.2f', 100 * $delta / $l) !! 0;
        @active.push($skip-days-active ?? 0 !! $speed);
    }

    my $trim-left = 3;

    my $labels = to-json(trim-data(@labels, $trim-left));

    my %dataset0 =
        label => 'Confirmed total',
        data => trim-data(moving-average(@confirmed, $avg-width), $trim-left),
        fill => False,
        lineTension => 0,
        borderColor => 'lightblue';
    my $dataset0 = to-json(%dataset0);

    # my %dataset1 =
    #     label => 'Recovered',
    #     data => trim-data(moving-average(@recovered, $avg-width), $trim-left),
    #     fill => False,
    #     lineTension => 0,
    #     borderColor => 'green';
    # my $dataset1 = to-json(%dataset1);

    # my %dataset2 =
    #     label => 'Failed to recover',
    #     data => trim-data(moving-average(@failed, $avg-width), $trim-left),
    #     fill => False,
    #     lineTension => 0,
    #     borderColor => 'red';
    # my $dataset2 = to-json(%dataset2);

    # my %dataset3 =
    #     label => 'Active cases',
    #     data => trim-data(moving-average(@active, $avg-width), $trim-left),
    #     fill => False,
    #     lineTension => 0,
    #     borderColor => 'orange';
    # my $dataset3 = to-json(%dataset3);

    my $json = q:to/JSON/;
        {
            "type": "line",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET0
                ]
            },
            "options": {
                "animation": false,
                "scales": {
                    "yAxes": [{
                        "type": "logarithmic",
                        "ticks": {
                            callback: function(value, index, values) {
                                value = value.toString();
                                if (value.length > 10) return '';
                                return value;
                            }
                        }
                    }],
                }
            }
        }
        JSON

    $json ~~ s/DATASET0/$dataset0/;
    # $json ~~ s/DATASET1/$dataset1/;
    # $json ~~ s/DATASET2/$dataset2/;
    # $json ~~ s/DATASET3/$dataset3/;
    $json ~~ s/LABELS/$labels/;

    return $json;
}

sub moving-average(@in, $width = 3) {
    return @in;

    # my @out;

    # @out.push(0) for ^$width;
    # for $width ..^ @in -> $index {
    #     my $avg = [+] @in[$index - $width .. $index];
    #     @out.push($avg / $width);
    # }

    # return @out;
}

sub trim-data(@data, $trim-length) {
    return @data[$trim-length .. *];
}

sub scattered-age-graph(%countries, %per-day, %totals, %daily-totals) is export {
    my @labels;
    my @dataset-confirmed;
    my @dataset-failed;

    my $max = 0;
    for %countries.keys -> $cc {
        my $confirmed = %totals{$cc}<confirmed>;
        next unless $confirmed;

        my $age = %countries{$cc}<age>;
        next unless $age;

        my $failed = %totals{$cc}<failed>;

        my $country = %countries{$cc}<country>;

        $confirmed /= 1_000_000 * %countries{$cc}<population> / 100;
        $failed    /= 1_000_000 * %countries{$cc}<population> / 100;

        $max = $confirmed if $max < $confirmed;

        @labels.push($country);

        my %point-confirmed =
            x => $age,
            y => $confirmed;
        push @dataset-confirmed, %point-confirmed;

        my %point-failed =
            x => $age,
            y => $failed;
        push @dataset-failed, %point-failed;
    }

    $max = sprintf('%.02f', $max);
    my $labels = to-json(@labels);

    my %dataset1 =
        label => 'Life expectancy vs confirmed cases',
        data => @dataset-confirmed,
        backgroundColor => '#3671e9';
    my $dataset1 = to-json(%dataset1);

    my %dataset2 =
        label => 'Life expectancy vs fatal cases',
        data => @dataset-failed,
        backgroundColor => 'red';
    my $dataset2 = to-json(%dataset2);

    my $json = q:to/JSON/;
        {
            "type": "scatter",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET1,
                    DATASET2
                ]
            },
            "options": {
                "animation": false,
                "tooltips": {
                    callbacks: {
                        label: function(tooltipItem, data) {
                            return data.labels[tooltipItem.index];
                        }
                    }
                },
                "scales": {
                    xAxes: [
                        {
                            type: "linear",
                            ticks: {
                                callback: function(value, index, values) {
                                    var n = value.toString();
                                    if (n.indexOf('e') != -1) return '';
                                    else return n + '%';
                                }
                            },
                            scaleLabel: {
                                display: true,
                                labelString: "Life expextancy, in years"
                            }
                        }
                    ],
                    yAxes: [
                        {
                            type: "logarithmic",
                            ticks: {
                                callback: function(value, index, values) {
                                    var n = value.toString();
                                    if (n.indexOf('e') != -1) return '';
                                    else return n + '%';
                                }
                            },
                            scaleLabel: {
                                display: true,
                                labelString: "The number of confirmed (blue) or fatal (red) cases, in %"
                            }
                        }
                    ]
                }
            }
        }
        JSON

    $json ~~ s/MAX/$max/;
    $json ~~ s/LABELS/$labels/;
    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;

    return $json;
}

sub scattered-density-graph(%countries, %per-day, %totals, %daily-totals) is export {
    my @labels;
    my @dataset-confirmed;
    my @dataset-failed;

    my $max = 0;
    for %countries.keys -> $cc {
        my $confirmed = %totals{$cc}<confirmed>;
        next unless $confirmed;

        next if %countries{$cc}<population> < 1;

        my $area = %countries{$cc}<area>;
        next unless $area;

        my $density = 1_000_000 * %countries{$cc}<population> / $area;

        my $failed = %totals{$cc}<failed>;

        my $country = %countries{$cc}<country>;

        # $confirmed /= 1_000_000 * %countries{$cc}<population> / 100;
        # $failed    /= 1_000_000 * %countries{$cc}<population> / 100;

        $max = $confirmed if $max < $confirmed;

        @labels.push($country);

        my %point-confirmed =
            x => $density,
            y => $confirmed;
        push @dataset-confirmed, %point-confirmed;

        my %point-failed =
            x => $density,
            y => $failed;
        push @dataset-failed, %point-failed;
    }

    $max = sprintf('%.02f', $max);
    my $labels = to-json(@labels);

    my %dataset1 =
        label => 'Population density vs confirmed cases',
        data => @dataset-confirmed,
        backgroundColor => '#3671e9';
    my $dataset1 = to-json(%dataset1);

    my %dataset2 =
        label => 'Population density vs fatal cases',
        data => @dataset-failed,
        backgroundColor => 'red';
    my $dataset2 = to-json(%dataset2);

    my $json = q:to/JSON/;
        {
            "type": "scatter",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET1,
                    DATASET2
                ]
            },
            "options": {
                "animation": false,
                "tooltips": {
                    callbacks: {
                        label: function(tooltipItem, data) {
                            return data.labels[tooltipItem.index];
                        }
                    }
                },
                "scales": {
                    xAxes: [
                        {
                            type: "logarithmic",
                            ticks: {
                                callback: function(value, index, values) {
                                    var n = value.toString();
                                    if (n.indexOf('e') != -1) return '';
                                    else return n;
                                },
                                minRotation: 35
                            },
                            scaleLabel: {
                                display: true,
                                labelString: "Population density, people / km2"
                            }
                        }
                    ],
                    yAxes: [
                        {
                            type: "logarithmic",
                            ticks: {
                                callback: function(value, index, values) {
                                    var n = value.toString();
                                    if (n.indexOf('e') != -1) return '';
                                    else return n;
                                },
                                minRotation: 35
                            },
                            scaleLabel: {
                                display: true,
                                labelString: "The number of confirmed (blue) or fatal (red) cases, in %"
                            }
                        }
                    ]
                }
            }
        }
        JSON

    $json ~~ s/MAX/$max/;
    $json ~~ s/LABELS/$labels/;
    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;

    return $json;
}

sub common-start(%countries, %per-day, %totals, %daily-totals) is export {
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
            next if $cc ~~ /'/'/ && $cc ne 'CN/HB';
            next unless %countries{$cc};

            my $confirmed = %date-cc{$date}{$cc} || 0;
            %data{$cc}{$date} = sprintf('%.6f', 100 * $confirmed / (1_000_000 * +%countries{$cc}<population>));

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
            next if %countries{$cc}<population> < 1;

            next if %max-cc{$cc} < 0.85 * %max-cc<CN>;

            %dataset{$cc} = [] unless %dataset{$cc};
            %dataset{$cc}.push(%data{$cc}{$date});
        }
    }

    my @ds;
    for %dataset.sort: -*.value[*-1] -> $data {
        my $cc = $data.key;
        my $color = $cc eq 'CN' ?? 'red' !! 'RANDOMCOLOR';
        my %ds =
            label => %countries{$cc}<country>,
            data => $data.value,
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

sub add-country-arrows(%countries, %per-day) is export {
    for %per-day.keys -> $cc {
        my @dates = %per-day{$cc}.keys.sort.reverse;

        my $score = 0;
        if @dates.elems > 7 {
            my $prev = %per-day{$cc}{@dates[0]}<confirmed> - %per-day{$cc}{@dates[1]}<confirmed>;
            for 1..7 -> $history {
                my $curr = %per-day{$cc}{@dates[$history]}<confirmed> - %per-day{$cc}{@dates[$history + 1]}<confirmed>;
                $score-- if $curr < $prev;
                $score++ if $curr > $prev;
                $prev = $curr;
            }
        }

        %countries{$cc}<trend> = $score;
    }
}

sub mortality-graph($cc, %per-day, %mortality, %crude, %countries, %totals) is export {
    # return Nil unless %mortality{$cc}:exists;

    constant @months = <January February March April May June July August September October November December>;

    my @years = %mortality{$cc}.keys.sort; # 5 last non-empty years in the db

    my $max = 0;
    # Some years are not complete in the data, so fill all the months with zeroes first.
    my %recent = @years.map: * => [0 xx 12];
    for @years -> $year is rw {
        for %mortality{$cc}{$year}.keys -> $month {
            my $value = %mortality{$cc}{$year}{$month};
            %recent{$year}[$month - 1] = $value;
            $max = $value if $value > $max;
        }
    }

    my $is-averaged = False;
    if !@years.elems && %crude{$cc} {
        my $population = 1_000_000 * %countries{$cc}<population>;
        @years = %crude{$cc}.keys.sort.reverse[0..5].reverse;
        for @years -> $year {
            my $deaths = %crude{$cc}{$year} * ($population / 1000);
            $deaths /= 12;
            %recent{$year} = $deaths.round xx 12;
            $max = $deaths if $deaths > $max;
        }
        $is-averaged = True;
    }


    my $max-current = 0;
    my @current = 0 xx 12;
    my @weekly = 0 xx 52;
    for %per-day{$cc}.keys.sort -> $date {
        my ($year, $month, $day) = $date.split('-');
        @current[$month - 1] = %per-day{$cc}{$date}<failed>;
        @current[$month - 1] -= [+] @current[0 ..^ $month - 1];

        my $value = @current[$month - 1];
        $max-current = $value if $value > $max-current;

        my $week-number = DateTime.new(year => $year, month => $month, day => $day).week-number;
        @weekly[$week-number - 1] = %per-day{$cc}{$date}<failed>;
    }

    return Nil unless $max-current;

    my $scale = $max < 20 * $max-current ?? 'linear' !! 'logarithmic';

    for 1 ..^ @weekly.elems -> $week-number {
        next unless @weekly[$week-number - 1];
        @weekly[$week-number - 1] -= [+] @weekly[0 ..^ $week-number - 1];
    }


    my $json-monthly = q:to/JSON/;
        {
            "type": "bar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASETS
                ]
            },
            "options": {
                "animation": false,
                "scales": {
                    "yAxes": [{
                        "type": "SCALE",
                        ticks: {
                            callback: function(value, index, values) {
                                value = value.toString();
                                if (value.length > 10) return '';
                                return value;
                            }
                        }
                    }]
                }
            }
        }
        JSON

    my @color = '#b7b7b7', '#c1c0c0', '#d3d3d3', '#e5e4e4', '#efeded';
    my @datasets;
    # for %recent.keys.sort Z @color.reverse -> ($year, $color) {
        for %recent.keys.sort -> $year {
        my %dataset =
            label => $is-averaged ?? "Averaged mortality in $year" !! "Mortality in $year",
            data => %recent{$year},
            backgroundColor => @color[2];

        @datasets.push(to-json(%dataset));
    }

    my %dataset =
        label => "Deaths from COVID-19",
        data => @current,
        backgroundColor => 'red';

    @datasets.push(to-json(%dataset));

    my $labels = to-json(@months);
    my $datasets = @datasets.join(",\n");

    $json-monthly ~~ s/DATASETS/$datasets/;
    $json-monthly ~~ s/LABELS/$labels/;
    $json-monthly ~~ s/SCALE/$scale/;

    my $json-weekly = q:to/JSON/;
        {
            "type": "bar",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET
                ]
            },
            "options": {
                "animation": false,
            }
        }
        JSON

    my $labels-weekly = to-json(1..52);
    my %dataset-weekly =
        label => "Deaths from COVID-19 by weeks of 2020",
        data => @weekly,
        backgroundColor => 'red';

    my $dataset-weekly = to-json(%dataset-weekly);

    $json-weekly ~~ s/DATASET/$dataset-weekly/;
    $json-weekly ~~ s/LABELS/$labels-weekly/;

    return {
        monthly     => $json-monthly,
        weekly      => $json-weekly,
        is-averaged => $is-averaged,
        scale       => $scale,
    };
}

sub crude-graph($cc, %per-day, %crude, %countries, %totals) is export {
    return Nil unless %crude{$cc}:exists;

    my @years = %crude{$cc}.keys.sort;
    my @data;
    my $max = 0;
    for @years -> $year {
        my $value = %crude{$cc}{$year};
        @data.push($value);
        $max = $value if $value > $max;
    }

    # Extend years till now
    my $last = @years[*-1];
    for $last ^.. 2020 -> $year {
        @years.push($year);
    }

    my $population = 1_000_000 * %countries{$cc}<population>;
    my $failed = %totals{$cc}<failed>;

    return Nil unless $failed;

    my $crude-covid = 1000 * $failed / $population;
    my @crude-covid = 0 xx @years.elems;
    @crude-covid[*-1] = sprintf('%3g', $crude-covid);

    my $scale = $max < 20 * @crude-covid[*-1] ?? 'linear' !! 'logarithmic';

    my $json = q:to/JSON/;
        {
            "type": "line",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET1,
                    DATASET2
                ]
            },
            "options": {
                "animation": false,
                "scales": {
                    "yAxes": [{
                        "type": "SCALE",
                        "ticks": {
                            callback: function(value, index, values) {
                                value = value.toString();
                                if (value.length > 10) return '';
                                return value;
                            }
                        }
                    }]
                }
            }
        }
        JSON

    my %dataset1 =
        label => "Crude deaths rates per 1000 population",
        data => @data,
        fill => False,
        borderColor => 'violet';

    my %dataset2 =
        label => "Crude rate COVID-19 per 1000",
        data => @crude-covid,
        fill => False,
        type => 'bar',
        backgroundColor => 'red';

    my $dataset1 = to-json(%dataset1);
    my $dataset2 = to-json(%dataset2);
    my $labels = to-json(@years);

    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;
    $json ~~ s/LABELS/$labels/;
    $json ~~ s/SCALE/$scale/;

    return {
        json => $json,
        scale => $scale,
    };
}

sub per-capita-data($chartdata, $population-n) is export {
    my $dates        = $chartdata<table><dates>;
    my $confirmed    = $chartdata<table><confirmed>;
    my $failed       = $chartdata<table><failed>;
    my $recovered    = $chartdata<table><recovered>;
    my $active       = $chartdata<table><active>;
    my $population-t = $population-n / 1_000;

    my @per-capita;
    for +$chartdata<table><dates> -1 ... 0 -> $index  {
        last unless $confirmed[$index];

        my $c = $confirmed[$index] // 0;
        my $f = $failed[$index] // 0;
        my $r = $recovered[$index] // 0;
        my $a = $active[$index] // 0;

        my $date-str = fmtdate($dates[$index]);
        $date-str ~~ s/^(\w\w\w)\S+/$0/;
        $date-str ~~ s/', '\d\d\d\d$//; #'

        my $confirmed-rate = '';
        my $confirmed-rate-str = '—';
        if $index {
            my $prev = $confirmed[$index - 1];
            if $prev {
                $confirmed-rate = 100 * ($c - $prev) / $prev;
                $confirmed-rate-str = sprintf('%.1f&thinsp;%%', $confirmed-rate);
            }
        }

        my $recovered-rate = '';
        my $recovered-rate-str = '';
        if $c {
            $recovered-rate = 100 * $r / $c;
            $recovered-rate-str = sprintf('%0.1f&thinsp;%%', $recovered-rate);
        }

        my $failed-rate = '';
        my $failed-rate-str = '';
        if $c {
            $failed-rate = 100 * $f / $c;
            $failed-rate-str = sprintf('%0.1f&thinsp;%%', $failed-rate);
        }

        my $percent = 100 * $c / $population-n;
        my $percent-str = '%.2g'.sprintf($percent);
        $percent-str = $percent < 0.001 ?? '&lt;&thinsp;0.001&thinsp;%' !! "$percent-str&thinsp;%";

        my $one-confirmed-per = '';
        my $one-confirmed-per-str = '';
        if $c {
            $one-confirmed-per = ($population-n / $c).round();
            $one-confirmed-per-str = fmtnum($one-confirmed-per);
        }

        my $one-failed-per = '';
        my $one-failed-per-str = '';
        if $f {
            $one-failed-per = ($population-n / $f).round();
            $one-failed-per-str = fmtnum($one-failed-per);
        }

        my $confirmed-per1000 = $c / $population-t;
        my $confirmed-per1000-str = smart-round($confirmed-per1000);

        my $failed-per1000 = $f / $population-t;
        my $failed-per1000-str = smart-round($failed-per1000);

        push @per-capita, {
            date => $dates[$index],
            :$date-str,

            confirmed => $c,
            confirmed-str => fmtnum($c),

            failed => $f,
            failed-str => fmtnum($f),

            recovered => $r,
            recovered-str => fmtnum($r),

            active => $a,
            active-str => fmtnum($a),

            :$confirmed-rate,
            :$confirmed-rate-str,
            :$recovered-rate,
            :$recovered-rate-str,
            :$failed-rate,
            :$failed-rate-str,

            :$percent,
            :$percent-str,

            :$one-confirmed-per,
            :$one-confirmed-per-str,
            :$one-failed-per,
            :$one-failed-per-str,

            :$confirmed-per1000,
            :$confirmed-per1000-str,
            :$failed-per1000,
            :$failed-per1000-str,
        };
    }

    return @per-capita;
}

sub per-capita-graph(@per-capita) is export {
    my @dates             = @per-capita.reverse.map: *<date>;
    my @confirmed-per1000 = @per-capita.reverse.map({smart-round($_<confirmed-per1000>)});
    my @failed-per1000    = @per-capita.reverse.map({smart-round($_<failed-per1000>)});

    my $json = q:to/JSON/;
        {
            "type": "line",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET1,
                    DATASET2
                ]
            },
            "options": {
                "animation": false
            }
        }
        JSON

    my %dataset1 =
        label => "Confirmed cases per 1000 of population",
        data => @confirmed-per1000,
        fill => False,
        borderColor => 'lightblue';

    my %dataset2 =
        label => "Fatal cases per 1000 population",
        data => @failed-per1000,
        fill => False,
        borderColor => 'red';

    my $dataset1 = to-json(%dataset1);
    my $dataset2 = to-json(%dataset2);
    my $labels = to-json(@dates);

    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;
    $json ~~ s/LABELS/$labels/;

    return $json;
}
