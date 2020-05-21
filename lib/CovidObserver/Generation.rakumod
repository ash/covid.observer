unit module CovidObserver::Generation;

use JSON::Tiny;

use CovidObserver::Population;
use CovidObserver::Geo;
use CovidObserver::Statistics;
use CovidObserver::HTML;
use CovidObserver::Excel;
use CovidObserver::Format;
use JSON::Tiny;

sub generate-world-stats(%CO, :$exclude?, :$skip-excel = False) is export {
    my $without-str = $exclude ?? " excluding %CO<countries>{$exclude}<country>" !! '';
    say "Generating world data{$without-str}...";

    my $chart1data = chart-pie(%CO, :$exclude);
    my $chart2data = chart-daily(%CO, :$exclude);
    my $chart3 = number-percent(%CO, :$exclude);
    my $chart7data = daily-speed(%CO, :$exclude);
    my @per-capita = per-capita-data($chart2data, $world-population);
    my $chart19data = per-capita-graph(@per-capita);

    my $table-path = 'world';
    $table-path ~= "-$exclude" if $exclude;
    $table-path.=subst('/', '.');

    my $daily-table = daily-table($table-path, @per-capita);
    excel-table($table-path, @per-capita) unless $skip-excel;

    my $content = qq:to/HTML/;
        <h1>COVID-19 World Statistics{$without-str}</h1>

        <div id="block2">
            <h2>Affected World Population{$without-str}</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p class="center">This is the part of confirmed infection cases against the total {
                if $exclude {
                    sprintf('｢%.1f｣', ($world-population / 1_000_000 - %CO<countries>{$exclude}<population>) / 1000)
                }
                else {
                    '7.8'
                }
            } billion of the world population{$without-str}.</p>
            <div class="affected">
                {
                    if $chart2data<confirmed> {
                        "Affected ｢{smart-round(@per-capita[0]<confirmed-per1000>)}｣ per 1000 people"
                    }
                    else {
                        'Nobody affected'
                    }
                }
            </div>
            <div class="failed">
                {
                    if $chart2data<failed> {
                        "Died ｢{smart-round(@per-capita[0]<failed-per1000-str>)}｣ per 1000 people"
                    }
                }
            </div>
        </div>

        <div id="block1">
            <a name="recovery"></a>
            <h2>Recovery Pie</h2>
            <p class="center">The whole pie reflects the total number of confirmed cases of people infected by coronavirus in the whole world{$without-str}.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block9">
            <a name="raw"></a>
            <h2>Raw Numbers on {fmtdate($chart2data<date>)}</h2>
            <p class="confirmed"><span>{fmtnum($chart2data<confirmed>)}</span><span class="updown"><sup>confirmed</sup><sub>{pm($chart2data<delta-confirmed>)}</sub></span></p>
            <p class="recovered"><span>{fmtnum($chart2data<recovered>)}</span><span class="updown"><sup>recovered</sup><sub>{pm($chart2data<delta-recovered>)}</sub></span></p>
            <p class="failed"><span>{fmtnum($chart2data<failed>)}</span><span class="updown"><sup>fatal</sup><sub>{pm($chart2data<delta-failed>)}</sub></span></p>
            <p class="active"><span>{fmtnum($chart2data<active>)}</span><span class="updown"><sup>active</sup><sub>{pm($chart2data<delta-active>)}</sub></span></p>
        </div>

        <div id="block3">
            <a name="daily"></a>
            <h2>Daily Flow</h2>
            <p>The height of a single bar is the total number of people suffered from Coronavirus confirmed to be infected in the World{$without-str}. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <canvas id="Chart2"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale2" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale2" onclick="log_scale(this, 2)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale2"> Logarithmic scale</label>
            </p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                chart[2] = new Chart(ctx2, $chart2data<json>);
            </script>
        </div>

        <div id="block10">
            <a name="new"></a>
            <h2>New Confirmed Cases</h2>
            <p>This graph shows the number of new cases by day. The lightblue bars are the number of the new total confirmed cases appeared that day.</p>
            <canvas id="Chart10"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale10" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale10" onclick="log_scale(this, 10)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale10"> Logarithmic scale</label>
            </p>
            <script>
                var ctx10 = document.getElementById('Chart10').getContext('2d');
                chart[10] = new Chart(ctx10, $chart2data<delta-json>);
            </script>
        </div>

        <div id="block7">
            <a name="speed"></a>
            <h2>Daily Speed</h2>
            <p>This graph shows the speed of growth (in %) over time. The only parameter here is the number of confirmed cases.</p>
            <canvas id="Chart7"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale7" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale7" checked="checked" onclick="log_scale(this, 7)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale7"> Logarithmic scale</label>
            </p>
            <script>
                var ctx7 = document.getElementById('Chart7').getContext('2d');
                chart[7] = new Chart(ctx7, $chart7data);
            </script>
            <p>Note. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreases, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that fewer cases registered today than yesterday.</p>
        </div>

        <div id="block19">
            <a name="per-capita"></a>
            <h2>Per capita values</h2>
            <p>Here, the number of confirmations and deaths <i>per 1000 of population</i> of the World is shown. These numbers is a better choice when comparing different countries than absolute numbers.</p>
            <canvas id="Chart19"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale19" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale19" onclick="log_scale(this, 19)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale19"> Logarithmic scale</label>
            </p>
            <script>
                var ctx19 = document.getElementById('Chart19').getContext('2d');
                chart[19] = new Chart(ctx19, $chart19data);
            </script>
        </div>

        <div id="block11">
            <a name="table"></a>
            <h1>Raw Daily Numbers</h1>
            $daily-table
        </div>

        {country-list(%CO<countries>, :$exclude)}

        HTML

    my $exclude-path = $exclude ?? '-' ~ $exclude.lc !! '';
    html-template("/$exclude-path", "World statistics$without-str", $content);
}

