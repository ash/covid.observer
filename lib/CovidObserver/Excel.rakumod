unit module CovidObserver::Excel;

use CovidObserver::HTML;

sub excel-table($path is copy, $chartdata, $population) is export {
    $path.=lc;

    my $csv = q:to/HEADER/;
        "Date","Confirmed cases","Daily growth, %","Recovered cases","Fatal cases","Active cases","Recovery rate, %","Mortality rate, %","Affected population, %","1 confirmed per every","1 died per every","Confirmed per million","Died per million"
        HEADER

    my $dates        = $chartdata<table><dates>;
    my $confirmed    = $chartdata<table><confirmed>;
    my $failed       = $chartdata<table><failed>;
    my $recovered    = $chartdata<table><recovered>;
    my $active       = $chartdata<table><active>;
    my $population-n = 1_000_000 * $population;

    for +$chartdata<table><dates> -1 ... 0 -> $index  {
        last unless $confirmed[$index];

        my $c = $confirmed[$index] // 0;
        my $f = $failed[$index] // 0;
        my $r = $recovered[$index] // 0;
        my $a = $active[$index] // 0;

        my $confirmed-rate = '';
        if $index {
            my $prev = $confirmed[$index - 1];
            if $prev {
                $confirmed-rate = 100 * ($c - $prev) / $prev;
            }
        }

        my $recovered-rate = '';
        if $c {
            $recovered-rate = 100 * $r / $c;
        }

        my $failed-rate = '';
        if $c {
            $failed-rate = 100 * $f / $c;
        }

        my $percent = 100 * $c / $population-n;

        my $one-confirmed-per = '';
        if $c {
            $one-confirmed-per = ($population-n / $c).round();
        }

        my $one-failed-per = '';
        if $f {
            $one-failed-per = ($population-n / $f).round();
        }

        my $confirmed-per-capita = $c / $population;
        my $failed-per-capita = $f / $population;

        $csv ~= qq:to/ROW/;
            $dates[$index],$c,$confirmed-rate,$r,$f,$a,$recovered-rate,$failed-rate,$percent,$one-confirmed-per,$one-failed-per,$confirmed-per-capita,$failed-per-capita
            ROW
    }

    mkdir "www/$path";
    my $filebase = "./www/$path/{$path}-covid.observer";
    my $csvfile = $filebase ~ '.csv';
    my $xlsfile = $filebase ~ '.xls';
    my $io = $csvfile.IO;
    my $fh = $io.open(:w);
    $fh.say: $csv;
    $fh.close;

    run '/usr/local/bin/ssconvert', $csvfile, $xlsfile, :err;
}
