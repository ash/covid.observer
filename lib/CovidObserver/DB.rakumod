unit module CovidObserver::DB;

use DBIish;

sub dbh() is export {
    state $dbh = DBIish.connect('mysql', :host<localhost>, :user<covid>, :password<covid>, :database<covid>);

    return $dbh;
}
