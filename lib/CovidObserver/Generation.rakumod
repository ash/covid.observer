unit module CovidObserver::Generation;

use JSON::Tiny;

use CovidObserver::Population;
use CovidObserver::Statistics;
use CovidObserver::HTML;

sub generate-world-stats(%countries, %per-day, %totals, %daily-totals) is export {
    say 'Generating world data...';

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals);

    my $chart7data = daily-speed(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

    my $content = qq:to/HTML/;
        <h1>COVID-19 World Statistics</h1>

        <div id="block2">
            <h2>Affected World Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of confirmed infection cases against the total 7.8 billion of the world population.</p>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in the whole world.</p>
            <canvas id="Chart1"></canvas>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
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
            <p>The height of a single bar is the total number of people suffered from Coronavirus confirmed to be infected in the world. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                chart[2] = new Chart(ctx2, $chart2data);
            </script>
        </div>

        <div id="block7">
            <a name="speed"></a>
            <h2>Daily Speed</h2>
            <p>This graph shows the speed of growth (in %) over time. The main three parameters are the number of confirmed cases, the number of recoveries and failures. The orange line is the speed of changing of the number of active cases (i.e., of those, who are still ill).</p>
            <canvas id="Chart7"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale7" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale7" onclick="log_scale(this, 7)">
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
            <p>Note 1. In calculations, the 3-day moving average is used.</p>
            <p>Note 2. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreeses, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that less cases registered today than yesterday.</p>
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/', 'World statistics', $content);
}

sub generate-country-stats($cc, %countries, %per-day, %totals, %daily-totals) is export {
    say "Generating $cc...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, :$cc);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, :$cc);
    my $chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, :$cc);

    my $chart7data = daily-speed(%countries, %per-day, %totals, %daily-totals, :$cc);

    my $country-list = country-list(%countries, :$cc);
    my $continent-list = continent-list(%countries{$cc}<continent>);

    my $country-name = %countries{$cc}<country>;
    my $population = +%countries{$cc}<population>;
    my $population-str = $population <= 1
        ?? sprintf('%i thousand', (1000 * $population).round)
        !! sprintf('%i million', $population.round);

    my $proper-country-name = $country-name;
    $proper-country-name = "the $country-name" if $cc ~~ /[US|GB|NL|DO|CZ]$/;

    my $content = qq:to/HTML/;
        <h1>Coronavirus in {$proper-country-name}</h1>

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">$chart3&thinsp;%</div>
            <p>This is the part of confirmed infection cases against the total $population-str of its population.</p>
        </div>

        <div id="block1">
            <h2>Recovery Pie</h2>
            <canvas id="Chart1"></canvas>
            <p>The whole pie reflects the total number of confirmed cases of people infected by coronavirus in {$proper-country-name}.</p>
            <script>
                var ctx1 = document.getElementById('Chart1').getContext('2d');
                chart[1] = new Chart(ctx1, $chart1data);
            </script>
        </div>

        <div id="block3">
            <h2>Daily Flow</h2>
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
            <p>The height of a single bar is the total number of people suffered from Coronavirus in {$proper-country-name} and confirmed to be infected. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                chart[2] = new Chart(ctx2, $chart2data);
            </script>
        </div>

        <div id="block7">
            <a name="speed"></a>
            <h2>Daily Speed</h2>
            <p>This graph shows the speed of growth (in %) over time in {$proper-country-name}. The main three parameters are the number of confirmed cases, the number of recoveries and failures. The orange line is the speed of changing of the number of active cases (i.e., of those, who are still ill).</p>
            <canvas id="Chart7"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale7" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale7" onclick="log_scale(this, 7)">
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
            <p>Note 1. In calculations, the 3-day moving average is used.</p>
            <p>Note 2. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreeses, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that less cases registered today than yesterday.</p>
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/' ~ $cc.lc, "Coronavirus in {$proper-country-name}", $content);
}

