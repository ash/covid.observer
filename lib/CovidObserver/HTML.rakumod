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

    my $anchor-prefix = $path ~~ / 'vs-' | countries | overview | 404 / ?? '/' !! '';

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
            <link rel="stylesheet" type="text/css" href="/main.css?v=15">
            <style>
                $style
            </style>

            <script>
                $script
            </script>
            <link rel="stylesheet" type="text/css" href="/likely.css">
            <script src="/likely.js" type="text/javascript"></script>
        </head>
        <body>
            <p>
                <a href="/">Home</a>
                |
                New:
                <a href="/per-million">Countries sorted per million affected</a>
                |
                <a href="https://andrewshitov.com/category/covid-19/">Tech blog</a>
            </p>
            <p>
                <a href="/overview">World overview</a>
                |
                <span class="desktop">
                    <a href="{$anchor-prefix}#table">Table data</a>
                    |
                </span>
                <a href="/vs-age">Cases vs life expectancy</a>
                |
                <a href="{$anchor-prefix}#raw">Raw numbers</a>
                |
                <a href="{$anchor-prefix}#new">New daily cases</a>
            </p>
            <p>
                <a href="/cn#regions">China provinces</a>
                |
                <a href="/-cn">World without China</a>
                |
                <a href="/cn/-hb">China without Hubei</a>
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
            <p>
                <a href="/#continents">Continents</a>
                |
                <a href="/continents">Spread over the continents</a>
            </p>

            <div class="likely" style="min-height: 50px">
                <div class="twitter">Tweet</div>
                <div class="facebook">Share</div>
                <div class="linkedin">Link</div>
                <div class="telegram">Send</div>
                <div class="whatsapp">Send</div>
            </div>

            $content

            <div id="about">
                <div class="likely" style="min-height: 50px">
                    <div class="twitter">Tweet</div>
                    <div class="facebook">Share</div>
                    <div class="linkedin">Link</div>
                    <div class="telegram">Send</div>
                    <div class="whatsapp">Send</div>
                </div>
                <p>Based on <a href="https://github.com/CSSEGISandData/COVID-19">data</a> collected by the Johns Hopkins University Center for Systems Science and Engineering.</p>
                <p>This website presents the very same data as the JHU’s <a href="https://gisanddata.maps.arcgis.com/apps/opsdashboard/index.html#/bda7594740fd40299423467b48e9ecf6">original dashboard</a> but from a less-panic perspective. Updated daily around 8 a.m. European time.</p>
                <p>Read the <a href="https://andrewshitov.com/category/covid-19/">Technology blog</a>. Look at the source code: <a href="https://github.com/ash/covid.observer">GitHub</a>. Powered by <a href="https://raku.org">Raku</a>.</p>
                <p>Created by <a href="https://andrewshitov.com">Andrew Shitov</a>. Twitter: <a href="https://twitter.com/andrewshitov">\@andrewshitov</a>. Contact <a href="mailto:andy@shitov.ru">by e-mail</a>.</p>
            </div>
        </body>
        </html>
        HTML    
#find-strings($template);
    mkdir("www$path");
    my $filepath = "./www$path/index.html";
    my $io = $filepath.IO;
    my $fh = $io.open(:w);
    $fh.say: $template;
    $fh.close;
}

