unit module CovidObserver::Excel;

use CovidObserver::HTML;

sub excel-table($path is copy, $chartdata, $population) is export {
    $path.=lc;

    my $csv = q:to/HEADER/;
        "Date","Confirmed cases","Daily growth, %","Recovered cases","Fatal cases","Active cases","Recovery rate, %","Mortality rate, %","Affected population, %","1 confirmed per every","1 died per every"
        HEADER

    my $dates        = $chartdata<table><dates>;
    my $confirmed    = $chartdata<table><confirmed>;
    my $failed       = $chartdata<table><failed>;
    my $recovered    = $chartdata<table><recovered>;
    my $active       = $chartdata<table><active>;
    my $population-n = 1_000_000 * $population;

    for +$chartdata<table><dates> -1 ... 0 -> $index  {
        last unless $confirmed[$index];

        my $confirmed-rate = '';
        if $index {
            my $prev = $confirmed[$index - 1];
            if $prev {
                $confirmed-rate = 100 * ($confirmed[$index] - $prev) / $prev;
            }
        }

        my $recovered-rate = '';
        if $confirmed[$index] {
            $recovered-rate = 100 * $recovered[$index] / $confirmed[$index];
        }

        my $failed-rate = '';
        if $confirmed[$index] {
            $failed-rate = 100 * $failed[$index] / $confirmed[$index];
        }

        my $percent = 100 * $confirmed[$index] / $population-n;

        my $one-confirmed-per = '';
        if $confirmed[$index] {
            $one-confirmed-per = ($population-n / $confirmed[$index]).round();
        }

        my $one-failed-per = '';
        if $failed[$index] {
            $one-failed-per = ($population-n / $failed[$index]).round();
        }

        $csv ~= qq:to/ROW/;
            $dates[$index],$confirmed[$index],$confirmed-rate,$recovered[$index],$failed[$index],$active[$index],$recovered-rate,$failed-rate,$percent,$one-confirmed-per,$one-failed-per
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