sub generate-country-stats($cc, %CO, :$exclude?, :%mortality?, :%crude?, :$skip-excel = False) is export {
    #countries, %per-day, %totals, %daily-totals
    my $without-str = $exclude ?? " excluding %CO<countries>{$exclude}<country>" !! '';
    say "Generating {$cc}{$without-str}...";

    my $chart1data = chart-pie(%CO, :$cc, :$exclude);
    my $chart2data = chart-daily(%CO, :$cc, :$exclude);
    my $chart3 = number-percent(%CO, :$cc, :$exclude);

    my $chart7data = daily-speed(%CO, :$cc, :$exclude);

    my $chart21data = daily-tests(%CO, :$cc);

    my $country-name = %CO<countries>{$cc}<country>;
    my $population = +%CO<countries>{$cc}<population>;

    if $exclude {
        $population -= %CO<countries>{$exclude}<population>;
    }

    my @per-capita = per-capita-data($chart2data, 1_000_000 * $population);
    my $chart19data = per-capita-graph(@per-capita);

    my %country-stats := {
        chart-daily => $chart2data,
    };

    my $table-path = $cc;
    $table-path ~= "-$exclude" if $exclude;
    $table-path.=subst('/', '.');

    my $daily-table = daily-table($table-path, @per-capita);
    excel-table($table-path, @per-capita) unless $skip-excel;

    my $population-str = $population <= 1
        ?? sprintf('｢%i｣ thousand', (1000 * $population).round)
        !! sprintf('｢%i｣ million', $population.round);

    my $proper-country-name = $country-name;
    my $title-name = $country-name;
    if $title-name ~~ / '/' / {
        $title-name = $title-name.split('/').reverse.join(', '); #'
    }

    if $cc ~~ /[US|GB|NL|DO|CZ|BS|GM|CD|CG]$/ || ($cc ~~ /^RU/ && $country-name ~~ /Republic/) {
        $proper-country-name = "the $country-name";
        $title-name = "the $title-name";
    }

    my $per-region-link = per-region(%CO, $cc);
    if $cc eq 'NL' {
        $per-region-link ~= q:to/LINKS/;
            <p class="center">Note: The numbers for [*a href="/aw/LNG"*]Aruba[*/a*], [*a href="/cw/LNG"*]Curaçao[*/a*], and [*a href="/sx/LNG"*]Sint Maarten[*/a*] are not included in the statistics for the Netherlands.</p>
            LINKS
    }

    my $mortality-block = '';
    if %mortality {
        my $chart16data = mortality-graph($cc, %CO, %mortality, %crude);
        if $chart16data {
            if $cc !~~ / '/' / {
                $mortality-block ~= qq:to/HTML/;
                    <div id="block16">
                        <a name="mortality"></a>
                        <h2>Mortality Level</h2>
                        <p>The gray bars on this graph display the absolute number of deaths that happen ｢in {$proper-country-name}｣ every month during the recent five years of [*a href="/sources/LNG"*]available data[*/a*]. The red bars are the absolute numbers of people died due to the COVID-19 infection.</p>
                        {'<p>Note that the vertical axis is drawn in logarithmic scale by default.</p>' if $chart16data<scale> eq 'logarithmic'}
                        {'<p>As there is no monthly data available ｢in ' ~ $proper-country-name ~ '｣, the gray bars are the average numbers obtained via the [*a href="#crude"*]crude[*/a*] death values known for this country for the recent five years of the available dataset.</p>' if $chart16data<is-averaged>}
                        <canvas id="Chart16"></canvas>
                        <p class="left">
                            <label class="toggle-switchy" for="logscale16" data-size="xs" data-style="rounded" data-color="blue">
                                <input type="checkbox" id="logscale16" {'checked="checked"' if $chart16data<scale> eq 'logarithmic'} onclick="log_scale(this, 16)">
                                <span class="toggle">
                                    <span class="switch"></span>
                                </span>
                            </label>
                            <label for="logscale16"> Logarithmic scale</label>
                        </p>
                        <script>
                            var ctx16 = document.getElementById('Chart16').getContext('2d');
                            chart[16] = new Chart(ctx16, $chart16data<monthly>);
                        </script>
                    </div>
                    HTML
            }

            $mortality-block ~= qq:to/HTML/;
                <div id="block16a">
                    <a name="weekly"></a>
                    <h2>Weekly Levels</h2>
                    <p>This graph draws the number of deaths ｢in {$proper-country-name}｣ connected to the COVID-19 infection aggregated by weeks of 2020.</p>
                    <canvas id="Chart17"></canvas>
                    <p class="left">
                        <label class="toggle-switchy" for="logscale17" data-size="xs" data-style="rounded" data-color="blue">
                            <input type="checkbox" id="logscale17" onclick="log_scale(this, 17)">
                            <span class="toggle">
                                <span class="switch"></span>
                            </span>
                        </label>
                        <label for="logscale17"> Logarithmic scale</label>
                    </p>
                    <script>
                        var ctx17 = document.getElementById('Chart17').getContext('2d');
                        chart[17] = new Chart(ctx17, $chart16data<weekly>);
                    </script>
                </div>
                HTML
        }
    }

    my $crude-block = '';
    if %crude {
        my $chart18data = crude-graph($cc, %CO, %crude);
        if $chart18data {
            $crude-block = qq:to/HTML/;
                <div id="block18">
                    <a name="crude"></a>
                    <h2>Crude rates</h2>
                    <p>Crude mortality rate is the number of people died in a country within a year per each 1000 of population.</p>
                    <p>Here, the crude rate ｢in {$proper-country-name}｣ is shown for the last 50 years. The red bar against 2020 is the number of people died due to COVID-19 per each 1000 people. Thus, you can directly compare the two parameters.</p>
                    {'<p>Note that the vertical axis is drawn in logarithmic scale by default.</p>' if $chart18data<scale> eq 'logarithmic'}
                    <canvas id="Chart18"></canvas>
                    <p class="left">
                        <label class="toggle-switchy" for="logscale18" data-size="xs" data-style="rounded" data-color="blue">
                            <input type="checkbox" id="logscale18" {'checked="checked"' if $chart18data<scale> eq 'logarithmic'} onclick="log_scale(this, 18)">
                            <span class="toggle">
                                <span class="switch"></span>
                            </span>
                        </label>
                        <label for="logscale18"> Logarithmic scale</label>
                    </p>
                    <script>
                        var ctx18 = document.getElementById('Chart18').getContext('2d');
                        chart[18] = new Chart(ctx18, $chart18data<json>);
                    </script>
                </div>
                HTML
        }
    }

    my $tests-fraction = 0;
    if %CO<tests>{$cc} {
        my @test-dates = %CO<tests>{$cc}.keys.sort;
        my $tests = %CO<tests>{$cc}{@test-dates[*-1]};
        $tests-fraction = smart-round(100 * $tests / (1_000_000 * $population));
    }

    my $content = qq:to/HTML/;
        <h1>Coronavirus ｢in {$title-name}{$without-str}｣</h1>
        $per-region-link

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p class="center">This is the part of confirmed infection cases against the total $population-str of its population.</p>

            {qq{<p class="center"><b>｢$tests-fraction&thinsp;%｣ of the whole population tested</b></p>} if $tests-fraction}

            <div class="affected">
                {
                    if $chart2data<confirmed> {
                        "Affected ｢{smart-round(@per-capita[0]<confirmed-per1000-str>)}｣ per 1000 people"
                    }
                    else {
                        'Nobody affected'
                    }
                }
            </div>
            <div class="failed">
                {
                    if $chart2data<failed> {
                        "Died ｢{smart-round(@per-capita[0]<failed-per1000-str>)}｣ per 1000 people"
                    }
                }
            </div>
        </div>

        <div id="block1">
            <a name="recovery"></a>
            <h2>Recovery Pie</h2>
            <p class="center">The whole pie reflects the total number of confirmed cases of people infected by coronavirus ｢in {$proper-country-name}{$without-str}｣.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block9">
            <a name="raw"></a>
            <h2>Raw Numbers on {fmtdate($chart2data<date>)}</h2>
            <p class="confirmed"><span>｢{fmtnum($chart2data<confirmed>)}｣</span><span class="updown"><sup>confirmed</sup><sub>｢{pm($chart2data<delta-confirmed>)}｣</sub></span></p>
            {
                if $chart2data<recovered> {
                    qq[<p class="recovered"><span>｢{fmtnum($chart2data<recovered>)}｣</span><span class="updown"><sup>recovered</sup><sub>｢{pm($chart2data<delta-recovered>)}｣</sub></span></p>]
                }
            }
            <p class="failed"><span>｢{fmtnum($chart2data<failed>)}｣</span><span class="updown"><sup>fatal</sup><sub>｢{pm($chart2data<delta-failed>)}｣</sub></span></p>
            <p class="active"><span>｢{fmtnum($chart2data<active>)}｣</span><span class="updown"><sup>active</sup><sub>｢{pm($chart2data<delta-active>)}｣</sub></span></p>
        </div>

        <div id="block3">
            <a name="daily"></a>
            <h2>Daily Flow</h2>
            <p>The height of a single bar is the total number of people suffered from Coronavirus ｢in {$proper-country-name}{$without-str}｣ and confirmed to be infected. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <canvas id="Chart2"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale2" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale2" onclick="log_scale(this, 2)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale2"> Logarithmic scale</label>
            </p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                chart[2] = new Chart(ctx2, $chart2data<json>);
            </script>
        </div>

        <div id="block10">
            <a name="new"></a>
            <h2>New Confirmed Cases</h2>
            <p>This graph shows the number of new cases by day. The lightblue bars are the number of the new total confirmed cases appeared that day.</p>
            <canvas id="Chart10"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale10" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale10" onclick="log_scale(this, 10)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale10"> Logarithmic scale</label>
            </p>
            <p></p>
            <script>
                var ctx10 = document.getElementById('Chart10').getContext('2d');
                chart[10] = new Chart(ctx10, $chart2data<delta-json>);
            </script>
        </div>

        <div id="block7">
            <a name="speed"></a>
            <h2>Daily Speed</h2>
            <p>This graph shows the speed of growth (in %) over time ｢in {$proper-country-name}{$without-str}｣. The only parameter here is the number of confirmed cases.</p>
            <canvas id="Chart7"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale7" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale7" checked="checked" onclick="log_scale(this, 7)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale7"> Logarithmic scale</label>
            </p>
            <script>
                var ctx7 = document.getElementById('Chart7').getContext('2d');
                chart[7] = new Chart(ctx7, $chart7data);
            </script>
            <p>Note. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreases, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that fewer cases registered today than yesterday.</p>
        </div>

        {
            if $chart21data {
                qq[
                    <div id="block21">
                        <a name="tests"></a>
                        <h2>｢{fmtnum($chart21data<tests>)}｣ tests performed</h2>
                        <p>This graph shows the total number of tests performed in ｢{$proper-country-name}{$without-str}｣. This graph does not reflect the outcome of the test cases. ｢$tests-fraction&thinsp;%｣ of the whole population have been tested.</p>
                        <canvas id="Chart21"></canvas>
                        <p class="left">
                            <label class="toggle-switchy" for="logscale21" data-size="xs" data-style="rounded" data-color="blue">
                                <input type="checkbox" id="logscale21" onclick="log_scale(this, 21)">
                                <span class="toggle">
                                    <span class="switch"></span>
                                </span>
                            </label>
                            <label for="logscale21"> Logarithmic scale</label>
                        </p>
                        <script>
                            var ctx21 = document.getElementById('Chart21').getContext('2d');
                            chart[21] = new Chart(ctx21, $chart21data<json>);
                        </script>
                    </div>
                ]
            }
        }

        $mortality-block
        $crude-block

        <div id="block19">
            <a name="per-capita"></a>
            <h2>Per capita values</h2>
            <p>Here, the number of confirmations and deaths [*i*]per 1000 of population[*/i*] ｢in {$proper-country-name}{$without-str}｣ is shown. These numbers is a better choice when comparing different countries than absolute numbers.</p>
            <canvas id="Chart19"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale19" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale19" onclick="log_scale(this, 19)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale19"> Logarithmic scale</label>
            </p>
            <script>
                var ctx19 = document.getElementById('Chart19').getContext('2d');
                chart[19] = new Chart(ctx19, $chart19data);
            </script>
        </div>

        <div id="block11">
            <a name="table"></a>
            <h1>Raw Daily Numbers</h1>
            $daily-table
        </div>

        {country-list(%CO<countries>, :$cc, :$exclude)}

        HTML

    my $url;
    if $exclude {
        my @parts = $exclude.lc.split('/');
        $url = '/' ~ @parts[0] ~ '/-' ~ @parts[1];
    }
    else {
        $url = '/' ~ $cc.lc;
    }

    html-template($url, "Coronavirus ｢in {$title-name}{$without-str}｣", $content);

    return %country-stats;
}

