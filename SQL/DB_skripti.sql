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
CREATE OR REPLACE FUNCTION LaskeHinta(IN p_auto_id INT, IN p_varaus_alkaa DATETIME, IN p_varaus_paattyy DATETIME)
RETURNS DECIMAL(8,2)
DETERMINISTIC
BEGIN
	DECLARE kokonaishinta DECIMAL(8,2);
	DECLARE paivien_maara int;
	DECLARE paivahinta DECIMAL(8,2);

	SET paivien_maara = DATEDIFF(p_varaus_paattyy, p_varaus_alkaa);
	SELECT auto.paivahinta INTO paivahinta
	FROM autot auto
	WHERE auto.auto_id = p_auto_id;

	SET kokonaishinta = paivahinta * paivien_maara;

	RETURN kokonaishinta;
END$$
DELIMITER ;

-- Tallennettu proseduuri (Stored Procedure): TeeVaraus
-- Proseduuri ottaa parametreina asiakkaan ID:n, auton ID:n, alkupäivän ja loppupäivän.
-- Transaktio: Proseduurin sisällä on käytettävä transaktiota (START TRANSACTION, COMMIT, ROLLBACK).
-- Logiikka: Tarkista ensin, onko auto vapaana kyseisenä ajankohtana.
-- Jos on, lisää rivi Varaukset-tauluun ja päivitä auton tila Autot-taulussa.
-- Jos auto on jo varattu, peruuta transaktio ja nosta virheilmoitus (SIGNAL SQLSTATE).
DELIMITER $$
CREATE OR REPLACE PROCEDURE TeeVaraus(IN p_asiakas_id INT, IN p_auto_id INT, IN p_varaus_alkaa DATETIME, IN p_varaus_paattyy DATETIME)
BEGIN
	DECLARE varauksien_maara INT;

	START TRANSACTION;


	SELECT COUNT(*) INTO varauksien_maara FROM Varaukset v
	WHERE v.auto_id = p_auto_id
	AND v.varaus_alkaa < p_varaus_paattyy
	AND v.varaus_paattyy > p_varaus_alkaa;

	IF varauksien_maara = 0 THEN

		INSERT INTO Varaukset(
		varaus_alkaa,
		varaus_paattyy,
		kokonaishinta,
		asiakas_id,
		auto_id

		) VALUES(
		p_varaus_alkaa,
		p_varaus_paattyy,
		LaskeHinta(p_auto_id, p_varaus_alkaa, p_varaus_paattyy),
		p_asiakas_id,
		p_auto_id
		);

		UPDATE Autot
		SET Tila = 'vuokralla'
		WHERE auto_id = p_auto_id;
		COMMIT;

	ELSE
		ROLLBACK;
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Auto on varattuna valittuna ajankohtana';

	END IF;

END$$
DELIMITER ;

-- Audit-loki (AFTER UPDATE):
-- Luo triggeri Autot-tauluun. Aina kun auton tila muuttuu arvoon 'huollossa', triggerin tulee automaattisesti lisätä tietue Loki-tauluun
-- (esim. "Auto [rekisterinumero] siirretty huoltoon").
DELIMITER $$
CREATE TRIGGER tr_au_autot_huollossa_loki_lisays
AFTER UPDATE ON Autot
FOR EACH ROW
BEGIN
	IF NEW.tila = 'huollossa' THEN
		INSERT INTO Loki(
		toimenpide,
		aikaleima,
		kenen_tekema
		)
		VALUES(
		CONCAT('Auto ', OLD.rekisterinumero, ' siirretty huoltoon.'),
		NOW(),
		CURRENT_USER
		);
	END IF;
END$$
DELIMITER ;

-- Turvatarkistus (BEFORE INSERT):
-- Luo triggeri Varaukset-tauluun, joka estää päällekkäiset varaukset tietokantatasolla.
-- Jos uusi varaus osuu aikavälille, jolloin auto on jo varattu, triggerin tulee pysäyttää operaatio ja palauttaa virhe.
DELIMITER $$
CREATE TRIGGER tr_bi_tarkista_onko_auto_varattu
BEFORE INSERT ON Varaukset
FOR EACH ROW
BEGIN
	DECLARE varauksien_maara INT;

	SELECT COUNT(*) INTO varauksien_maara FROM Varaukset v
	WHERE v.auto_id = NEW.auto_id
	AND v.varaus_alkaa < NEW.varaus_paattyy
	AND v.varaus_paattyy > NEW.varaus_alkaa;

	IF varauksien_maara > 0 THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Auto on varattuna valittuna ajankohtana';
	END IF;
END$$
DELIMITER ;