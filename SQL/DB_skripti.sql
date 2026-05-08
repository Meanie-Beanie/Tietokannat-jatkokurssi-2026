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

-- Asiakkaat -data
INSERT INTO Asiakkaat (etunimi,sukunimi,sahkoposti,ajokortin_numero)
VALUES
('Mikko', 'Virtanen', 'mikko.virtanen@email.fi', '123456'),
('Sanna', 'Korhonen', 'sanna.korhonen@email.fi', '234567'),
('Juhani', 'Mäkinen', 'juhani.makinen@email.fi', '345678'),
('Laura', 'Niemi', 'laura.niemi@email.fi', '456789'),
('Pekka', 'Hämäläinen','pekka.hamalainen@email.fi', '567890'),
('Erika', 'Leinonen', 'erika.leinonen@email.fi', '678901');

-- Autot -data
INSERT INTO Autot (rekisterinumero,merkki, malli,paivahinta,tila)
VALUES
('ABC-123', 'Toyota', 'Corolla', 45.00, 'vapaa'),
('DEF-456', 'Volkswagen', 'Golf', 55.00, 'vapaa'),
('GHI-789', 'Ford', 'Focus', 50.00, 'vapaa'),
('JKL-012', 'BMW', '3 Series', 95.00, 'vapaa'),
('MNO-345', 'Skoda', 'Octavia', 48.00, 'huollossa'),
('PQR-678', 'Volvo', 'V60', 80.00, 'vapaa');

-- Varaukset
INSERT INTO Varaukset (varaus_alkaa, varaus_paattyy, kokonaishinta, asiakas_id, auto_id)
VALUES
('2026-06-01', '2026-06-04', 135.00, 1, 1),
('2026-06-05', '2026-06-10', 275.00, 2, 2),
('2026-06-03', '2026-06-05', 100.00, 3, 3),
('2026-06-07', '2026-06-11', 380.00, 4, 4),
('2026-06-10', '2026-06-11', 45.00, 5, 1),
('2026-06-15', '2026-06-22', 560.00, 6, 6);

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
		INSERT INTO Loki(toimenpide, aikaleima,	kenen_tekema)
		VALUES(CONCAT('Auto ', OLD.rekisterinumero, ' siirretty huoltoon.'), NOW(),	CURRENT_USER);
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

-- Näkymä (View): v_AktiivisetVaraukset
-- Luo näkymä, joka yhdistää tietoa tauluista: se näyttää asiakkaan nimen (muttei ajokortin numeroa), auton merkin, rekisterinumeron ja varauksen aikavälin.
-- Näkymän tulee näyttää vain ne varaukset, jotka ovat tällä hetkellä käynnissä tai tulevaisuudessa.
CREATE VIEW v_AktiivisetVaraukset AS
SELECT CONCAT(asiakas.etunimi, " ", asiakas.sukunimi), a.merkki, a.rekisterinumero, v.varaus_alkaa, v.varaus_paattyy FROM varaukset v
JOIN autot a ON a.auto_id = v.auto_id
JOIN asiakkaat asiakas ON asiakas.asiakas_id = v.asiakas_id
WHERE  v.varaus_paattyy > NOW();


-- Luo rooli asiakaspalvelu.
-- Anna tälle roolille oikeus lukea (SELECT) ja lisätä (INSERT) tietoa Varaukset ja Asiakkaat -tauluihin, sekä oikeus ajaa proseduuri TeeVaraus.
CREATE ROLE IF NOT EXISTS 'asiakaspalvelu';
GRANT SELECT, INSERT ON GoAuto.Varaukset TO 'asiakaspalvelu';
GRANT SELECT, INSERT ON GoAuto.Asiakkaat TO 'asiakaspalvelu';
GRANT EXECUTE ON PROCEDURE GoAuto.TeeVaraus TO 'asiakaspalvelu';


-- Luo rooli mekaanikko. Anna tälle roolille oikeus päivittää (UPDATE) Autot-taulun tila-saraketta ja lukea v_AktiivisetVaraukset -näkymää.
CREATE ROLE IF NOT EXISTS 'mekaanikko';
GRANT UPDATE ON GoAuto.Autot TO 'mekaanikko';
GRANT SELECT ON  GoAuto.v_aktiivisetvaraukset TO 'mekaanikko';

-- Luo testikäyttäjät molemmille rooleille ja liitä roolit niihin (GRANT ROLE).
CREATE USER IF NOT EXISTS 'asiakaspalvelu'@'localhost.com' IDENTIFIED BY 'PASSWORD';
GRANT 'asiakaspalvelu' TO 'asiakaspalvelu'@'localhost.com';

CREATE USER IF NOT EXISTS 'mekaanikko'@'localhost.com' IDENTIFIED BY 'PASSWORD';
GRANT 'mekaniikko' TO 'mekaanikko'@'localhost.com';

-- Kirjoita kysely, joka etsii tietyn asiakkaan kaikki varaukset. Aja kysely EXPLAIN-komennon läpi ja ota tuloste talteen.
EXPLAIN SELECT v.asiakas_id, v.auto_id, v.varaus_alkaa, v.varaus_paattyy  FROM Varaukset v
JOIN Asiakkaat a ON v.asiakas_id = a.asiakas_id
WHERE v.asiakas_id = 1;


-- Luo tarvittava indeksi (CREATE INDEX), joka nopeuttaa tätä kyselyä (esim. asiakas_id ja varaus_alkaa -sarakkeisiin).
--Aja EXPLAIN uudelleen ja vertaa tuloksia dokumentaatiossasi.
CREATE INDEX idx_varaukset_asiakas_varaus_alkaa
ON Varaukset (asiakas_id, varaus_alkaa);

-- Huom: Varmista ensin, että MariaDB:n tapahtuma-ajastin on päällä: SET GLOBAL event_scheduler = ON;
SET GLOBAL event_scheduler = ON;

-- Luo tapahtuma PaivitaAutojenTilat, joka ajetaan automaattisesti kerran vuorokaudessa.
-- Tapahtuman tulee etsiä varaukset, jotka ovat päättyneet eilen, ja päivittää kyseisten autojen tila takaisin 'vapaa'-tilaan Autot-taulussa.
DELIMITER $$
CREATE EVENT PaivitaAutojenTilat
    ON SCHEDULE
      EVERY 1 DAY
    COMMENT 'Päättyneiden varauksien autot on laitettu vapaiksi.'
    DO
      BEGIN
		UPDATE tila
		JOIN Varaukset v ON v.auto_id = a.auto_id
		SET tila = 'vapaa'
		WHERE v.varaus_paattyy >= DATE_SUB(NOW(), INTERVAL 1 DAY);
      END $$
DELIMITER ;