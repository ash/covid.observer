var countries = [['asia','Asia'],['africa','Africa'],['europe','Europe'],['north-america','North America'],['south-america','South America'],['oceania','Oceania'],['AF','Afghanistan'],['AL','Albania'],['DZ','Algeria'],['AD','Andorra'],['AO','Angola'],['AI','Anguilla'],['AG','Antigua and Barbuda'],['AR','Argentina'],['AM','Armenia'],['AW','Aruba'],['AU','Australia'],['AT','Austria'],['AZ','Azerbaijan'],['BS','Bahamas'],['BH','Bahrain'],['BD','Bangladesh'],['BB','Barbados'],['BY','Belarus'],['BE','Belgium'],['BZ','Belize'],['BJ','Benin'],['BM','Bermuda'],['BT','Bhutan'],['BO','Bolivia'],['BQ','Bonaire, St. Eustatius & Saba'],['BA','Bosnia and Herzegovina'],['BW','Botswana'],['BR','Brazil'],['VG','British Virgin Islands'],['BN','Brunei Darussalam'],['BG','Bulgaria'],['BF','Burkina Faso'],['BI','Burundi'],['CV','Cabo Verde'],['KH','Cambodia'],['CM','Cameroon'],['CA','Canada'],['KY','Cayman Islands'],['CF','Central African Republic'],['TD','Chad'],['CL','Chile'],['CN','China'],['CO','Colombia'],['KM','Comoros'],['CG','Congo'],['CR','Costa Rica'],['HR','Croatia'],['CU','Cuba'],['CW','Curaçao'],['CY','Cyprus'],['CZ','Czechia'],['CD','Dem. Rep. of the Congo'],['DK','Denmark'],['DJ','Djibouti'],['DM','Dominica'],['DO','Dominican Republic'],['EC','Ecuador'],['EG','Egypt'],['SV','El Salvador'],['GQ','Equatorial Guinea'],['ER','Eritrea'],['EE','Estonia'],['SZ','Eswatini'],['ET','Ethiopia'],['FK','Falkland Islands'],['FO','Faroe Islands'],['FJ','Fiji'],['FI','Finland'],['FR','France'],['GF','French Guiana'],['PF','French Polynesia'],['GA','Gabon'],['GM','Gambia'],['GE','Georgia'],['DE','Germany'],['GH','Ghana'],['GI','Gibraltar'],['GR','Greece'],['GL','Greenland'],['GD','Grenada'],['GP','Guadeloupe'],['GU','Guam'],['GT','Guatemala'],['GN','Guinea'],['GW','Guinea-Bissau'],['GY','Guyana'],['HT','Haiti'],['VA','Holy See'],['HN','Honduras'],['HU','Hungary'],['IS','Iceland'],['IN','India'],['ID','Indonesia'],['IR','Iran'],['IQ','Iraq'],['IE','Ireland'],['IM','Isle of Man'],['IL','Israel'],['IT','Italy'],['JM','Jamaica'],['JP','Japan'],['JO','Jordan'],['KZ','Kazakhstan'],['KE','Kenya'],['XK','Kosovo'],['KW','Kuwait'],['KG','Kyrgyzstan'],['LA','Lao People\'s Dem. Rep.'],['LV','Latvia'],['LB','Lebanon'],['LS','Lesotho'],['LR','Liberia'],['LY','Libya'],['LI','Liechtenstein'],['LT','Lithuania'],['LU','Luxembourg'],['MG','Madagascar'],['MW','Malawi'],['MY','Malaysia'],['MV','Maldives'],['ML','Mali'],['MT','Malta'],['MH','Marshall Islands'],['MQ','Martinique'],['MR','Mauritania'],['MU','Mauritius'],['YT','Mayotte'],['MX','Mexico'],['MD','Moldova'],['MC','Monaco'],['MN','Mongolia'],['ME','Montenegro'],['MS','Montserrat'],['MA','Morocco'],['MZ','Mozambique'],['MM','Myanmar'],['NA','Namibia'],['NP','Nepal'],['NL','Netherlands'],['NC','New Caledonia'],['NZ','New Zealand'],['NI','Nicaragua'],['NE','Niger'],['NG','Nigeria'],['MK','North Macedonia'],['NO','Norway'],['OM','Oman'],['PK','Pakistan'],['PA','Panama'],['PG','Papua New Guinea'],['PY','Paraguay'],['PE','Peru'],['PH','Philippines'],['PL','Poland'],['PT','Portugal'],['PR','Puerto Rico'],['QA','Qatar'],['RO','Romania'],['RU','Russian Federation'],['RW','Rwanda'],['RE','Réunion'],['BL','Saint Barthélemy'],['KN','Saint Kitts and Nevis'],['LC','Saint Lucia'],['PM','Saint Pierre and Miquelon'],['WS','Samoa'],['SM','San Marino'],['ST','Sao Tome and Principe'],['SA','Saudi Arabia'],['SN','Senegal'],['RS','Serbia'],['SC','Seychelles'],['SL','Sierra Leone'],['SG','Singapore'],['SX','Sint Maarten'],['SK','Slovakia'],['SI','Slovenia'],['SB','Solomon Islands'],['SO','Somalia'],['ZA','South Africa'],['KR','South Korea'],['SS','South Sudan'],['ES','Spain'],['LK','Sri Lanka'],['PS','State of Palestine'],['SD','Sudan'],['SR','Suriname'],['SE','Sweden'],['CH','Switzerland'],['SY','Syrian Arab Republic'],['TW','Taiwan'],['TJ','Tajikistan'],['TZ','Tanzania'],['TH','Thailand'],['TL','Timor-Leste'],['TG','Togo'],['TT','Trinidad and Tobago'],['TN','Tunisia'],['TR','Turkey'],['TC','Turks and Caicos Islands'],['UG','Uganda'],['UA','Ukraine'],['AE','United Arab Emirates'],['GB','United Kingdom'],['US','United States of America'],['UY','Uruguay'],['UZ','Uzbekistan'],['VU','Vanuatu'],['VE','Venezuela'],['VN','Viet Nam'],['YE','Yemen'],['ZM','Zambia'],['ZW','Zimbabwe'],['US/AL','Alabama'],['US/AK','Alaska'],['RU/22','Altai Krai'],['RU/04','Altai Republic'],['RU/28','Amur Oblast'],['CN/AH','Anhui'],['US/AZ','Arizona'],['US/AR','Arkansas'],['RU/29','Arkhangelsk Oblast'],['RU/30','Astrakhan Oblast'],['CN/BJ','Beijing'],['RU/31','Belgorod Oblast'],['RU/32','Bryansk Oblast'],['US/CA','California'],['RU/20','Chechen Republic'],['RU/74','Chelyabinsk Oblast'],['CN/CQ','Chongqing'],['RU/87','Chukotka Autonomous Okrug'],['RU/21','Chuvash Republic'],['US/CO','Colorado'],['US/CT','Connecticut'],['US/DE','Delaware'],['US/DC','District of Columbia'],['US/FL','Florida'],['CN/FJ','Fujian'],['CN/GS','Gansu'],['US/GA','Georgia'],['US/GU','Guam'],['CN/GD','Guangdong'],['CN/GX','Guangxi Zhuangzu'],['CN/GZ','Guizhou'],['CN/HI','Hainan'],['US/HI','Hawaii'],['CN/HE','Hebei'],['CN/HL','Heilongjiang'],['CN/HA','Henan'],['CN/HK','Hong Kong'],['CN/HB','Hubei'],['CN/HN','Hunan'],['US/ID','Idaho'],['US/IL','Illinois'],['US/IN','Indiana'],['US/IA','Iowa'],['RU/38','Irkutsk Oblast'],['RU/37','Ivanovo Oblast'],['RU/79','Jewish Autonomous Oblast'],['CN/JS','Jiangsu'],['CN/JX','Jiangxi'],['CN/JL','Jilin'],['RU/07','Kabardino-Balkar Republic'],['RU/39','Kaliningrad Oblast'],['RU/40','Kaluga Oblast'],['RU/41','Kamchatka Krai'],['US/KS','Kansas'],['RU/09','Karachay-Cherkess Republic'],['RU/42','Kemerovo Oblast'],['US/KY','Kentucky'],['RU/27','Khabarovsk Krai'],['RU/86','Khanty–Mansi Autonomous Okrug – Yugra'],['RU/43','Kirov Oblast'],['RU/11','Komi Republic'],['RU/44','Kostroma Oblast'],['RU/23','Krasnodar Krai'],['RU/24','Krasnoyarsk Krai'],['RU/45','Kurgan Oblast'],['RU/46','Kursk Oblast'],['RU/47','Leningrad Oblast'],['CN/LN','Liaoning'],['RU/48','Lipetsk Oblast'],['US/LA','Louisiana'],['CN/MO','Macao'],['RU/49','Magadan Oblast'],['US/ME','Maine'],['RU/12','Mari El Republic'],['US/MD','Maryland'],['US/MA','Massachusetts'],['US/MI','Michigan'],['US/MN','Minnesota'],['US/MS','Mississippi'],['US/MO','Missouri'],['US/MT','Montana'],['RU/77','Moscow'],['RU/50','Moscow Oblast'],['RU/51','Murmansk Oblast'],['US/NE','Nebraska'],['CN/NM','Nei Mongol'],['RU/83','Nenets Autonomous Okrug'],['US/NV','Nevada'],['US/NH','New Hampshire'],['US/NJ','New Jersey'],['US/NM','New Mexico'],['US/NY','New York'],['CN/NX','Ningxia Huizi'],['RU/52','Nizhny Novgorod Oblast'],['US/NC','North Carolina'],['US/ND','North Dakota'],['RU/53','Novgorod Oblast'],['RU/54','Novosibirsk Oblast'],['US/OH','Ohio'],['US/OK','Oklahoma'],['RU/55','Omsk Oblast'],['US/OR','Oregon'],['RU/56','Orenburg Oblast'],['RU/57','Oryol Oblast'],['US/PA','Pennsylvania'],['RU/58','Penza Oblast'],['RU/59','Perm Krai'],['RU/25','Primorsky Krai'],['RU/60','Pskov Oblast'],['US/PR','Puerto Rico'],['CN/QH','Qinghai'],['RU/01','Republic of Adygea'],['RU/02','Republic of Bashkortostan'],['RU/03','Republic of Buryatia'],['RU/91','Republic of Crimea'],['RU/05','Republic of Dagestan'],['RU/06','Republic of Ingushetia'],['RU/08','Republic of Kalmykia'],['RU/10','Republic of Karelia'],['RU/19','Republic of Khakassia'],['RU/13','Republic of Mordovia'],['RU/15','Republic of North Ossetia-Alania'],['RU/16','Republic of Tatarstan'],['US/RI','Rhode Island'],['RU/61','Rostov Oblast'],['RU/62','Ryazan Oblast'],['RU/78','Saint Petersburg'],['RU/14','Sakha (Yakutia) Republic'],['RU/65','Sakhalin Oblast'],['RU/63','Samara Oblast'],['RU/64','Saratov Oblast'],['RU/92','Sevastopol'],['CN/SN','Shaanxi'],['CN/SD','Shandong'],['CN/SH','Shanghai'],['CN/SX','Shanxi'],['CN/SC','Sichuan'],['RU/67','Smolensk Oblast'],['US/SC','South Carolina'],['US/SD','South Dakota'],['RU/26','Stavropol Krai'],['RU/66','Sverdlovsk Oblast'],['CN/TW','Taiwan'],['RU/68','Tambov Oblast'],['US/TN','Tennessee'],['US/TX','Texas'],['CN/TJ','Tianjin'],['RU/70','Tomsk Oblast'],['RU/71','Tula Oblast'],['RU/17','Tuva Republic'],['RU/69','Tver Oblast'],['RU/72','Tyumen Oblast'],['RU/18','Udmurt Republic'],['RU/73','Ulyanovsk Oblast'],['US/UT','Utah'],['US/VT','Vermont'],['US/VI','Virgin Islands'],['US/VA','Virginia'],['RU/33','Vladimir Oblast'],['RU/34','Volgograd Oblast'],['RU/35','Vologda Oblast'],['RU/36','Voronezh Oblast'],['US/WA','Washington'],['US/WV','West Virginia'],['US/WI','Wisconsin'],['US/WY','Wyoming'],['CN/XJ','Xinjiang Uygur'],['CN/XZ','Xizang'],['RU/89','Yamalo-Nenets Autonomous Okrug'],['RU/76','Yaroslavl Oblast'],['CN/YN','Yunnan'],['RU/75','Zabaykalsky Krai'],['CN/ZJ','Zhejiang']];
