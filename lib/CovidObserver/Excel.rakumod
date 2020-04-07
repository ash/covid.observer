unit module CovidObserver::Excel;

use CovidObserver::HTML;

sub excel-table($path is copy, @per-capita) is export {
    $path.=lc;

    my $csv = q:to/HEADER/;
        "Date","Confirmed cases","Daily growth, %","Recovered cases","Fatal cases","Active cases","Recovery rate, %","Mortality rate, %","Affected population, %","1 confirmed per every","1 died per every","Confirmed per million","Died per million"
        HEADER

    for @per-capita -> %day {
        $csv ~= %day<date confirmed confirmed-rate recovered failed active recovered-rate failed-rate percent one-confirmed-per one-failed-per confirmed-per-million failed-per-million>.join(',') ~ "\n";
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