sub generate-countries-stats(%countries, %per-day, %totals, %daily-totals) is export {
    say 'Generating countries data...';

    my %chart5data = countries-first-appeared(%countries, %per-day, %totals, %daily-totals);
    my $chart4data = countries-per-capita(%countries, %per-day, %totals, %daily-totals);
    my $countries-appeared = countries-appeared-this-day(%countries, %per-day, %totals, %daily-totals);

    my $country-list = country-list(%countries);
    my $continent-list = continent-list();

    my $percent = sprintf('%.1f', 100 * %chart5data<current-n> / %chart5data<total-countries>);

    my $content = qq:to/HTML/;
        <h1>Coronavirus in different countries</h1>

        <div id="block5">
            <h2>Number of Countires Affected</h2>
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

        <div id="block4">
            <h2>Top 30 Affected per Million</h2>
            <canvas id="Chart4"></canvas>
            <p>This graph shows the number of affected people per each million of the population. Countries with more than one million are shown only.</p>
            <script>
                var ctx4 = document.getElementById('Chart4').getContext('2d');
                chart[4] = new Chart(ctx4, $chart4data);
            </script>
        </div>

        $continent-list
        $country-list

        HTML

    html-template('/countries', 'Coronavirus in different countries', $content);
}

sub generate-continent-stats($cont, %countries, %per-day, %totals, %daily-totals) is export {
    say "Generating continent $cont...";

    my $chart1data = chart-pie(%countries, %per-day, %totals, %daily-totals, :$cont);
    my $chart2data = chart-daily(%countries, %per-day, %totals, %daily-totals, :$cont);
    my %chart3 = number-percent(%countries, %per-day, %totals, %daily-totals, :$cont);

    my $chart7data = daily-speed(%countries, %per-day, %totals, %daily-totals, :$cont);

    my $country-list = country-list(%countries, :$cont);
    my $continent-list = continent-list($cont);

    my $percent-str = %chart3<percent> ~ '&thinsp;%';
    my $population-str = %chart3<population>.round() ~ ' million';

    my $continent-name = %continents{$cont};
    my $continent-url = $continent-name.lc.subst(' ', '-');

    my $content = qq:to/HTML/;
        <h1>Coronavirus in {$continent-name}</h1>

        <div id="block2">
            <h2>Affected Population</h2>
            <div id="percent">{$percent-str}</div>
            <p>This is the part of confirmed infection cases against the total $population-str of its population.</p>
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

        <div id="block3">
            <h2>Daily Flow</h2>
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
            <p>The height of a single bar is the total number of people suffered from Coronavirus in $continent-name and confirmed to be infected. It includes three parts: those who could or could not recover and those who are currently in the active phase of the disease.</p>
            <script>
                var ctx2 = document.getElementById('Chart2').getContext('2d');
                chart[2] = new Chart(ctx2, $chart2data);
            </script>
        </div>

        <div id="block7">
            <a name="speed"></a>
            <h2>Daily Speed</h2>
            <p>This graph shows the speed of growth (in %) over time in {$continent-name}. The main three parameters are the number of confirmed cases, the number of recoveries and failures. The orange line is the speed of changing of the number of active cases (i.e., of those, who are still ill).</p>
            <canvas id="Chart7"></canvas>
            <p class="left">
                <label class="toggle-switchy" for="logscale7" data-size="xs" data-style="rounded" data-color="blue">
                    <input type="checkbox" id="logscale7" onclick="log_scale(this, 7)">
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
            <p>Note 1. In calculations, the 3-day moving average is used.</p>
            <p>Note 2. When the speed is positive, the number of cases grows every day. The line going down means that the speed decreeses, and while there may be more cases the next day, the disease spread is slowing down. If the speed goes below zero, that means that less cases registered today than yesterday.</p>
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
            <p>On this graph, you see how the fraction (in %) of the confirmed infection cases changes over time in different countries or the US states.</p>
            <p>The almost-horizontal red line displays China. The number of confirmed infections in China almost stopped growing.</p>
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
            <p>1. Note that only countries and US states with more than 1 million population are taken into account. The smaller countries such as <a href="/va">Vatican</a> or <a href="/sm">San Marino</a> would have shown too high nimbers due to their small population.</p>
            <p>2. The line for the country is drawn only if it reaches at least 75% of the corresponding maximum parameter in China.</p>
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