sub generate-countries-stats(%CO) is export {
    say 'Generating countries data...';

    my %chart5data = countries-first-appeared(%CO);
    my $countries-appeared = countries-appeared-this-day(%CO);

    my $percent = sprintf('%.1f', 100 * %chart5data<current-n> / %chart5data<total-countries>);

    my $content = qq:to/HTML/;
        <h1>Coronavirus in different countries</h1>

            <p class="center">
                <a href="/compare">Compare</a>
                |
                <a href="/per-million">Per capita</a>
                |
                <b>Affected countries</b>
            </p>

        <div id="block5">
            <h2>Number of Countries Affected</h2>
            <p class="center">｢%chart5data<current-n>｣ countires are affected, which is ｢{$percent}&thinsp;\%｣ from the total ｢%chart5data<total-countries>｣ countries.</p>
            <canvas id="Chart5"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale5" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale5" onclick="log_scale(this, 5)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale5"> Logarithmic scale</label>
            </p>
            <p>On this graph, you can see how many countries did have data about confirmed coronavirus invection for a given date over the last months.</p>
            <script>
                var ctx5 = document.getElementById('Chart5').getContext('2d');
                chart[5] = new Chart(ctx5, %chart5data<json>);
            </script>
        </div>

        <div id="block6">
            <h2>Countries or Regions Appeared This Day</h2>
            <p>This list gives you the overview of when the first confirmed case was reported in the given country. Or, you can see here, which countries entered the chart in the recent days. The number in parentheses is the number of confirmed cases in that country on that date.</p>
            $countries-appeared
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template('/countries', 'Coronavirus in different countries', $content);
}

