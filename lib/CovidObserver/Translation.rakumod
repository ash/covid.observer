unit module CovidObserver::Translation;

use CovidObserver::DB;

constant %languages is export =
    ru => 'Russian';

sub translate($path, $html is copy) is export {
    $html ~~ s/ '<LANGUAGE lang="en">' .*? '</LANGUAGE>'//;
    $html ~~ s/'<LANGUAGE' .*? '>'//;
    $html ~~ s/'</LANGUAGE>'//;

    my @phrases = find-strings($html);

    # state %t;
    my %t;

    for %languages.keys -> $language {
        if %t{$language}:!exists {
            my $filename = "./translations/$language.csv";

            my %translations;
            add-geo-translations(%translations, $language);

            if $filename.IO.e {
                for $filename.IO.lines() -> $line {
                    my ($original, $translation) = $line.split("\t");
                    %translations{$original} = $translation // '';
                }

                my %untranslated;
                for @phrases -> $phrase {
                    if %translations{$phrase}:!exists {
                        say "UNTRANSLATED ($language): $phrase";
                        %untranslated{$phrase} = 1;
                    }
                    elsif !%translations{$phrase} {
                        say "EMPTY TRANSLATION ($language): $phrase";
                    }
                }

                if %untranslated.keys {
                    my $fh = $filename.IO.open(:a);
                    for %untranslated.keys.sort -> $phrase {
                        $fh.say: $phrase;
                    }
                    $fh.close();
                    say %untranslated.keys.elems ~ " untranslated phrase(s) added to $language";
                }
            }
            else {
                my $fh = $filename.IO.open(:w);
                for @phrases -> $phrase {
                    $fh.say: $phrase;
                    %translations{$phrase} = '';
                }
                $fh.close();
            }

            %t{$language} = %translations;
        }

        my $translated = substitute-translations($html, %t{$language});

        $translated ~~ s/ '<body' /<body lang="$language"/;
        $translated ~~ s:g! '/LNG' !/.ru/!;

        my $local-path = "$path/.$language";
        mkdir("www$local-path");
        my $filepath = "./www$local-path/index.html";
        my $io = $filepath.IO;
        my $fh = $io.open(:w);
        $fh.say: $translated;
        $fh.close;
    }
}

sub add-geo-translations(%translations, $language) {
    my $sth = dbh.prepare('select country, name_ru, name_in_ru from countries');
    $sth.execute();

    for $sth.allrows() -> @row {
        my ($country, $name_ru, $name_in_ru) = @row;

        %translations{$country} = $name_ru;
        %translations{"in $country"} = $name_in_ru;
        %translations{"in the $country"} = $name_in_ru;
    }
    $sth.finish();
}

sub find-strings($html) {
    my @matches = $html ~~ m:g/
        '<' (\w+) <-[ > ]>* '>'
            (<-[ < ]>+)
    /;

    my %phrase;
    for @matches -> $match {
        my $tag = ~$match[0];
        next if $tag ~~ /script/;

        my $content = ~$match[1];
        next unless $content ~~ /<alpha>/;

        my $copy = $content;
        $copy ~~ s:g/'&' <alpha>+ ';'/ /;
        next unless $copy ~~ /<alpha>/;

        my $trimmed = $content.trim;

        my $n = 0;
        $trimmed ~~ s:g/ '｢' .*? '｣' /{ '｢' ~ ++$n ~ '｣' }/;
        for $/.map: ~* -> $value is copy {
            $value ~~ s:g/'&' <alpha>+ ';'/ /;
            next unless $value ~~ /<alpha>/;

            $value ~~ s:g/ '｢' | '｣' //;
            $value ~~ s:g/\s\s+/ /;

            %phrase{$value} = 1;
        }

        %phrase{$trimmed} = 1;        
    }

    return %phrase.keys.sort;
}

sub substitute-translations($html is copy, %translations) {
    $html ~~ s:g/
        ($<tag> = '<' \w+ <-[ > ]>* '>')
        ($<content> = <-[ < ]>+)
    /{
        my $tag = ~$/[0];
        my $content = ~$/[1];

        if $tag !~~ /^ '<script' / {
            $content ~~ /^ (\s*) /;
            my $before = $/[0] // '';

            $content ~~ / (\s*) $/;
            my $after = $/[0] // '';

            $content.=trim();
            $content ~~ s:g/\s\s+/ /;

            my $n = 0;
            $content ~~ s:g/ '｢' .*? '｣' /{ '｢' ~ ++$n ~ '｣' }/;
            my $translation = %translations{$content} || $content;

            if $/.elems {
                $n = 0;
                for $/.map: ~* -> $value is copy {
                    if $value ~~ /<alpha>/ {
                        $value ~~ s:g/ <[｢｣]> //;
                        $value = %translations{$value} // $value;
                    }

                    ++$n;
                    $translation ~~ s:g/ '｢' $n '｣' /$value/;
                }
                $translation ~~ s:g/ '｢' | '｣' //;
            }

            if $translation ~~ / \d<[,.]>\d / {
                $translation ~~ s:g/ (\d) ',' (\d) /$0'$1/;
                $translation ~~ s:g/ (\d) '.' (\d) /$0,$1/;
                $translation ~~ s:g/ (\d) \' (\d) /$0.$1/;
            }

            $tag ~ $before ~ $translation ~ $after
        }
        else {
            $tag ~ $content
        }
    }/;

    $html ~~ s:g/ '[*' ('/'? <alpha>+ .*? ) '*]' /<$0>/;

    return $html;
}
