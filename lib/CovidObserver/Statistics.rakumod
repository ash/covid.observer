unit module CovidObserver::Statistics;

use JSON::Tiny;

use CovidObserver::DB;
use CovidObserver::Population;

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
    my $sth = dbh.prepare('select cc, country, continent, population, life_expectancy from countries');
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
            age => %row<life_expectancy>;
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

    $delta-json ~~ s/DATASET0/$delta-dataset0/;
    $delta-json ~~ s/DATASET1/$delta-dataset1/;
    $delta-json ~~ s/DATASET2/$delta-dataset2/;
    $delta-json ~~ s/DATASET3/$delta-dataset3/;
    $delta-json ~~ s/LABELS/$labels/;

    my %return =
        date => @dates[*-1],

        json => $json,
        confirmed => @confirmed[*-1],
        failed => @failed[*-1],
        recovered => @recovered[*-1],
        active => @active[*-1],

        delta-json => $delta-json,
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

sub countries-per-capita(%countries, %per-day, %totals, %daily-totals, :$limit = 50, :$param = 'confirmed') is export {
    my %per-mln;
    for get-known-countries() -> $cc {
        my $population-mln = %countries{$cc}<population>;

        next if $population-mln < 1;
        
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

        @labels.push(%countries{$cc}<country>);

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

sub continent-joint-graph(%countries, %per-day, %totals, %daily-totals) is export {
    my @labels;
    my %datasets;
    for %daily-totals.keys.sort -> $date {
        push @labels, $date;

        my %day-data;
        for %per-day.keys -> $cc {
            next unless %countries{$cc} && %countries{$cc}<continent>;

            my $continent = %countries{$cc}<continent>;

            my $confirmed = %per-day{$cc}{$date}<confirmed> || 0;
            my $failed = %per-day{$cc}{$date}<failed> || 0;
            my $recovered = %per-day{$cc}{$date}<recovered> || 0;

            %day-data{$continent} += $confirmed - $failed - $recovered;
        }

        for %day-data.keys -> $cont {
            %datasets{$cont} = [] unless %datasets{$cont};
            %datasets{$cont}.push(%day-data{$cont});
        }
    }

    my $labels = to-json(@labels);

    my %continent-color =
        AF => '#f5494d', AS => '#c7b53e', EU => '#477ccc',
        NA => '#d256d7', OC => '#40d8d3', SA => '#35ad38';

    my %json;
    for %datasets.keys -> $cont {
        my %ds =
            label => %continents{$cont},
            data => %datasets{$cont},
            backgroundColor => %continent-color{$cont};
        %json{$cont} = to-json(%ds);
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

    $json ~~ s/LABELS/$labels/;

    for %continents.keys -> $cont {
        $json ~~ s/DATASET$cont/%json{$cont}/;
    }

    return $json;
}

sub daily-speed(%countries, %per-day, %totals, %daily-totals, :$cc?, :$cont?, :$exclude?) is export {
    my @labels;
    my @confirmed;
    my @failed;
    my @recovered;
    my @active;

    my %data;

    if $cc {
        %data = %per-day{$cc};

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

    my %dataset1 =
        label => 'Recovered',
        data => trim-data(moving-average(@recovered, $avg-width), $trim-left),
        fill => False,
        lineTension => 0,
        borderColor => 'green';
    my $dataset1 = to-json(%dataset1);

    my %dataset2 =
        label => 'Failed to recover',
        data => trim-data(moving-average(@failed, $avg-width), $trim-left),
        fill => False,
        lineTension => 0,
        borderColor => 'red';
    my $dataset2 = to-json(%dataset2);

    my %dataset3 =
        label => 'Active cases',
        data => trim-data(moving-average(@active, $avg-width), $trim-left),
        fill => False,
        lineTension => 0,
        borderColor => 'orange';
    my $dataset3 = to-json(%dataset3);

    my $json = q:to/JSON/;
        {
            "type": "line",
            "data": {
                "labels": LABELS,
                "datasets": [
                    DATASET0,
                    DATASET2,
                    DATASET3,
                    DATASET1
                ]
            },
            "options": {
                "animation": false,
                "scales": {
                    "yAxes": [{
                        "type": "linear",
                    }],
                }
            }
        }
        JSON

    $json ~~ s/DATASET0/$dataset0/;
    $json ~~ s/DATASET1/$dataset1/;
    $json ~~ s/DATASET2/$dataset2/;
    $json ~~ s/DATASET3/$dataset3/;
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
        label => 'Life expectancy vs Confirmed cases',
        data => @dataset-confirmed,
        backgroundColor => '#3671e9';
    my $dataset1 = to-json(%dataset1);

    my %dataset2 =
        label => 'Life expectancy vs Failed cases',
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
                            var label = data.labels[tooltipItem.index];
                            return label;
                        }
                    }
                },
                "scales": {
                    xAxes: [
                        {
                            type: "linear",
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
                                labelString: "The number of confirmed (blue) or failed (red) cases, in %"
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
