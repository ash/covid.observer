unit module CovidObserver::Generation;

use JSON::Tiny;

use CovidObserver::Population;
use CovidObserver::Statistics;
use CovidObserver::HTML;
use JSON::Tiny;

sub generate-world-stats(%countries, %per-day, %totals, %daily-totals, :$exclude?) is export {
    my $without-str = $exclude ?? " excluding %countries{$exclude}<country>" !! '';
    say "Generating world data{$without-str}...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, :$exclude);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, :$exclude);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, :$exclude);

    my $chart7data = daily-speed(%countries, %per-day, %totals, %daily-totals, :$exclude);

    my $daily-table = daily-table($chart2data, $world-population / 1_000_000);

    my $country-list = country-list(%countries, :$exclude);
    my $continent-list = continent-list();

    my $content = qq:to/HTML/;
        <h1>COVID-19 World Statistics{$without-str}</h1>

        <div id="block2">
            <h2>Affected World Population{$without-str}</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of confirmed infection cases against the total {
                if $exclude {
                    sprintf('%.1f', ($world-population / 1_000_000 - %countries{$exclude}<population>) / 1000)
                }
                else {
                    '7.8'
                }
            } billion of the world population{$without-str}.</p>
            <div class="affected">
                {
                    if $chart2data<confirmed> {
                        'Affected 1 of every ' ~ fmtnum(($world-population / $chart2data<confirmed>).round())
                    }
                    else {
                        'Nobody affected'
                    }
                }
            </div>
            <div class="failed">
                {
                    if $chart2data<failed> {
                        'Failed to recover 1 of every ' ~ fmtnum(($world-population / $chart2data<failed>).round())
                    }
                }
            </div>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in the whole world{$without-str}.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block9">
            <a name="raw"></a>
            <h2>Raw Numbers on {fmtdate($chart2data<date>)}</h2>
            <p class="confirmed"><span>{fmtnum($chart2data<confirmed>)}</span><sup>confirmed</sup></p>
            <p class="recovered"><span>{fmtnum($chart2data<recovered>)}</span><sup>recovered</sup></p>
            <p class="failed"><span>{fmtnum($chart2data<failed>)}</span><sup>failed</sup></p>
            <p class="active"><span>{fmtnum($chart2data<active>)}</span><sup>active</sup></p>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
            <p>The height of a single bar is the total number of people suffered from Coronavirus confirmed to be infected in the world{$without-str}. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
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
            <p>This graph shows the speed of growth (in %) over time. The main three parameters are the number of confirmed cases, the number of recoveries and failures. The orange line is the speed of changing of the number of active cases (i.e., of those, who are still ill).</p>
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
            <!--p>Note 1. In calculations, the 3-day moving average is used.</p-->
            <p>Note. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreases, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that less cases registered today than yesterday.</p>
        </div>

        <div id="block11">
            <a name="table"></a>
            <h1>Raw Daily Numbers</h1>
            $daily-table
        </div>

        $continent-list
        $country-list

        HTML

    my $exclude-path = $exclude ?? '-' ~ $exclude.lc !! '';
    html-template("/$exclude-path", "World statistics$without-str", $content);
}