sub generate-per-capita-stats(%CO, :$mode = '', :$cc-only = '') is export {
    #countries, %per-day, %totals, %daily-totals
    say 'Generating per-capita data...';

    my $N = 100;
    my $chart4data = countries-per-capita(%CO, limit => $N, :$mode, :$cc-only);
    my $chart14data = countries-per-capita(%CO, limit => $N, param => 'failed', :$mode, :$cc-only);

    my $in = '';
    my $topNconfirmations = "Top $N confirmations";
    my $topNfailures = "Top $N failures";

    if $cc-only eq 'US' {
        $in = 'in the USA';
        $topNconfirmations = 'Confirmations';
        $topNfailures = 'Failures';
    }
    elsif $cc-only eq 'CN' {
        $in = 'in China';
        $topNconfirmations = 'Confirmations';
        $topNfailures = 'Failures';
    }

    my $path = '/per-million';
    $path ~= "/$mode" if $mode;
    $path ~= "/{$cc-only.lc}" if $cc-only;

    my $content = qq:to/HTML/;
        <h1>Coronavirus per capita {$in}</h1>
        <p class="center">
            <a href="/compare/">Compare</a>
            |
            {$path eq '/per-million' ?? '<b>Countries</b>' !! '<a href="/per-million/">Countries</a>'}
            |
            {$path eq '/per-million/us' ?? '<b>US states</b>' !! '<a href="/per-million/us/">US states</a>'}
            |
            {$path eq '/per-million/cn' ?? '<b>China provinces</b>' !! '<a href="/per-million/cn/">China provinces</a>'}
            |
            {$path eq '/per-million/combined' ?? '<b>Combined</b>' !! '<a href="/per-million/combined">Combined</a>'}
        </p>

        <div id="block4">
            <a name="confirmed"></a>
            <h2>{$topNconfirmations} per million</h2>
            <p class="center">Sorted by <b>confirmed cases</b> | by <a href="#failed">failed cases</a></p>
            <p>This graph shows the number of affected people per each million of the population. The length of a bar per country is proportional to the number of confirmed cases per million.</p>
            {"<p>The ｢$N｣ most affected countries with more than one million of population are shown only. </p>" unless $cc-only}
            <div style="height: {$N * 1.9}ex">
                <canvas id="Chart4"></canvas>
            </div>
            <p class="left">
                <label class="toggle-switchy" for="logscale4" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale4" onclick="log_scale_horizontal(this, 4)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale4"> Logarithmic scale</label>
            </p>
            <script>
                var ctx4 = document.getElementById('Chart4').getContext('2d');
                chart[4] = new Chart(ctx4, $chart4data);
            </script>
        </div>

        <div id="block14">
            <a name="failed"></a>
            <h2>{$topNfailures} per million</h2>
            <p class="center">Sorted by <a href="#confirmed">confirmed cases</a> | by <b>failed cases</b></p>

            <p>This graph shows the relative number of people who could not recover from the disease. The data are the same as on the [*a href="#confirmed"*]graph above[*/a*] but sorted by the number of failures.</p>
            {"<p>The ｢$N｣ most affected countries with more than one million of population are shown only. </p>" unless $cc-only}
            <div style="height: {$N * 1.9}ex">
                <canvas id="Chart14"></canvas>
            </div>
            <p class="left">
                <label class="toggle-switchy" for="logscale14" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale14" onclick="log_scale_horizontal(this, 14)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale14"> Logarithmic scale</label>
            </p>
            <script>
                var ctx14 = document.getElementById('Chart14').getContext('2d');
                chart[14] = new Chart(ctx14, $chart14data);
            </script>
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template($path, 'Coronavirus per million of population', $content);
}

sub generate-continent-stats($cont, %CO, :$skip-excel = False) is export {
    say "Generating continent $cont...";

    my $chart1data = chart-pie(%CO, :$cont);
    my $chart2data = chart-daily(%CO, :$cont);
    my %chart3 = number-percent(%CO, :$cont);
    my $chart7data = daily-speed(%CO, :$cont);

    my $population = %chart3<population>;
    my @per-capita = per-capita-data($chart2data, 1_000_000 * $population);
    my $chart19data = per-capita-graph(@per-capita);

    my $table-path = %continents{$cont}.lc.subst(' ', '-');
    my $daily-table = daily-table($table-path, @per-capita);
    excel-table($table-path, @per-capita) unless $skip-excel;

    my $percent-str = %chart3<percent> ~ '&thinsp;%';
    my $population-str = '｢' ~ $population.round() ~ '｣ million';

    my $continent-name = %continents{$cont};
    my $continent-url = $continent-name.lc.subst(' ', '-');

    my $content = qq:to/HTML/;
        <h1>Coronavirus ｢in {$continent-name}｣</h1>

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">{$percent-str}</div>
            <p class="center">This is the part of confirmed infection cases against the total $population-str of its population.</p>
            <div class="affected">
                {
                    if $chart2data<confirmed> {
                        "Affected ｢{smart-round(@per-capita[0]<confirmed-per1000-str>)}｣ per 1000 people"
                    }
                    else {
                        'Nobody affected'
                    }
                }
            </div>
            <div class="failed">
                {
                    if $chart2data<failed> {
                        "Died ｢{smart-round(@per-capita[0]<failed-per1000-str>)}｣ per 1000 people"
                    }
                }
            </div>
        </div>

        <div id="block1">
            <a name="recovery"></a>
            <h2>Recovery Pie</h2>
            <p class="center">The whole pie reflects the total number of confirmed cases of people infected by coronavirus ｢in {$continent-name}｣.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block9">
            <a name="raw"></a>
            <h2>Raw Numbers on {fmtdate($chart2data<date>)}</h2>
            <p class="confirmed"><span>｢{fmtnum($chart2data<confirmed>)}｣</span><span class="updown"><sup>confirmed</sup><sub>｢{pm($chart2data<delta-confirmed>)}｣</sub></span></p>
            <p class="recovered"><span>｢{fmtnum($chart2data<recovered>)}｣</span><span class="updown"><sup>recovered</sup><sub>｢{pm($chart2data<delta-recovered>)}｣</sub></span></p>
            <p class="failed"><span>｢{fmtnum($chart2data<failed>)}｣</span><span class="updown"><sup>fatal</sup><sub>｢{pm($chart2data<delta-failed>)}｣</sub></span></p>
            <p class="active"><span>｢{fmtnum($chart2data<active>)}｣</span><span class="updown"><sup>active</sup><sub>｢{pm($chart2data<delta-active>)}｣</sub></span></p>
        </div>

        <div id="block3">
            <a name="daily"></a>
            <h2>Daily Flow</h2>
            <p>The height of a single bar is the total number of people suffered from Coronavirus in $continent-name and confirmed to be infected. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <canvas id="Chart2"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale2" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale2" onclick="log_scale(this, 2)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale2"> Logarithmic scale</label>
            </p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                chart[2] = new Chart(ctx2, $chart2data<json>);
            </script>
        </div>

        <div id="block10">
            <a name="new"></a>
            <h2>New Confirmed Cases</h2>
            <p>This graph shows the number of new cases by day. The lightblue bars are the number of the new total confirmed cases appeared that day.</p>
            <canvas id="Chart10"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale10" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale10" onclick="log_scale(this, 10)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale10"> Logarithmic scale</label>
            </p>
            <script>
                var ctx10 = document.getElementById('Chart10').getContext('2d');
                chart[10] = new Chart(ctx10, $chart2data<delta-json>);
            </script>
        </div>

        <div id="block7">
            <a name="speed"></a>
            <h2>Daily Speed</h2>
            <p>This graph shows the speed of growth (in %) over time ｢in {$continent-name}｣. The only parameter here is the number of confirmed cases.</p>
            <canvas id="Chart7"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale7" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale7" checked="checked" onclick="log_scale(this, 7)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale7"> Logarithmic scale</label>
            </p>
            <script>
                var ctx7 = document.getElementById('Chart7').getContext('2d');
                chart[7] = new Chart(ctx7, $chart7data);
            </script>
            <p>Note. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreases, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that fewer cases registered today than yesterday.</p>
        </div>

        <div id="block19">
            <a name="per-capita"></a>
            <h2>Per capita values</h2>
            <p>Here, the number of confirmations and deaths <i>per 1000 of population</i> ｢in {$continent-name}｣ is shown. These numbers is a better choice when comparing different countries than absolute numbers.</p>
            <canvas id="Chart19"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale19" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale19" onclick="log_scale(this, 19)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale19"> Logarithmic scale</label>
            </p>
            <script>
                var ctx19 = document.getElementById('Chart19').getContext('2d');
                chart[19] = new Chart(ctx19, $chart19data);
            </script>
        </div>

        <div id="block11">
            <a name="table"></a>
            <h1>Raw Daily Numbers</h1>
            $daily-table
        </div>

        {country-list(%CO<countries>, :$cont)}

        HTML

    html-template("/$continent-url", "Coronavirus ｢in $continent-name｣", $content);
}

