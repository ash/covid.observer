// Compile as:
// g++ -std=c++17 days.cpp

#include<iostream>
#include<map>
#include<string>
#include<vector>
#include<fstream>

using namespace std;

typedef map<string, vector<int>> series;

#include "series.cpp"

int main() {

    for (auto &c : confirmed) {
        string cc = c.first;

        cout << cc;

        vector<int> dC = confirmed[cc];
        vector<int> dF = failed[cc];
        vector<int> dR = recovered[cc];

        int days = dC.size();
        if (dC.size() != dF.size() || dC.size() != dR.size() || dF.size() != dR.size()) {
            cout << cc << " Data not adjusted\n";
            return 1;
        }

        int min = 0;
        int minNf = 0;
        int minNr = 0;

        const int maxNf = 20;
        const int maxNr = 30;

        int firstDay;
        for (firstDay = 0; firstDay != days && !dC[firstDay]; firstDay++);
        if (days - firstDay < 15) {
            cout << endl;
            continue;
        }

        for (int Nf = 5; Nf != maxNf; Nf++) {
            for (int Nr = Nf; Nr != maxNr; Nr++) {
                double distance = 0;
                for (int day = 0; day != days; day++) {
                    int iF = day + Nf;
                    int iR = day + Nr;

                    if (iF >= days - 4 || iR >= days - 4) {
                        break;
                    }

                    int realDeltaC = dC[day]
                        ?  dC[day]
                        : (dC[day-1] + dC[day+1]) / 2
                    ;

                    int estimatedDeltaC = dF[iF] + dR[iR];

                    double diff = realDeltaC - estimatedDeltaC;
                    distance += diff * diff;
                }

                // cout << Nf << "\t" << Nr << "\t" << distance << endl;
                if (!min || min > distance) {
                    min = distance;
                    minNf = Nf;
                    minNr = Nr;
                }
            }
        }

        cout << " " << minNf << " " << minNr << endl;

        ofstream out;
        out.open(cc);

        double distance = 0;        
        for (int day = 0; day != days; day++) {
            int iF = day + minNf;
            int iR = day + minNr;

            if (iF >= days - 4 || iR >= days - 4) {
                break;
            }

            int realDeltaC = dC[day]
                ?  dC[day]
                : (dC[day-1] + dC[day+1]) / 2
            ;

            int estimatedDeltaC = dF[iF] + dR[iR];

            double diff = realDeltaC - estimatedDeltaC;
            distance += diff * diff;

            out << day << " " << realDeltaC << " " << estimatedDeltaC << endl;
        }

        out.close();
    }
}