sub generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals, :$exclude?) is export {
    my $without-str = $exclude ?? " excluding %countries{$exclude}<country>" !! '';
    say "Generating {$cc}{$without-str}...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, :$cc, :$exclude);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, :$cc, :$exclude);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, :$cc, :$exclude);

    my $chart7data = daily-speed(%countries, %per-day, %totals, %daily-totals, :$cc, :$exclude);

    my $country-list = country-list(%countries, :$cc, :$exclude);
    my $continent-list = continent-list(%countries{$cc}<continent>);

    my $country-name = %countries{$cc}<country>;
    my $population = +%countries{$cc}<population>;

    if $exclude {
        $population -= %countries{$exclude}<population>;
    }

    my $daily-table = daily-table($chart2data, $population);

    my $population-str = $population <= 1
        ?? sprintf('%i thousand', (1000 * $population).round)
        !! sprintf('%i million', $population.round);

    my $proper-country-name = $country-name;
    $proper-country-name = "the $country-name" if $cc ~~ /[US|GB|NL|DO|CZ|BS|GM|CD|CG]$/;

    my $per-region-link = per-region($cc);
    if $cc eq 'NL' {
        $per-region-link ~= q:to/LINKS/;
            <p>Note: The numbers for <a href="/aw">Aruba</a>, <a href="/cw">Curaçao</a>, and <a href="/sx">Sint Maarten</a> are not included in the statistics for the Netherlands.</p>
            LINKS
    }

    my $content = qq:to/HTML/;
        <h1>Coronavirus in {$proper-country-name}{$without-str}</h1>
        $per-region-link

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of confirmed infection cases against the total $population-str of its population.</p>
            <div class="affected">
                {
                    if $chart2data<confirmed> {
                        'Affected 1 of every ' ~ fmtnum((1_000_000 * $population / $chart2data<confirmed>).round())
                    }
                    else {
                        'Nobody affected'
                    }
                }
            </div>
            <div class="failed">
                {
                    if $chart2data<failed> {
                        'Failed to recover 1 of every ' ~ fmtnum((1_000_000 * $population / $chart2data<failed>).round())
                    }
                }
            </div>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in {$proper-country-name}{$without-str}.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block9">
            <a name="raw"></a>
            <h2>Raw Numbers on {fmtdate($chart2data<date>)}</h2>
            <p class="confirmed"><span>{fmtnum($chart2data<confirmed>)}</span><sup>confirmed</sup></p>
            {
                if $cc !~~ /US/ {
                    '<p class="recovered"><span>' ~ fmtnum($chart2data<recovered>) ~ '</span><sup>recovered</sup></p>'
                }
                else {''}
            }
            <p class="failed"><span>{fmtnum($chart2data<failed>)}</span><sup>failed</sup></p>
            <p class="active"><span>{fmtnum($chart2data<active>)}</span><sup>active</sup></p>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
            <p>The height of a single bar is the total number of people suffered from Coronavirus in {$proper-country-name}{$without-str} and confirmed to be infected. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
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
            <p>This graph shows the speed of growth (in %) over time in {$proper-country-name}{$without-str}. The main three parameters are the number of confirmed cases, the number of recoveries and failures. The orange line is the speed of changing of the number of active cases (i.e., of those, who are still ill).</p>
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
            <!--p>Note 1. In calculations, the 3-day moving average is used.</p-->
            <p>Note. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreases, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that less cases registered today than yesterday.</p>
        </div>

        <div id="block11">
            <a name="table"></a>
            <h1>Raw Daily Numbers</h1>
            $daily-table
        </div>

        $continent-list
        $country-list

        HTML

    my $url;
    if $exclude {
        my @parts = $exclude.lc.split('/');
        $url = '/' ~ @parts[0] ~ '/-' ~ @parts[1];
    }
    else {
        $url = '/' ~ $cc.lc;
    }

    html-template($url, "Coronavirus in {$proper-country-name}{$without-str}", $content);
}