sub generate-china-level-stats(%CO) is export {
    say 'Generating stats vs China...';

    my $chart6data = countries-vs-china(%CO);

    my $content = qq:to/HTML/;
        <h1>Countries vs China</h1>

        <script>
            var randomColorGenerator = function () \{
                return '#' + (Math.random().toString(16) + '0000000').slice(2, 8);
            \};
        </script>

        <div id="block6">
            <h2>Confirmed population timeline</h2>
            <p>On this graph, you see how the fraction (in %) of the confirmed infection cases changes over time in different countries.</p>
            <p>The almost-horizontal red line in the bottom part of the graph line displays [*a href="/cn/LNG"*]China[*/a*]. The number of confirmed infections in China almost stopped growing. Note the top line reflecting the most suffered province of China, [*a href="/cn/hb/LNG"*]Hubei[*/a*], where the spread is also almost stopped.</p>
            <p>Click on the bar in the legend to turn the line off and on.</p>
            <br/>
            <canvas id="Chart6"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale6" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale6" onclick="log_scale(this, 6)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale6"> Logarithmic scale</label>
            </p>
            <p>1. Note that only countries with more than 1000 population are taken into account. The smaller countries such as [*a href="/va/LNG"*]Vatican[*/a*] or [*a href="/sm/LNG"*]San Marino[*/a*] would have shown too high nimbers due to their small population.</p>
            <p>2. The line for the country is drawn only if it reaches at least 85% of the corresponding maximum parameter in China.</p>
            <script>
                var ctx6 = document.getElementById('Chart6').getContext('2d');
                chart[6] = new Chart(ctx6, $chart6data);
            </script>
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template('/vs-china', 'Countries vs China', $content);
}

sub generate-continent-graph(%CO) is export {
    my $chart8data = continent-joint-graph(%CO);

    my $content = qq:to/HTML/;
        <h1>Coronavirus Spread over the Continents</h1>

        <div id="block3">
            <a name="active"></a>
            <h2>Active Cases Timeline</h2>
            <p class="center"><b>Active cases</b> | <a href="#confirmed">Confirmed cases</a></p>

            <p>This bar chart displays the timeline of the number of active cases (thus, confirmed minus failed to recovered minus recovered). The blue bars correspond to the number of confirmed cases in [*a href="/europe/LNG"*]Europe[*/a*], and the violet bars—[*a href="/north-america/LNG"*]North America[*/a*].</p>
            <canvas id="Chart8"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale8" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale8" onclick="log_scale(this, 8)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale8"> Logarithmic scale</label>
            </p>
            <script>
                var ctx8 = document.getElementById('Chart8').getContext('2d');
                chart[8] = new Chart(ctx8, $chart8data<active>);
            </script>
        </div>

        <div id="block16">
            <a name="confirmed"></a>
            <h2>Confirmed Cases Timeline</h2>
            <p class="center"><a href="#active">Active cases</a> | <b>Confirmed cases</b></p>

            <p>This bar chart displays the timeline of the number of confirmed cases. The gold bars are those reflecting [*a href="/asia/LNG"*]Asia[*/a*]. The blue bars correspond to the number of confirmed cases in [*a href="/europe/LNG"*]Europe[*/a*], and the violet bars—[*a href="/north-america/LNG"*]North America[*/a*].</p>
            <canvas id="Chart16"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale16" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale16" onclick="log_scale(this, 16)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale16"> Logarithmic scale</label>
            </p>
            <script>
                var ctx16 = document.getElementById('Chart16').getContext('2d');
                chart[16] = new Chart(ctx16, $chart8data<confirmed>);
            </script>
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template('/continents', 'Coronavirus over the Continents', $content);
}

sub generate-scattered-age(%CO) is export {
    say "Generating cases vs age...";

    my $chart11data = scattered-age-graph(%CO);

    my $content = qq:to/HTML/;
        <h1>Coronavirus vs Life Expectancy</h1>

        <div id="block3">
            <p>Each point on this graph reflects a single country. The blue dots are the number of confirmed cases (in % to the total population of the country), the red ones are the fraction of people failed to recover (in % to the total population). Move the cursor over the dot to see the name of the country.</p>
            <canvas id="Chart11"></canvas>
            <script>
                var ctx11 = document.getElementById('Chart11').getContext('2d');
                chart[11] = Chart.Scatter(ctx11, $chart11data);
            </script>
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template('/vs-age', 'Coronavirus vs Life Expectancy', $content);
}

sub generate-scattered-density(%CO) is export {
    say "Generating cases vs density...";

    my $chart20data = scattered-density-graph(%CO);

    my $content = qq:to/HTML/;
        <h1>Coronavirus vs Population Density</h1>

        <div id="block3">
            <p>Each point on this graph reflects a single country. The blue dots are the absolute number of confirmed cases, the red ones are the fraction of people failed to recover. Move the cursor over the dot to see the name of the country. Note that only the countires with more than one million of population are shown.</p>
            <canvas id="Chart20"></canvas>
            <script>
                var ctx20 = document.getElementById('Chart20').getContext('2d');
                chart[20] = Chart.Scatter(ctx20, $chart20data);
            </script>
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template('/vs-density', 'Coronavirus vs Population Density', $content);
}

