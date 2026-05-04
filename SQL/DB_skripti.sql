CREATE DATABASE IF NOT EXISTS GoAuto;

USE GoAuto;

-- Asiakkaat (asiakas_id, etunimi, sukunimi, sahkoposti, ajokortin_numero)

Create Table Asiakkaat (
asiakas_id int AUTO_INCREMENT PRIMARY KEY,
etunimi varchar(100) NOT NULL,
sukunimi varchar (100) NOT NULL,
sahkoposti varchar(100) NOT NULL UNIQUE,
ajokortin_numero varchar(50) UNIQUE
);

-- Autot (auto_id, rekisterinumero, merkki, malli, paivahinta, tila [esim. 'vapaa', 'vuokralla', 'huollossa'])
-- Auton päivähinnan on oltava suurempi kuin nolla (CHECK).

Create Table Autot (
auto_id int AUTO_INCREMENT PRIMARY KEY,
rekisterinumero VARCHAR(20) NOT NULL UNIQUE,
merkki VARCHAR(50) NOT NULL,
malli VARCHAR(50) NOT NULL,
paivahinta DECIMAL(8,2) NOT NULL CHECK (paivahinta > 0),
tila ENUM('vapaa', 'vuokralla', 'huollossa') NOT NULL DEFAULT 'vapaa'
);


-- Varaukset (varaus_id, asiakas_id, auto_id, varaus_alkaa, varaus_paattyy, kokonaishinta)
-- Varauksen päättymispäivän on oltava sama tai myöhäisempi kuin alkamispäivä (CHECK).

Create Table Varaukset (
varaus_id int AUTO_INCREMENT PRIMARY KEY,
varaus_alkaa DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
varaus_paattyy DATETIME NOT NULL,
kokonaishinta decimal(8,2) NOT NULL,
asiakas_id int NOT NULL,
auto_id int NOT NULL,

CONSTRAINT chk_varaus_aika
CHECK (varaus_paattyy >= varaus_alkaa),

CONSTRAINT fk_asiakas_id
FOREIGN KEY (asiakas_id)
REFERENCES Asiakkaat(asiakas_id),

CONSTRAINT fk_auto_id
FOREIGN KEY (auto_id)
REFERENCES Autot(auto_id)
);


-- Loki (loki_id, toimenpide, aikaleima, kenen tekemä)

Create Table Loki(
loki_id int AUTO_INCREMENT PRIMARY KEY,
toimenpide VARCHAR(40) NOT NULL,
aikaleima DATETIME DEFAULT CURRENT_TIMESTAMP,
kenen_tekema VARCHAR(100) NOT NULL
);

-- Luo funktio, joka ottaa parametreina auton ID:n, varauksen alkupäivän ja loppupäivän.
-- Funktio laskee ja palauttaa varauksen kokonaishinnan (päivien määrä $\times$ auton päivähinta).
DELIMITER $$
CREATE OR REPLACE FUNCTION LaskeHinta(IN Auto_Id INT, IN Varaus_Alkaa DATETIME, IN Varaus_Paattyy DATETIME)
RETURNS DECIMAL(8,2)
DETERMINISTIC
BEGIN
	DECLARE kokonaishinta DECIMAL(8,2);
	DECLARE paivien_maara int;
	DECLARE paivahinta DECIMAL(8,2);

	SET paivien_maara = DATEDIFF(varaus_paattyy, varaus_alkaa);
	SELECT auto.paivahinta INTO paivahinta
	FROM autot auto
	WHERE auto.auto_id = Auto_Id;

	SET kokonaishinta = paivahinta * paivien_maara;

	RETURN kokonaishinta;
END$$
DELIMITER ;