sub country-list(%countries, :$cc?, :$cont?, :$exclude?) is export {
    my $is_current = !$cc && !$cont ?? ' class="current"' !! '';
    my $html = qq{<p$is_current><a href="/">Whole world</a></p>};

    sub current-country($cc-code) {
        if $cc {
            return True if $cc ~~ /US/ && $cc-code eq 'US';
            return True if $cc ~~ /CN/ && $cc-code eq 'CN';
            return $cc eq $cc-code;
        }
        if $cont {
            return %countries{$cc-code}<continent> eq $cont;
        }

        return False;
    }

    my $us_html = '';
    my $cn_html = '';
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
        elsif $cc-code ~~ /CN'/'/ {
            if $cc && $cc ~~ /CN/ {
                my $path = $cc-code.lc;

                my $is_current = current-country($cc-code) ??  ' class="current"' !! '';
                if $exclude && $exclude eq $cc-code {
                    $is_current = ' class="excluded"';
                }

                my $region = %countries{$cc-code}<country>;
                $region ~~ s/'China/'//;
                $cn_html ~= qq{<p$is_current><a href="/$path">} ~ $region ~ '</a></p>';
            }
        }
        else {
            my $path = $cc-code.lc;
            my $is_current = current-country($cc-code) ??  ' class="current"' !! '';
            if $exclude && $exclude eq $cc-code {
                $is_current = ' class="excluded"';
            }
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

    if $cc && $cc ~~ /CN/ {
        $cn_html = qq:to/CNHTML/;
            <a name="regions"></a>
            <h2>Coronavirus in China</h2>
            <p><a href="/cn/#">Cumulative China statistics</a></p>
            <p><a href="/cn/-hb">China excluding Hubei</a></p>
            <div id="countries-list">
                $cn_html
            </div>
        CNHTML
    }

    return qq:to/HTML/;
        <div id="countries">
            $us_html
            $cn_html
            <a name="countries"></a>
            <h2>Statistics per Country</h2>
            <p><a href="/">The whole world</a></p>
            <p><a href="/-cn">World excluding China</a></p>
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
    $day ~~ s/^0//;

    my $dt = DateTime.new(:$year, :$month, :$day);
    my $ending;
    given $day {
        when 1|21|31 {$ending = 'st'}
        when 2|22    {$ending = 'nd'}
        when 3       {$ending = 'rd'}
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

sub per-region($cc) is export {
    state %links =
        CN => {
            link => 'https://covid.observer/cn#regions',
            title => 'China provinces and regions'
        },
        US => {
            link => 'https://covid.observer/us#states',
            title => 'US states'
        },
        RU => {
            link => 'https://yandex.ru/web-maps/covid19',
            title => 'Official data: Карта распространения коронавируса в России'
        },
        NL => {
            link => 'https://www.rivm.nl/coronavirus-kaart-van-nederland-per-gemeente',
            title => 'Official data: Coronavirus kaart van Nederland per gemeente'
        },
        IN => {
            link => 'https://www.mohfw.gov.in/',
            title => 'Official Statistics by the Ministry of Health and Family Welfare'
        },
        CL => {
            link => 'https://www.gob.cl/coronavirus/casosconfirmados/',
            title => 'Official data: Casos confirmados de COVID-19 a nivel nacional'
        };

    return '' unless %links{$cc};

    my $target = %links{$cc}<link> ~~ /^ 'https://covid.observer/' / ?? '' !! ' target="_blank"';
    my $link = %links{$cc}<link>;
    my $title = %links{$cc}<title>;
    return qq{<p><a href="$link"$target>} ~ $title ~ '</a></p>';
}

sub daily-table($chartdata, $population) is export {
    my $html = q:to/HEADER/;
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Confirmed<br/>cases</th>
                    <th>Daily<br/>growth, %</th>
                    <th>Recovered<br/>cases</th>
                    <th>Failed<br/>cases</th>
                    <th>Active<br/>cases</th>
                    <th>Recovery<br/>rate, %</th>
                    <th>Mortality<br/>rate, %</th>
                    <th>Affected<br/>population, %</th>
                    <th>1 confirmed<br/>per every</th>
                    <th>1 failed<br/>per every</th>
                    </tr>
                </thead>
            <tbody>
        HEADER

    my $dates        = $chartdata<table><dates>;
    my $confirmed    = $chartdata<table><confirmed>;
    my $failed       = $chartdata<table><failed>;
    my $recovered    = $chartdata<table><recovered>;
    my $active       = $chartdata<table><active>;
    my $population-n = 1_000_000 * $population;

    for +$chartdata<table><dates> -1 ... 0 -> $index  {
        last unless $confirmed[$index];

        $html ~= qq:to/TR/;
            <tr>
                <td class="date">{
                    my $date = fmtdate($dates[$index]);
                    $date ~~ s/^(\w\w\w)\S+/$0/;
                    $date ~~ s/', '\d\d\d\d$//;
                    $date
                }</td>
                <td>{fmtnum($confirmed[$index])}</td>
                <td>{
                    if $index {
                        my $prev = $confirmed[$index - 1];
                        if $prev {
                            sprintf('%.1f&thinsp;%%', 100 * ($confirmed[$index] - $prev) / $prev)
                        }
                        else {'—'}
                    }
                    else {'—'}
                }</td>
                <td>{fmtnum($recovered[$index])}</td>
                <td>{fmtnum($failed[$index])}</td>
                <td>{fmtnum($active[$index])}</td>
                <td>{
                    if $confirmed[$index] {
                        sprintf('%0.1f&thinsp;%%', 100 * $recovered[$index] / $confirmed[$index])
                    }
                    else {''}
                }</td>
                <td>{
                    if $confirmed[$index] {
                        sprintf('%0.1f&thinsp;%%', 100 * $failed[$index] / $confirmed[$index])
                    }
                    else {''}
                }</td>
                <td>{
                    my $percent = '%.2g'.sprintf(100 * $confirmed[$index] / $population-n);
                    if $percent ~~ /e/ {
                        '&lt;&thinsp;0.001&thinsp;%'
                    }
                    else {
                        $percent ~ '&thinsp;%'
                    }
                }</td>
                <td>{
                    if $confirmed[$index] {
                        fmtnum(($population-n / $confirmed[$index]).round())
                    }
                    else {'—'}
                }</td>
                <td>{
                    if $failed[$index] {
                        fmtnum(($population-n / $failed[$index]).round())
                    }
                    else {'—'}
                }</td>
            </tr>
            TR
    }
    $html ~= '</tbody></table>';

    return $html;
}

sub find-strings($html) {
    my @matches = $html ~~ m:g/
        '<' (\w+) <-[ > ]>* '>'
            (<-[ < ]>+)
        '<'
    /;

    for @matches -> $match {
        my $tag = ~$match[0];
        next if $tag ~~ /script/;

        my $content = ~$match[1];

        my $copy = $content;
        $copy ~~ s:g/'&' <alpha>+ ';'/ /;
        next unless $copy ~~ /<alpha>/;

        my $trim = $content.trim;

        say $trim;
    }
}
