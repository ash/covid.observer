unit module CovidObserver::Excel;

use CovidObserver::HTML;

sub excel-table($path is copy, @per-capita) is export {
    $path.=lc;

    my $csv = q:to/HEADER/;
        "Date","Confirmed cases","Daily growth, %","Recovered cases","Fatal cases","Active cases","Recovery rate, %","Mortality rate, %","Affected population, %","1 confirmed per every","1 died per every","Confirmed per 1000","Died per 1000"
        HEADER

    for @per-capita -> %day {
        $csv ~= %day<date confirmed confirmed-rate recovered failed active recovered-rate failed-rate percent one-confirmed-per one-failed-per confirmed-per1000 failed-per1000>.join(',') ~ "\n";
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