sub generate-countries-stats(%countries, %per-day, %totals, %daily-totals) is export {
    say 'Generating countries data...';

    my %chart5data = countries-first-appeared(%countries, %per-day, %totals, %daily-totals);
    my $countries-appeared = countries-appeared-this-day(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

    my $percent = sprintf('%.1f', 100 * %chart5data<current-n> / %chart5data<total-countries>);

    my $content = qq:to/HTML/;
        <h1>Coronavirus in different countries</h1>

        <div id="block5">
            <h2>Number of Countries Affected</h2>
            <p>%chart5data<current-n> countires are affected, which is {$percent}&thinsp;\% from the total %chart5data<total-countries> countries.</p>
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
            <h2>Countries Appeared This Day</h2>
            <p>This list gives you the overview of when the first confirmed case was reported in the given country. Or, you can see here, which countries entered the chart in the recent days. The number in parentheses is the number of confirmed cases in that country on that date.</p>
            $countries-appeared
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/countries', 'Coronavirus in different countries', $content);
}

sub generate-per-capita-stats(%countries, %per-day, %totals, %daily-totals) is export {
    say 'Generating per-capita data...';

    my $N = 100;
    my $chart4data = countries-per-capita(%countries, %per-day, %totals, %daily-totals, limit => $N);
    my $chart14data = countries-per-capita(%countries, %per-day, %totals, %daily-totals, limit => $N, param => 'failed');

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

    my $content = qq:to/HTML/;
        <h1>Coronavirus per million of population</h1>
        <p>Sorted by <a href="#confirmed">confirmed cases</a> | by <a href="#failed">failed cases</a></p>

        <div id="block4">
            <a name="confirmed"></a>
            <h2>Top $N confirmations per million</h2>
            <p>This graph shows the number of affected people per each million of the population. The length of a bar per country is proportional to the number of confirmed cases per million.</p>
            <p>The $N most affected countries with more than one million of population are shown only. </p>
            <div style="height: {$N * 1.9}ex">
                <canvas id="Chart4"></canvas>
            </div>
            <script>
                var ctx4 = document.getElementById('Chart4').getContext('2d');
                chart[4] = new Chart(ctx4, $chart4data);
            </script>
        </div>

        <div id="block14">
            <a name="failed"></a>
            <h2>Top $N failures per million</h2>
            <p>This graph shows the relative number of people who could not recover from the disease. The data are the same as on the <a href="#confirmed">graph above</a> but sorted by the number of failures.</p>
            <p>The $N most affected countries with more than one million of population are shown only. </p>
            <div style="height: {$N * 1.9}ex">
                <canvas id="Chart14"></canvas>
            </div>
            <script>
                var ctx14 = document.getElementById('Chart14').getContext('2d');
                chart[14] = new Chart(ctx14, $chart14data);
            </script>
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/per-million', 'Coronavirus per million of population', $content);
}

sub generate-continent-stats($cont, %countries, %per-day, %totals, %daily-totals) is export {
    say "Generating continent $cont...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, :$cont);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, :$cont);
    my %chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, :$cont);

    my $chart7data = daily-speed(%countries, %per-day, %totals, %daily-totals, :$cont);

    my $population = %chart3<population>;
    my $daily-table = daily-table($chart2data, $population);

    my $country-list = country-list(%countries, :$cont);
    my $continent-list = continent-list($cont);

    my $percent-str = %chart3<percent> ~ '&thinsp;%';
    my $population-str = $population.round() ~ ' million';

    my $continent-name = %continents{$cont};
    my $continent-url = $continent-name.lc.subst(' ', '-');

    my $content = qq:to/HTML/;
        <h1>Coronavirus in {$continent-name}</h1>

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">{$percent-str}</div>
            <p>This is the part of confirmed infection cases against the total $population-str of its population.</p>
            <div class="affected">
                {
                    if $chart2data<confirmed> {
                        'Affected 1 of every ' ~ fmtnum((1_000_000 * $population / $chart2data<confirmed>).round())
                    }
                    else {
                        'Nobody affected'
                    }
                }
            </div>
            <div class="failed">
                {
                    if $chart2data<failed> {
                        'Failed to recover 1 of every ' ~ fmtnum((1_000_000 * $population / $chart2data<failed>).round())
                    }
                }
            </div>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in {$continent-name}.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block9">
            <a name="raw"></a>
            <h2>Raw Numbers on {fmtdate($chart2data<date>)}</h2>
            <p class="confirmed"><span>{fmtnum($chart2data<confirmed>)}</span><sup>confirmed</sup></p>
            <p class="recovered"><span>{fmtnum($chart2data<recovered>)}</span><sup>recovered</sup></p>
            <p class="failed"><span>{fmtnum($chart2data<failed>)}</span><sup>failed</sup></p>
            <p class="active"><span>{fmtnum($chart2data<active>)}</span><sup>active</sup></p>
        </div>

        <div id="block3">
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
            <p>This graph shows the speed of growth (in %) over time in {$continent-name}. The main three parameters are the number of confirmed cases, the number of recoveries and failures. The orange line is the speed of changing of the number of active cases (i.e., of those, who are still ill).</p>
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
            <!--p>Note 1. In calculations, the 3-day moving average is used.</p-->
            <p>Note. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreases, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that less cases registered today than yesterday.</p>
        </div>

        <div id="block11">
            <a name="table"></a>
            <h1>Raw Daily Numbers</h1>
            $daily-table
        </div>

        $continent-list
        $country-list

        HTML

    html-template("/$continent-url", "Coronavirus in $continent-name", $content);
}

