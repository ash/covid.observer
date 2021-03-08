unit module CovidObserver::HTML;

use CovidObserver::Population;
use CovidObserver::Geo;
use CovidObserver::Statistics;
use CovidObserver::Format;
use CovidObserver::Translation;

sub html-template($path, $title, $content, $header = '') is export {
    my $style = q:to/CSS/;
        CSS

    my $script = q:to/JS/;
        var chart = new Array();
        function log_scale(input, n) {
            chart[n].options.scales.yAxes[0].type = input.checked ? 'logarithmic' : 'linear';
            chart[n].update();
            input.blur();
        }
        function log_scale_horizontal(input, n) {
            chart[n].options.scales.xAxes[0].type = input.checked ? 'logarithmic' : 'linear';
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

    my $anchor-prefix = $path.chars == 3 || $path ~~ / ^ '/' [europe|america|asia|oceania|africa|'-cn' | .. '/' .. ]/ ?? '' !! '/LNG';

    my $new-prefix = $content ~~ /block16/ && $content ~~ /block18/ ?? '' !! '/it';
    # my $new-block = qq:to/BLOCK/;
    #     <div class="new">
    #         <p class="center">New data on country-level pages. {'E.g., for Italy:' if $new-prefix eq '/it'}</p>
    #         <p class="center">
    #             <a href="$new-prefix#mortality">Mortality level</a>
    #             |
    #             <a href="$new-prefix#weekly">Weekly levels</a>
    #             |
    #             <a href="$new-prefix#crude">Crude death rates</a>
    #         </p>
    #         <p class="center">Compare the COVID-19 influence with the previous years.</p>
    #     </div>
    #     BLOCK
    # my $new-block = qq:to/BLOCK/;
    #     <div>
    #         <p class="center"><span style="padding: 4px 10px; border-radius: 16px; background: #1d7cf8; color: white;">New: <a style="color: white" href="/impact/LNG">Impact by different countries over time</a></span></p>
    #     </div>
    # BLOCK
    my $new-block = '';
    # $new-block = '' if $path ~~ /impact/;

    my $css-version = 'www/main.css'.IO.modified.round;
    my $timestamp = DateTime.now.truncated-to('hour');
    my $html = qq:to/HTML/;
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>$title | Coronavirus COVID-19 Observer</title>
            <link rel="icon" href="/favicon.ico?v=2" type="image/x-icon">

            $ga

            <script src="/Chart.min.js"></script>
            <link href="https://fonts.googleapis.com/css2?family=Nanum+Gothic:wght@400;700&display=swap" rel="stylesheet">
            <link rel="stylesheet" type="text/css" href="/main.css?v=$css-version">
            <style>
                $style
            </style>

            <script>
                $script
            </script>

            <script src="/countries.js?v=$timestamp" type="text/javascript"></script>
            <script src="/autocomplete.js?v=2" type="text/javascript"></script>

            <link rel="stylesheet" type="text/css" href="/likely.css">
            <script src="/likely.js" type="text/javascript"></script>

            $header
        </head>
        <body>

            <div class="menu" id="mainmenu">
                <ul>
                    <li><a href="/LNG">Home</a></li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn" style="cursor: normal">Statistics</a>
                        <div class="dropdown-content">
                            <a href="$anchor-prefix#recovery">Recovery pie</a>
                            <a href="$anchor-prefix#raw">Raw numbers</a>
                            <a href="$anchor-prefix#new">New daily cases</a>
                            <a href="$anchor-prefix#daily">Daily flow</a>
                            <a href="$anchor-prefix#speed">Daily speed</a>
                            <a href="$anchor-prefix#per-capita">Per capita values</a>
                            <a href="$anchor-prefix#table">Table data</a>
                            {
                                if $path.chars == 3 {
                                    q:to/LINKS/;
                                        <a href="#index7">Cumulative 7-day index</a>
                                        <a href="#index14">Cumulative 14-day index</a>
                                        <a href="#mortality">Mortality level</a>
                                        <a href="#weekly">Weekly levels</a>
                                        <a href="#crude">Crude deaths</a>
                                        LINKS
                                }
                            }
                            {
                                if $path eq '/ru' || $path eq '/ua' || $path ~~ /^ '/us' / {
                                    q:to/LINKS/;
                                        <a href="#tests">Tests performed</a>
                                    LINKS
                                }
                            }
                            <a href="/vs-age/LNG">Cases vs life expectancy</a>
                            <!--a href="/vs-density/LNG">Cases vs population density</a-->
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">World</a>
                        <div class="dropdown-content">
                            <a href="/map/LNG">World Map</a>
                            <a href="/LNG">World numbers</a>
                            <a href="/overview/LNG">Overview</a>
                            <a href="/-cn/LNG">World excluding China</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">Continents</a>
                        <div class="dropdown-content">
                            <a href="/africa/LNG">Africa</a>
                            <a href="/asia/LNG">Asia</a>
                            <a href="/europe/LNG">Europe</a>
                            <a href="/north-america/LNG">North America</a>
                            <a href="/south-america/LNG">South America</a>
                            <a href="/oceania/LNG">Oceania</a>
                            <a href="/continents/LNG">Spread over the continents</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">Countries</a>
                        <div class="dropdown-content">
                            <a href="$anchor-prefix#countries">List of countries</a>
                            <a href="/countries/LNG">Affected countries</a>
                            <a href="/compare/LNG">Compare countries</a>
                            <a href="/per-million/LNG">Sorted per million affected</a>
                            <a href="/vs-china/LNG">Countries vs China</a>
                            <a href="/pie/LNG">Distribution over the countries</a>
                            <a href="/impact/LNG">Impact timeline</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">China</a>
                        <div class="dropdown-content">
                            <a href="/cn/LNG">Cumulative data</a>
                            <a href="/cn/LNG#regions">China provinces</a>
                            <a href="/-cn/LNG">World excluding China</a>
                            <a href="/cn/-hb/LNG">China excluding Hubei</a>
                            <a href="/vs-china/LNG">Countries vs China</a>
                            <a href="/cn/compare/LNG">Compare provinces</a>
                            <a href="/per-million/cn/LNG">Provinces sorted per capita</a>
                            <a href="/pie/cn/LNG">Distribution over the regions</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">Russia</a>
                        <div class="dropdown-content">
                            <a href="/ru/LNG">Cumulative data</a>
                            <a href="/ru/LNG#regions">Regions</a>
                            <a href="/ru/compare/LNG">Compare regions</a>
                            <a href="/pie/ru/LNG">Distribution over the regions</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">US</a>
                        <div class="dropdown-content">
                            <a href="/us/LNG">Cumulative data</a>
                            <a href="/us/LNG#states">US states</a>
                            <a href="/us/compare/LNG">Compare the states</a>
                            <a href="/per-million/us/LNG">States sorted per capita</a>
                            <a href="/pie/us/LNG">Distribution over the states</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">About</a>
                        <div class="dropdown-content">
                            <a href="/news">What’s new</a>
                            <a href="/about">About the project</a>
                            <a href="/sources">Data sources</a>
                            <a href="https://andrewshitov.com/category/covid-19/" target="_blank">Tech blog</a>
                        </div>
                    </li>

                    <li class="dropdown">
                        <a href="javascript: void(0)" class="dropbtn">Language</a>
                        <div class="dropdown-content">
                            <a href="/">English</a>
                            <a href="/.ru/">Russian (beta)</a>
                        </div>
                    </li>

                    <li class="searchbox">
                        <div class="autocomplete">
                            <input id="SearchBox" type="text" name="myCountry" placeholder="Find a country or region">
                        </div>
                    </li>
                </ul>
            </div>

            <script>
                autocomplete(document.getElementById("SearchBox"), countries);
            </script>

            $new-block

            $content

            <div id="about">
                <div class="likely" style="min-height: 50px">
                    <div class="twitter">Tweet</div>
                    <div class="facebook">Share</div>
                    <div class="linkedin">Link</div>
                    <div class="telegram">Send</div>
                    <div class="whatsapp">Send</div>
                </div>
                <p>Based on [*a href="https://github.com/CSSEGISandData/COVID-19"*]data[*/a*] collected by the Johns Hopkins University Center for Systems Science and Engineering.</p>
                <p>This website presents the very same data as the JHU’s [*a href="https://gisanddata.maps.arcgis.com/apps/opsdashboard/index.html#/bda7594740fd40299423467b48e9ecf6"*]original dashboard[*/a*] but from a less-panic perspective. Updated daily around 8 a.m. Central European time.</p>
                <p>Read the [*a href="https://andrewshitov.com/category/covid-19/"*]Technology blog[*/a*]. Look at the source code: [*a href="https://github.com/ash/covid.observer"*]GitHub[*/a*]. Powered by [*a href="https://raku.org"*]Raku[*/a*].</p>
                <p>Created by [*a href="https://andrewshitov.com"*]Andrew Shitov[*/a*]. Twitter: [*a href="https://twitter.com/andrewshitov"*]\@andrewshitov[*/a*]. Contact [*a href="mailto:andy@shitov.ru"*]by e-mail[*/a*].</p>
            </div>
        </body>
        </html>
        HTML

    my $for-translation = $html;

    $html ~~ s:g/ '｢' | '｣' //;
    $html ~~ s:g/ '[*' ('/'? <alpha>+ .*? ) '*]' /<$0>/;

    $html ~~ s/ '<LANGUAGE lang="ru">' .*? '</LANGUAGE lang="ru">'//;
    $html ~~ s/'<LANGUAGE' .*? '>'//;
    $html ~~ s/'</LANGUAGE' .*? '>'//;

    $html ~~ s:g! '/LNG' !/!;

    mkdir("www$path");
    my $filepath = "./www$path/index.html";
    my $io = $filepath.IO;
    my $fh = $io.open(:w);
    $fh.say: $html;
    $fh.close;

    translate($path, $for-translation) unless $path ~~ /about|news|sources/;
}

sub arrow(%countries, $cc-code) is export {
    do given %countries{$cc-code}<trend> {
        when * >=  10 {' <span class="up">▲▲</span>'}
        when * >=  3  {' <span class="up">▲</span>'}
        when * >   0  {' <span class="up">△</span>'}
        when * <= -10 {' <span class="down">▼▼</span>'}
        when * <= -3  {' <span class="down">▼</span>'}
        when * <   0  {' <span class="down">▽</span>'}
        # when Order::Less {' <span class="down">▼</span>'}
        # when Order::More {' <span class="up">▲</span>'}
        default       {''};
    }
}

sub country-list(%countries, :$cc?, :$cont?, :$exclude?) is export {
    my $is_current = !$cc && !$cont ?? ' class="current"' !! '';

    sub current-country($cc-code) {
        if $cc {
            return True if $cc ~~ /US/ && $cc-code eq 'US';
            return True if $cc ~~ /CN/ && $cc-code eq 'CN';
            return True if $cc ~~ /RU/ && $cc-code eq 'RU';
            return $cc eq $cc-code;
        }
        if $cont {
            return %countries{$cc-code}<continent> eq $cont;
        }

        return False;
    }

    my $combined-html = '';
    for 'en', 'ru' -> $lang {
        my $html = '';
        my $regions-html = '';
        my $known-countries = get-known-countries($lang);

        for @$known-countries -> $cc-code {
            next unless %countries{$cc-code};
            next if $cc-code ~~ /^ [HK|MO] $/;

            if $cc-code ~~ /US'/'/ {
                if $cc && $cc ~~ /US/ {
                    my $path = $cc-code.lc;

                    my $is_current = current-country($cc-code) ??  ' class="current"' !! '';

                    my $state = %countries{$cc-code}<country>;
                    $state ~~ s/US'/'//;
                    $regions-html ~= qq{<p$is_current><a href="/$path/LNG">} ~ $state ~ '</a>' ~ arrow(%countries, $cc-code) ~ '</p>';
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
                    $regions-html ~= qq{<p$is_current><a href="/$path/LNG">} ~ $region ~ '</a>' ~ arrow(%countries, $cc-code) ~ '</p>';
                }
            }
            elsif $cc-code ~~ /RU'/'/ {
                if $cc && $cc ~~ /RU/ {
                    my $path = $cc-code.lc;

                    my $is_current = current-country($cc-code) ??  ' class="current"' !! '';
                    if $exclude && $exclude eq $cc-code {
                        $is_current = ' class="excluded"';
                    }

                    my $region = %countries{$cc-code}<country>;
                    $region ~~ s/'Russia/'//;
                    $regions-html ~= qq{<p$is_current><a href="/$path/LNG">} ~ $region ~ '</a>' ~ arrow(%countries, $cc-code) ~ '</p>';
                }
            }
            else {
                my $path = $cc-code.lc;
                my $is_current = current-country($cc-code) ??  ' class="current"' !! '';
                if $exclude && $exclude eq $cc-code {
                    $is_current = ' class="excluded"';
                }
                $html ~= qq{<p$is_current><a href="/$path/LNG">} ~ %countries{$cc-code}<country> ~ '</a>' ~ arrow(%countries, $cc-code) ~ '</p>';
            }
        }

        if $cc {
            if $cc ~~ /US/ {
                $regions-html = qq:to/USHTML/;
                    <a name="states"></a>
                    <h2>Coronavirus in the USA</h2>
                    <p class="center"><a href="/us/LNG#">Cumulative USA statistics</a> | <a href="/pie/us/LNG#">Distribution over the states</a> | <a href="/us/compare/LNG#">Compare the states</a></p>
                    <div class="countries-list">
                        $regions-html
                    </div>
                USHTML
            }
            elsif $cc ~~ /CN/ {
                $regions-html = qq:to/CNHTML/;
                    <a name="regions"></a>
                    <h2>Coronavirus in China</h2>
                    <p class="center"><a href="/cn/LNG#">Cumulative China statistics</a> | <a href="/pie/cn/LNG#">Distribution over the provinces</a> | <a href="/cn/compare/LNG#">Compare the provinces</a></p>
                    <p class="center"><a href="/cn/-hb/LNG">China excluding Hubei</a></p>
                    <div class="countries-list">
                        $regions-html
                    </div>
                CNHTML
            }
            elsif $cc ~~ /RU/ {
                $regions-html = qq:to/RUHTML/;
                    <a name="regions"></a>
                    <h2>Coronavirus in Russia</h2>
                    <p class="center"><a href="/ru/LNG#">Cumulative Russian statistics</a> | <a href="/pie/ru/LNG#">Distribution over the regions</a> | <a href="/ru/compare/LNG#">Compare the regions</a></p>
                    <div class="countries-list">
                        $regions-html
                    </div>
                RUHTML
            }
        }

        my $continent-list = continent-list($cont ?? $cont !! $cc ?? %countries{$cc}<continent> !! Any);

        $combined-html ~= qq:to/HTML/;
            <LANGUAGE lang="$lang">
                <a name="countries"></a>
                <div class="countries">
                    $regions-html

                    $continent-list

                    <a name="countries"></a>
                    <h2>Statistics per Country</h2>
                    <div class="countries-list">
                        $html
                    </div>
                    <p>The green and red arrows next to the country name display the trend of the new confirmed cases during the last week.</p>
                </div>
            </LANGUAGE lang="$lang">
            HTML
    }

    return $combined-html;
}

sub continent-list($cont?) is export {
    my $is_current = !$cont ?? ' class="current"' !! '';
    my $html = qq{<p$is_current><a href="/LNG">Whole world</a></p>};

    my $us_html = '';
    for %continents.keys.sort -> $cont-code {
        my $continent-name = %continents{$cont-code};
        my $continent-url = $continent-name.lc.subst(' ', '-');

        my $is_current = $cont && $cont-code eq $cont ??  ' class="current"' !! '';
        $html ~= qq{<p$is_current><a href="/$continent-url/LNG">} ~ $continent-name ~ '</a></p>';
    }

    return qq:to/HTML/;
        <a name="continents"></a>
        <h2>Statistics per Continent</h2>

        <div class="countries-list">
            $html
        </div>
        HTML
}

sub per-region(%CO, $cc) is export {
    state %links =
        CN => {
            link => '/cn/LNG#regions',
            title => 'China provinces and regions'
        },
        US => {
            link => '/us/LNG#states',
            title => 'US states'
        },
        RU => {
                link => '/ru/LNG#regions',
                title => 'Regions of the Russian Federation'
            },
            # {
            #     link => 'https://стопкоронавирус.рф',
            #     title => 'Official data: стопкоронавирус.рф'
            # }
        NL => {
            link => 'https://www.rivm.nl/coronavirus-covid-19/actueel',
            title => 'Official data: Actuele informatie over het nieuwe coronavirus'
        },
        IN => {
            link => 'https://www.mohfw.gov.in/',
            title => 'Official Statistics by the Ministry of Health and Family Welfare'
        },
        CL => {
            link => 'https://www.gob.cl/coronavirus/casosconfirmados/',
            title => 'Official data: Casos confirmados de COVID-19 a nivel nacional'
        },
        BE => {
            link => 'https://epistat.wiv-isp.be/Covid/',
            title => 'Division per communes (Belgian institute for health)'
        },
        FR => {
            link => 'https://dashboard.covid19.data.gouv.fr',
            title => 'L’information officielle sur la progression de l’épidémie en France'
        },
        JP => {
            link => 'https://covid19japan.com',
            title => '日本国内の新型コロナウイルス (COVID-19) 感染状況追跡 | Japan Coronavirus Tracker'
        }
        ;

    my $html = '';

    if %links{$cc} {
        my $link = %links{$cc}<link>;
        my $target = $link ~~ /^ '/' / ?? '' !! ' target="_blank"';

        $html ~= qq{<p class="center"><a href="$link"$target>} ~ %links{$cc}<title> ~ '</a></p>';
    }

    if $cc ~~ / [US|RU|CN] '/' / {
        my $country-name = %CO<countries>{$cc}<country>;
        $country-name = "the $country-name" if $cc ~~ /US|RU/;
        $html ~~ qq{<p class="center"><a href="/{$cc.lc}/LNG">Cumulative data in {$country-name}</a></p>};
    }

    return $html;
}

sub daily-table($path, @per-capita) is export {
    my $date = DateTime.now.yyyy-mm-dd;
    my $filebase = "/$path/{$path}-covid.observer".lc;
    my $html = qq[<p class="right">Download as <a href="{$filebase}.csv?$date">CSV</a> | <a href="{$filebase}.xls?$date">XLS</a></p>];
    $html ~= q:to/HEADER/;
        <table>
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Confirmed[*br/*]cases</th>
                    <th>Daily[*br/*]growth, %</th>
                    <th>Recovered[*br/*]cases</th>
                    <th>Fatal[*br/*]cases</th>
                    <th>Active[*br/*]cases</th>
                    <th>Recovery[*br/*]rate, %</th>
                    <th>Mortality[*br/*]rate, %</th>
                    <th>Affected[*br/*]population, %</th>
                    <th>Confirmed[*br/*]per 1000</th>
                    <th>Died[*br/*]per 1000</th>
                    </tr>
                </thead>
            <tbody>
        HEADER

    for @per-capita -> %day {
        $html ~= qq:to/TR/;
            <tr>
                <td class="date">{%day<date-str>}</td>
                <td>{%day<confirmed-str>}</td>
                <td>{%day<confirmed-rate-str>}</td>
                <td>{%day<recovered-str>}</td>
                <td>{%day<failed-str>}</td>
                <td>{%day<active-str>}</td>
                <td>{%day<recovered-rate-str>}</td>
                <td>{%day<failed-rate-str>}</td>
                <td>{%day<percent-str>}</td>
                <td>{%day<confirmed-per1000-str>}</td>
                <td>{%day<failed-per1000-str>}</td>
            </tr>
            TR
    }
    $html ~= '</tbody></table>';

    return $html;
}
