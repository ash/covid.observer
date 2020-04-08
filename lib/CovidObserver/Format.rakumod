unit module CovidObserver::Format;

use DateTime::Format;

sub date2yyyymmdd($date) is export {
    my ($month, $day, $year) = $date.split('/');
    $year += 2000;
    my $yyyymmdd = '%i%02i%02i'.sprintf($year, $month, $day);

    return $yyyymmdd;
}

sub fmtdate($date) is export {
    my ($year, $month, $day) = $date.split('-');
    $day ~~ s/^0//;

    my $dt = DateTime.new(:$year, :$month, :$day);
    my $ending;
    given $day {
        when 1|21|31 {$ending = 'st'}
        when 2|22    {$ending = 'nd'}
        when 3|23    {$ending = 'rd'}
        default      {$ending = 'th'}
    }

    return strftime("%B {$day}<sup>{$ending}</sup>, %Y", $dt);
}

sub fmtnum($n is copy) is export {
    $n ~~ s/ (\d) (\d ** 9) $/$0,$1/;
    $n ~~ s/ (\d) (\d ** 6) $/$0,$1/;
    $n ~~ s/ (\d) (\d ** 3) $/$0,$1/;

    return $n;
}

sub pm($n) is export {
    my $fmt = fmtnum($n);

    my $str = do given $n {
        when * > 0 {return "+$fmt"}
        when * < 0 {return '&minus;' ~ fmtnum(-$n)}
        default    {return $fmt}
    }
}

sub smart-round($n) is export {
    return $n < 10 ?? sprintf('%.02g', $n) !! fmtnum($n.round());
}