sub generate-china-level-stats(%countries, %per-day, %totals, %daily-totals) is export {
    say 'Generating stats vs China...';

    my $chart6data = countries-vs-china(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

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
            <p>The almost-horizontal red line in the bottom part of the graph line displays <a href="/cn">China</a>. The number of confirmed infections in China almost stopped growing. Note the top line reflecting the most suffered province of China, <a href="/cn/hb">Hubei</a>, where the spread is also almost stopped.</p>
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
            <p>1. Note that only countries with more than 1 million population are taken into account. The smaller countries such as <a href="/va">Vatican</a> or <a href="/sm">San Marino</a> would have shown too high nimbers due to their small population.</p>
            <p>2. The line for the country is drawn only if it reaches at least 85% of the corresponding maximum parameter in China.</p>
            <script>
                var ctx6 = document.getElementById('Chart6').getContext('2d');
                chart[6] = new Chart(ctx6, $chart6data);
            </script>
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/vs-china', 'Countries vs China', $content);
}

sub generate-continent-graph(%countries, %per-day, %totals, %daily-totals) is export {
    my $chart8data = continent-joint-graph(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

    my $content = qq:to/HTML/;
        <h1>Coronavirus Spread over the Continents</h1>

        <div id="block3">
            <h2>Active Cases Timeline</h2>
            <p>This bar chart displays the timeline of the number of active cases (thus, confirmed minus failed to recovered minus recovered). The gold bars are those reflecting <a href="/asia">Asia</a> (mostly, <a href="/cn">China</a>). The blue bars correspond to the number of active cases in <a href="/europe">Europe</a>.</p>
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
                chart[8] = new Chart(ctx8, $chart8data);
            </script>
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/continents', 'Coronavirus over the Continents', $content);
}

sub generate-scattered-age(%countries, %per-day, %totals, %daily-totals) is export {
    say "Generating cases vs age...";

    my $chart11data = scattered-age-graph(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

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

        $continent-list
        $country-list

        HTML

    html-template('/vs-age', 'Coronavirus vs Life Expectancy', $content);
}

sub generate-overview(%countries, %per-day, %totals, %daily-totals) is export {
    say "Generating dashboard overview...";

    my %delta;
    my %confirmed;
    my %failed;
    my @max;

    my @dates = %daily-totals.keys.sort;
    my $days = @dates.elems - 2;

    my @display-dates;

    my @dashboard;

    for 2 .. $days + 1 -> $day {
        my $day-max = 0;

        @display-dates.push("'" ~ fmtdate(@dates[$day]) ~ "'");

        my @recent-dates = %daily-totals.keys.sort[$day - 1, $day];

        for %per-day.keys -> $cc {
            next if $cc ~~ /'/'/;

            my $prev = %per-day{$cc}{@recent-dates[0]};
            my $curr = %per-day{$cc}{@recent-dates[1]};

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
        for %countries.sort: *.value<country> -> $c {
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

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

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

        $continent-list
        $country-list

        HTML

    html-template('/overview', 'Coronavirus World Overview Dashboard', $content);
}

sub generate-js-countries(%countries, %per-day, %totals, %daily-totals) is export {
    say "Generating a new JS country list...";

    my @countries;
    for %countries.sort: *.value<country> -> $c {
        my $cc = $c.key;
        next if $cc ~~ /'/'/;
        next unless %per-day{$cc};

        my $country = $c.value<country>;
        $country ~~ s:g/\'/\\'/;

        @countries.push("['$cc','$country']");
    }

    for %countries.sort: *.value<country> -> $c {
        my $cc = $c.key;
        next unless $cc ~~ /'/'/;
        next unless %per-day{$cc};

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
