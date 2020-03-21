unit module CovidObserver::HTML;

use DateTime::Format;

use CovidObserver::Population;
use CovidObserver::Statistics;

sub html-template($path, $title, $content) is export {
    my $style = q:to/CSS/;
        CSS

    my $script = q:to/JS/;
        var chart = new Array();
        function log_scale(input, n) {
            chart[n].options.scales.yAxes[0].type = input.checked ? 'logarithmic' : 'linear';
            chart[n].update();
            input.blur();
        }
        JS

    my $ga = q:to/GA/;
        <script async src="https://www.googletagmanager.com/gtag/js?id=UA-160707541-1"></script>
        <script>
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', 'UA-160707541-1');
        </script>
        GA

    my $anchor-prefix = $path ~~ / 'vs-china' | countries | 404 / ?? '/' !! '';

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
            <link rel="stylesheet" type="text/css" href="/main.css?v=5">
            <style>
                $style
            </style>

            <script>
                $script
            </script>
        </head>
        <body>
            <p>
                <a href="/">Home</a>
                |
                New:
                <a href="{$anchor-prefix}#raw">Raw numbers</a>
                |
                <a href="{$anchor-prefix}#new">New daily cases</a>
                |
                <a href="/#continents">Continents</a>
                |
                <a href="/continents">Spread over continents</a>
            </p>
            <p>
                <a href="#countries">Countries</a>
                |
                <a href="/countries">Affected countries</a>
                |
                <a href="/vs-china">Countries vs China</a>
                |
                <a href="/us#states">US states</a>
                |
                <a href="{$anchor-prefix}#speed">Daily speed</a>
            </p>

            $content

            <div id="about">
                <p>Based on <a href="https://github.com/CSSEGISandData/COVID-19">data</a> collected by the Johns Hopkins University Center for Systems Science and Engineering.</p>
                <p>This website presents the very same data but from a less-panic perspective. Updated daily around 8 a.m. European time.</p>
                <p>Created by <a href="https://andrewshitov.com">Andrew Shitov</a>. Twitter: <a href="https://twitter.com/andrewshitov">\@andrewshitov</a>. Source code: <a href="https://github.com/ash/covid.observer">GitHub</a>. Powered by <a href="https://raku.org">Raku</a>.</p>
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

sub country-list(%countries, :$cc?, :$cont?) is export {
    my $is_current = !$cc && !$cont ?? ' class="current"' !! '';
    my $html = qq{<p$is_current><a href="/">Whole world</a></p>};

    sub current-country($cc-code) {
        if $cc {
            return True if $cc ~~ /US/ && $cc-code eq 'US';
            return $cc eq $cc-code;
        }
        if $cont {
            return %countries{$cc-code}<continent> eq $cont;
        }

        return False;
    }

    my $us_html = '';
    for get-known-countries() -> $cc-code {
        next unless %countries{$cc-code};

        if $cc-code ~~ /US'/'/ {
            if $cc && $cc ~~ /US/ {
                my $path = $cc-code.lc;

                my $is_current = current-country($cc-code) ??  ' class="current"' !! '';

                my $state = %countries{$cc-code}<country>;
                $state ~~ s/US'/'//;
                $us_html ~= qq{<p$is_current><a href="/$path">} ~ $state ~ '</a></p>';
            }
        }
        else {
            my $path = $cc-code.lc;
            my $is_current = current-country($cc-code) ??  ' class="current"' !! '';
            $html ~= qq{<p$is_current><a href="/$path">} ~ %countries{$cc-code}<country> ~ '</a></p>';
        }
    }

    if $cc && $cc ~~ /US/ {
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
            <a name="countries"></a>
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

sub continent-list($cont?) is export {
    my $is_current = !$cont ?? ' class="current"' !! '';
    my $html = qq{<p$is_current><a href="/">Whole world</a></p>};

    my $us_html = '';
    for %continents.keys.sort -> $cont-code {
        my $continent-name = %continents{$cont-code};
        my $continent-url = $continent-name.lc.subst(' ', '-');

        my $is_current = $cont && $cont-code eq $cont ??  ' class="current"' !! '';
        $html ~= qq{<p$is_current><a href="/$continent-url">} ~ $continent-name ~ '</a></p>';
    }

    return qq:to/HTML/;
        <div id="countries">
            <a name="continents"></a>
            <h2>Statistics per Continent</h2>
            <p><a href="/continents">Spread over the continents timeline</a></p>

            <div id="countries-list">
                $html
            </div>
        </div>
        HTML
}

sub fmtdate($date) is export {
    my ($year, $month, $day) = $date.split('-');

    my $dt = DateTime.new(:$year, :$month, :$day);
    my $ending;
    given $day {
        when 1 {$ending = 'st'}
        when 2 {$ending = 'nd'}
        when 3 {$ending = 'rd'}
        default {$ending = 'th'}
    }

    return strftime("%B {$day}<sup>th</sup>, %Y", $dt);
}

sub fmtnum($n is copy) is export {
    $n ~~ s/ (\d) (\d ** 6) $/$0,$1/;
    $n ~~ s/ (\d) (\d ** 3) $/$0,$1/;

    return $n;
}