sub generate-overview(%CO) is export {
    say "Generating dashboard overview...";

    my %delta;
    my %confirmed;
    my %failed;
    my @max;

    my @dates = %CO<daily-totals>.keys.sort.grep: * le %CO<calendar><World>;
    my $days = @dates.elems - 2;

    my @display-dates;

    my @dashboard;

    my %levels;

    for 2 .. $days + 1 -> $day {
        my $day-max = 0;

        @display-dates.push("'" ~ fmtdate(@dates[$day]) ~ "'");

        my @recent-dates = %CO<daily-totals>.keys.sort[$day - 1, $day];

        for %CO<per-day>.keys -> $cc {
            next if $cc ~~ /'/'/;

            my $prev = %CO<per-day>{$cc}{@recent-dates[0]};
            my $curr = %CO<per-day>{$cc}{@recent-dates[1]};

            %delta{$cc}     //= [];
            %confirmed{$cc} //= [];
            %failed{$cc}    //= [];
            my $delta = 0;

            if ($curr) {
                my $curr-confirmed = $curr<confirmed>;
                my $prev-confirmed = $prev<confirmed> // 0;

                $delta = $curr-confirmed - $prev-confirmed;

                $delta = 0 if $delta < 0;
                %delta{$cc}.push($delta);

                %confirmed{$cc}.push($curr-confirmed);
                %failed{$cc}.push($curr<failed> // 0);
            }
            else {
                %delta{$cc}.push(0);
                %confirmed{$cc}.push(0);
                %failed{$cc}.push(0);
            }

            $day-max = $delta if $delta > $day-max;
        }
        @max.push($day-max ?? log($day-max) !! 0);


        my $dashboard = '';
        for %CO<countries>.sort: *.value<country> -> $c {
            my $cc = $c.key;
            my $country = $c.value<country>;
            next if $cc ~~ /'/'/;

            my $have-data = %confirmed{$cc}:exists;

            my $confirmed = $have-data ?? %confirmed{$cc}[*-1] !! 0;
            my $failed    = $have-data ?? %failed{$cc}[*-1]    !! 0;
            my $delta     = $have-data ?? %delta{$cc}[*-1]     !! 0;

            my $level;
            if $have-data && $confirmed {
                $level = $delta ?? (10 * log($delta) / @max[*-1]).round() !! 0;
                $level = 0 if $level < 0;
            }
            else {
                $level = 'N';
            }

            # %levels{$cc}{$day} = $level;
            %levels{$cc} = $level;

            my $item = '<div class="L' ~ $level ~ '"><p class="c">' ~ fmtnum($confirmed) ~ '</p><p class="d">' ~
                    ($confirmed ?? fmtnum($failed) !! '') ~ '</p><h5>' ~ $country ~ '</h5></div>';

            if $confirmed {
                $dashboard ~= '<a href="/' ~ $cc.lc ~ '">' ~ $item ~ '</a>';
            }
            else {
                $dashboard ~= $item;
            }
        }

        @dashboard.push($dashboard);
    }

    my $content = qq:to/HTML/;
        <h1>Coronavirus World Overview</h1>

        <div id="block13">
            <p>Each cell here represents a country, and the colour of the cell reflects the number of new confirmed cases happened since yesterday.</p>
            <p>The numbers shown are the total number of confirmed infections and the number of people failed to recover. Click on the cell to get more information about the country.</p>
            <div class="dashboard" id="Dashboard">
                @dashboard[*-1]
            </div>
            <div class="clear"></div>

            <div class="slidecontainer">
                <input type="range" min="1" max="$days" value="$days" class="slider" id="sliderInput">
                <h2><span id="currentDate"></span></h2>
                <input type="button" value="►" style="font-size: 400%; cursor: pointer;" onclick="PlayOverview(0)"/>
            </div>
        </div>

        <script>
            var dashboard = {to-json(@dashboard)};

            var dates = \[{@display-dates.join(', ')}\];

            var slider = document.getElementById("sliderInput");
            var output = document.getElementById("currentDate");
            output.innerHTML = dates[dates.length - 1];

            var dashboardDiv = document.getElementById('Dashboard');

            slider.oninput = function() \{
                var n = this.value - 1;
                output.innerHTML = dates[n];
                dashboardDiv.innerHTML = dashboard[n];
            \}

            function PlayOverview(n) \{
                slider.value = n;

                if (slider.max == slider.value) return;

                setTimeout(function () \{
                    output.innerHTML = dates[n];
                    dashboardDiv.innerHTML = dashboard[n];

                    PlayOverview(n + 1);
                \}, 250);
            \}
        </script>

        {country-list(%CO<countries>)}

        HTML

    html-template('/overview', 'Coronavirus World Overview Dashboard', $content);

    return %levels;
}

sub generate-js-countries(%CO) is export {
    #%countries, %per-day, %totals, %daily-totals
    say "Generating a new JS country list...";

    my @countries;
    for %CO<countries>.sort: *.value<country> -> $c {
        my $cc = $c.key;
        next if $cc ~~ /'/'/;
        next unless %CO<per-day>{$cc};

        my $country = $c.value<country>;
        $country ~~ s:g/\'/\\'/;

        @countries.push("['$cc','$country']");
    }

    for %CO<countries>.sort: *.value<country> -> $c {
        my $cc = $c.key;
        next unless $cc ~~ /'/'/;
        next unless %CO<per-day>{$cc};

        my $country = $c.value<country>;
        $country ~~ s:g/\'/\\'/;

        @countries.push("['$cc','$country']");
    }

    my $js = q{var countries = [['asia','Asia'],['africa','Africa'],['europe','Europe'],['north-america','North America'],['south-america','South America'],['oceania','Oceania'],} ~
        @countries.join(',') ~ "];";

    my $filepath = "./www/countries.js";
    my $io = $filepath.IO;
    my $fh = $io.open(:w);
    $fh.say: $js;
    $fh.close;
}

# sub generate-common-start-stats(%countries, %per-day, %totals, %daily-totals) is export {
#     say 'Generating common start graph...';

#     my $chart15data = common-start(%countries, %per-day, %totals, %daily-totals);

#     my $content = qq:to/HTML/;
#         <h1>Countries vs China</h1>

#         <script>
#             var randomColorGenerator = function () \{
#                 return '#' + (Math.random().toString(16) + '0000000').slice(2, 8);
#             \};
#         </script>

#         <div id="block6">
#             <h2>Confirmed population timeline</h2>
#             <p>On this graph, you see how the fraction (in %) of the confirmed infection cases changes over time in different countries.</p>
#             <p>The almost-horizontal red line in the bottom part of the graph line displays <a href="/cn">China</a>. The number of confirmed infections in China almost stopped growing. Note the top line reflecting the most suffered province of China, <a href="/cn/hb">Hubei</a>, where the spread is also almost stopped.</p>
#             <p>Click on the bar in the legend to turn the line off and on.</p>
#             <br/>
#             <canvas id="Chart6"></canvas>
#             <p class="left">
#                 <label class="toggle-switchy" for="logscale6" data-size="xs" data-style="rounded" data-color="blue">
#                     <input type="checkbox" id="logscale6" onclick="log_scale(this, 6)">
#                     <span class="toggle">
#                         <span class="switch"></span>
#                     </span>
#                 </label>
#                 <label for="logscale6"> Logarithmic scale</label>
#             </p>
#             <p>1. Note that only countries with more than 1000 population are taken into account. The smaller countries such as <a href="/va">Vatican</a> or <a href="/sm">San Marino</a> would have shown too high nimbers due to their small population.</p>
#             <p>2. The line for the country is drawn only if it reaches at least 85% of the corresponding maximum parameter in China.</p>
#             <script>
#                 var ctx15 = document.getElementById('Chart15').getContext('2d');
#                 chart[15] = new Chart(ctx15, $chart15data);
#             </script>
#         </div>

#         {country-list(%countries)}

#         HTML

#     html-template('/start', 'Coronavirus in different countries if it would have started at the same day', $content);
# }

sub generate-world-map(%CO, %levels) is export {
    say "Generating World map...";

    my $header = q:to/HEAD/;
        <script src="/svgMap.js" type="text/javascript"></script>
        <link rel="stylesheet" type="text/css" href="/svgMap.min.css">
        HEAD

    my @data;

    my @confirmed;
    my @failed;
    my @recovered;
    my @percent;

    my @color = '#93bb2b', '#cfcc26', '#d4bf26', '#d4bf25', '#d7ab24',
                '#d79323', '#d77820', '#d75c20', '#d7421e', '#d72b1d', '#d71c1c';

    for %CO<totals>.keys -> $cc {
        next unless $cc.chars == 2;

        next unless %CO<countries>{$cc}:exists;
        my $population = 1_000_000 * %CO<countries>{$cc}<population>;
        next unless $population;

        my $confirmed = %CO<totals>{$cc}<confirmed> || 0;
        my $percent = sprintf('%2f', (100 * $confirmed / $population));

        my $failed = %CO<totals>{$cc}<failed> || 0;
        my $recovered = %CO<totals>{$cc}<recovered> || 0;

        @confirmed.push($confirmed);
        @failed.push($failed);
        @recovered.push($recovered);
        @percent.push($percent);

        my $level = %levels{$cc} || 0;
        my $color = $level eq 'N' ?? 'gray' !! @color[$level];
        @data.push("$cc: \{confirmed: $confirmed, failed: $failed, recovered: $recovered, percent: $percent, color: '$color'\}");
    }

    my $script = qq:to/SCRIPT/;
        <script>
            new svgMap(\{
                targetElementID: 'svgMap',
                flagType: 'emoji',
                colorMin: '#93bb2b',
                colorMax: '#d71c1c',
                mouseWheelZoomEnabled: false,
                noDataText: 'No data for this country',
                data: \{
                    data: \{
                        confirmed: \{
                            name: 'Confirmed cases',
                            format: '\{0}',
                            thousandSeparator: ',',
                            thresholdMax: {max(@confirmed)},
                            thresholdMin: {min(@confirmed)}
                        },
                        failed: \{
                            name: 'Died',
                            format: '\{0}',
                            thousandSeparator: ',',
                            thresholdMax: {max(@failed)},
                            thresholdMin: {min(@failed)}
                        },
                        recovered: \{
                            name: 'Recovered',
                            format: '\{0}',
                            thousandSeparator: ',',
                            thresholdMax: {max(@recovered)},
                            thresholdMin: {min(@recovered)}
                        },
                        percent: \{
                            name: 'Affected population',
                            format: '\{0} %',
                            thresholdMax: {max(@percent)},
                            thresholdMin: {min(@percent)}
                        }
                    },
                    applyData: 'confirmed',
                    values: \{
                        {@data.join(",\n")}
                    }
                }
            });
        </script>
        SCRIPT

    my $content = qq:to/HTML/;
        <h1>Coronavirus World Map</h1>

        <p>The colour of the country reflects the number of new confirmed cases happened since yesterday. Click on the map to navigate to the country-level page to get more information about the country.</p>
        <div id="svgMap"></div>
        $script

        {country-list(%CO<countries>)}

        HTML

    html-template('/map', 'Coronavirus world map', $content, $header);
}

sub generate-countries-compare(%country-stats, %countries, :$prefix?, :$limit?) is export {
    say 'Generating comparison...';

    my $path = '/compare';
    $path = '/' ~ $prefix.lc ~ $path if $prefix;
    $path ~= '/all' if !$limit && !$prefix;

    my $x-range = '';
    $x-range = ", min: '2020-03-15'" if $prefix && $prefix eq 'RU';

    my $content = q:to/HTML/;
            <script>
                var smallOptionsA = {
                    animation: false,
                    maintainAspectRatio: false,
                    legend: {
                        display: false
                    },
                    scales: {
                        xAxes: [{
                            stacked: true,
                            ticks: {
                                display: false
                                XRANGE
                            },
                            gridLines: {
                                display: false,
                                drawBorder: false
                            }
                        }],
                        yAxes: [{
                            stacked: true,
                            ticks: {
                                display: false,
                                min: 0
                            },
                            gridLines: {
                                drawTicks: false,
                                drawBorder: false,
                                lineWidth: 0,
                                zeroLineColor: '#eeeeee'
                            }
                        }]
                    }
                }
                var smallOptionsB = {
                    animation: false,
                    maintainAspectRatio: false,
                    legend: {
                        display: false
                    },
                    scales: {
                        xAxes: [{
                            ticks: {
                                display: false
                                XRANGE
                            },
                            gridLines: {
                                display: false,
                                drawBorder: false
                            }
                        }],
                        yAxes: [{
                            ticks: {
                                display: false,
                                min: 0
                            },
                            gridLines: {
                                drawTicks: false,
                                drawBorder: false,
                                lineWidth: 0,
                                zeroLineColor: '#eeeeee'
                            }
                        }]
                    }
                }
            </script>
        HTML

        $content ~~ s:g/XRANGE/$x-range/;

        $content ~= qq:to/HTML/;
            <h1>
                {
                    if    $path eq '/compare'     {'Compare the countries[*br/*]affected by coronavirus'  }
                    elsif $path eq '/compare/all' {'Compare all countries[*br/*]affected by coronavirus'  }
                    elsif $path eq '/us/compare'  {'Compare the US states[*br/*]affected by coronavirus'  }
                    elsif $path eq '/cn/compare'  {'Compare China’s provinces[*br/*]affected by coronavirus'}
                    elsif $path eq '/ru/compare'  {'Compare Russia’s regions[*br/*]affected by coronavirus'}
                }
            </h1>

            <p class="center">
                {$path eq '/compare' ?? '<b>Compare countries</b>' !! '<a href="/compare/LNG">Compare countries</a>'}
                |
                <a href="/per-million/LNG">Per capita</a>
                |
                <a href="/countries/LNG">Affected countries</a>
            </p>
            <p class="center">
                {$path eq '/us/compare' ?? '<b>US states</b>' !! '<a href="/us/compare/LNG">US states</a>'}
                |
                {$path eq '/cn/compare' ?? '<b>China’s provinces</b>' !! '<a href="/cn/compare/LNG">China’s provinces</a>'}
                |
                {$path eq '/ru/compare' ?? '<b>Russia’s regions</b>' !! '<a href="/ru/compare/LNG">Russia’s regions</a>'}
            </p>
            {'<p class="center"><a href="/pie/us/LNG">Compare the states on a pie diagram</a></p>' if $path eq '/us/compare'}
            {'<p class="center"><a href="/pie/cn/LNG">Compare the provinces on a pie diagram</a></p>' if $path eq '/cn/compare'}
            {'<p class="center"><a href="/pie/ru/LNG">Compare the regions on a pie diagram</a></p>' if $path eq '/ru/compare'}

            {qq[<p>On this page, the most affected ｢$limit｣ countries are listed sorted by the number of confirmed cases. You can click on the country name to see more details about the country. The numbers below the name of the country are the numbers of confirmed (black), recovered (green, if known), and fatal cases (red). These numbers are displayed on the graph in the middle column. The graphs on the right draw the number of new cases a day. Move the mouse over the graphs to see the dates and the numbers. Note that the scale of the vertical axis differs per country.</p><p>Visit [*a href="/compare/all/LNG"*]a separate page[*/a*] to see the comparison of all countries. The green and red arrows next to the country name display the trend of the new confirmed cases during the last week.</p>] if $path eq '/compare'}

            {qq[<p>On this page, all the countries affected by coronavirus are listed sorted by the number of confirmed cases. You can click on the country name to see more details about the country. The numbers below the name of the country are the numbers of confirmed (black), recovered (green, if known), and fatal cases (red). These numbers are displayed on the graph in the middle column. The graphs on the right draw the number of new cases a day.  Move the mouse over the graphs to see the dates and the numbers. Note that the scale of the vertical axis differs per country.</p><p>The green and red arrows next to the country name display the trend of the new confirmed cases during the last week.</p>] if $path eq '/compare/all'}

            {'<p>On this page, the US states are listed sorted by the number of confirmed cases. You can click on the state name to see more details about it. The numbers below the state name are the numbers of confirmed (black) and fatal cases (red). These numbers are displayed on the graph in the middle column. The graphs on the right draw the number of new cases a day. Move the mouse over the graphs to see the dates and the numbers. Note that the scale of the vertical axis differs per state.</p><p>The green and red arrows next to the state name display the trend of the new confirmed cases during the last week.' if $path eq '/us/compare'}

            {'<p>On this page, China provinces and regions are listed sorted by the number of confirmed cases. You can click on the name to see the more details about the region. The numbers below are the numbers of confirmed (black), recovered (green, if known), and fatal cases (red). These numbers are displayed on the graph in the middle column. The graphs on the right draw the number of new cases a day. Move the mouse over the graphs to see the dates and the numbers. Note that the scale of the vertical axis differs per region.</p><p>The green and red arrows next to the region name display the trend of the new confirmed cases during the last week.' if $path eq '/cn/compare'}

            {'<p>On this page, the regions of the Russian Federation are listed sorted by the number of confirmed cases. You can click on the name to see the more details about the region. The numbers below are the numbers of confirmed (black), recovered (green), and fatal cases (red). These numbers are displayed on the graph in the middle column. The graphs on the right draw the number of new cases a day. Move the mouse over the graphs to see the dates and the numbers. Note that the scale of the vertical axis differs per region.</p><p>The green and red arrows next to the region name display the trend of the new confirmed cases during the last week.' if $path eq '/ru/compare'}

            <table class="compare">
                <thead>
                    <tr>
                        <th>{
                            $path eq '/compare' ?? 'Country' !! 'Region'
                        }</th>
                        <th>Cumulative cases</th>
                        <th>New daily cases</th>
                    </tr>
                </thead>
                <tbody>
        HTML

    my $count = 0;
    for %country-stats.sort: -*.value<chart-daily><confirmed> -> %c {
        my $cc = %c.key;

        if $prefix {
            next unless $cc ~~ / $prefix '/' /;
        }
        else {
            next if $cc ~~ / '/' /;
        }

        if $limit {
            last if ++$count > $limit;
        }

        my %data = %country-stats{$cc}<chart-daily>;

        my $id = $cc.subst('/', '');
        my $json = %data<json-small>;
        my $json-delta = %data<delta-json-small>;

        %countries{$cc}<country> ~~ /^ .+ '/' (.+) $/;
        my $country-or-region-name = $/[0] // %countries{$cc}<country>;

        $content ~= qq:to/HTML/;
            <tr>
                <td class="h3">
                    <h4>
                        <a href="/{$cc.lc}/LNG">{$country-or-region-name}</a>
                        {arrow(%countries, $cc)}
                    </h4>
                    <p>
                        {fmtnum(%data<confirmed>)}<br/>
                        {qq[<span class="recovered">{fmtnum(%data<recovered>)}</span><br/>] if %data<recovered>}
                        <span class="failed">{fmtnum(%data<failed>)}</span>
                    </p>
                </td>

                <td>
                    <div class="mini"><canvas id="ChartA_$id"></canvas></div>
                    <script>new Chart(document.getElementById('ChartA_$id').getContext('2d'), $json);</script>
                </td>
                <td>
                    <div class="mini"><canvas id="ChartB_$id"></canvas></div>
                    <script>new Chart(document.getElementById('ChartB_$id').getContext('2d'), $json-delta);</script>
                </td>
            </tr>
            HTML
    }

    $content ~= qq:to/HTML/;
            </tbody>
        </table>

        HTML

    html-template($path, 'Compare the countries with coronavirus', $content);
}

sub generate-pie-diagrams(%CO, :$cc?) is export {
    say "Generating pie diagrams{ qq{ in $cc} if $cc }...";

    my $chart22data = world-pie-diagrams(%CO, :$cc);
    my $chart23data = world-fatal-diagrams(%CO, :$cc);

    my $title;
    my $h2a;
    my $h2b;
    my $where;
    if $cc {
        if $cc eq 'US' {
            $title = 'Coronavirus distribution over the US states';
            $h2a = 'Confirmed cases in the US states';
            $h2b = 'Fatal cases in the US states';
            $where = 'in the US';
        }
        elsif $cc eq 'CN' {
            $title = 'Coronavirus distribution over the China’s regions';
            $h2a = 'Confirmed cases in China’s regions';
            $h2b = 'Fatal cases in China’s regions';
            $where = 'in China';
        }
        elsif $cc eq 'RU' {
            $title = 'Coronavirus distribution over the regions of Russia';
            $h2a = 'Confirmed cases in Russia’s regions';
            $h2b = 'Fatal cases in Russia’s regions';
            $where = 'in Russia';
        }
    }
    else {
        $title = 'Coronavirus distribution over different countries';
        $h2a = 'Confirmed cases worldwide';
        $h2b = 'Fatal cases worldwide';
        $where = 'in the whole world';
    }

    my $content = qq:to/HTML/;
        <h1>{$title}</h1>

        <div id="block22">
            <a name="confirmed"></a>
            <h2>{$h2a}</h2>
            <p class="center"><b>Confirmed cases</b> | <a href="#failed">Fatal cases</a></p>
            <p class="center">The whole pie reflects the total number of the confirmed cases {$where}.</p>
            <canvas id="Chart22"></canvas>
            <script>
                var ctx22 = document.getElementById('Chart22').getContext('2d');
                chart[22] = new Chart(ctx22, $chart22data);
            </script>
        </div>

        <div id="block23">
            <a name="failed"></a>
            <h2>{$h2b}</h2>
            <p class="center"><a href="#confirmed">Confirmed cases</a> | <b>Fatal cases</b></p>
            <p class="center">The whole pie reflects the total number of fatal cases {$where}.</p>
            <canvas id="Chart23"></canvas>
            <script>
                var ctx23 = document.getElementById('Chart23').getContext('2d');
                chart[23] = new Chart(ctx23, $chart23data);
            </script>
        </div>

        {country-list(%CO<countries>, :$cc)}

        HTML

    my $path = '/pie';
    $path ~= '/' ~ $cc.lc if $cc;

    html-template("$path", $title, $content, '<script src="/outlabels.js"></script>');
}

sub genrate-impact-timeline(%CO) is export {
    say "Generating impact timeline...";

    my $chart24data = impact-timeline(%CO);

    my $content = qq:to/HTML/;
        <h1>Countries Impact Timeline</h1>

        <div id="block24">
            <p class="center">Here, you can see the impact from different countries over the timespan of the coronavirus pandemic. The number of the new daily confirmed cases is shown averaged by 7 days.</p>
            <canvas id="Chart24"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale24" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale24" onclick="log_scale(this, 24)">
                    <span class="toggle">
                        <span class="switch"></span>
                    </span>
                </label>
                <label for="logscale24"> Logarithmic scale</label>
            </p>
            <script>
                var ctx24 = document.getElementById('Chart24').getContext('2d');
                chart[24] = new Chart(ctx24, $chart24data);
            </script>
        </div>

        {country-list(%CO<countries>)}

        HTML

    html-template('/impact', 'Countries impact timeline', $content);
}
