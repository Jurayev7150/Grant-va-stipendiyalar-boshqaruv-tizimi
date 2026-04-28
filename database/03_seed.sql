-- =====================================================================
-- 03_seed.sql — BOSHLANG'ICH MA'LUMOTLAR (test/demo uchun)
-- =====================================================================
-- Bu faylda faqat foydalanuvchidan mustaqil ma'lumotlar bor:
-- universitetlar, fakultetlar, grantlar, stipendiyalar.
--
-- Foydalanuvchilar (admin, talabalar) va ularga bog'liq ma'lumotlar
-- (arizalar) Python skripti orqali yaratiladi:
--      python init_db.py
-- Sababi: parollar Werkzeug bilan to'g'ri hashlanishi kerak.
-- =====================================================================

-- ----- Universitetlar ------------------------------------------------
INSERT INTO universitetlar (nomi, qisqa_nomi, shahar, tashkil_yili, veb_sayt) VALUES
('Toshkent axborot texnologiyalari universiteti', 'TATU',  'Toshkent', 1955, 'https://tuit.uz'),
('Toshkent davlat pedagogika universiteti',       'TDPU',  'Toshkent', 1935, 'https://tdpu.uz'),
('O''zbekiston Milliy universiteti',              'OzMU',  'Toshkent', 1918, 'https://nuu.uz'),
('Samarqand davlat universiteti',                  'SamDU', 'Samarqand', 1927, 'https://samdu.uz');

-- ----- Fakultetlar --------------------------------------------------
INSERT INTO fakultetlar (universitet_id, nomi, qisqa_nomi) VALUES
(1, 'Kompyuter injiniringi',              'KI'),
(1, 'Dasturiy injiniring',                'DI'),
(1, 'Telekommunikatsiya texnologiyalari', 'TT'),
(2, 'Matematika va informatika',          'MI'),
(2, 'Filologiya',                          'FIL'),
(3, 'Fizika',                              'FIZ'),
(3, 'Kimyo',                               'KIM'),
(4, 'Iqtisod',                             'IQT');

-- ----- Grantlar ------------------------------------------------------
INSERT INTO grantlar (nomi, tavsif, beruvchi_tashkilot, summa, valyuta,
                      minimal_gpa, minimal_kurs, maksimal_kurs, jins_talab,
                      ariza_boshlanishi, ariza_tugashi) VALUES
('Prezident granti',
 'O''zbekiston Respublikasi Prezidentining iqtidorli yoshlar uchun granti',
 'O''zbekiston Respublikasi Prezidenti devoni',
 50000000.00, 'UZS', 4.50, 2, 6, NULL, '2026-01-01', '2026-12-31'),
('Beruniy nomidagi grant',
 'Aniq fanlar bo''yicha tadqiqot olib boruvchi talabalar uchun',
 'O''zbekiston Fanlar akademiyasi',
 30000000.00, 'UZS', 4.00, 3, 4, NULL, '2026-03-01', '2026-08-31'),
('Qizlar uchun maxsus grant',
 'STEM yo''nalishlarida ta''lim olayotgan qizlar uchun',
 'BMTTD',
 25000000.00, 'UZS', 3.80, 1, 6, 'ayol', '2026-02-01', '2026-07-31'),
('Erasmus+ stipendiyasi',
 'Yevropada bir semestr o''qish uchun grant',
 'Yevropa Ittifoqi',
 60000000.00, 'UZS', 4.20, 2, 4, NULL, '2026-04-01', '2026-09-30');

-- ----- Stipendiyalar -------------------------------------------------
INSERT INTO stipendiyalar (nomi, tavsif, tur, oylik_summa, minimal_gpa, davomiyligi_oy) VALUES
('Davlat stipendiyasi',         'A''lochi talabalar uchun davlat stipendiyasi',  'davlat',  850000.00,  4.00,  5),
('Prezident stipendiyasi',      'Eng iqtidorli talabalar uchun',                'davlat',  2000000.00, 4.80, 12),
('Beruniy nomidagi stipendiya', 'Aniq fanlar bo''yicha',                        'nomli',   1500000.00, 4.50, 10),
('Sotsial yordam stipendiyasi', 'Ehtiyojmand oilalar farzandlari uchun',         'sotsial', 600000.00,  3.00, 12);

-- =====================================================================
-- TUGADI
-- Endi Python skriptini ishga tushiring: python init_db.py
-- =====================================================================
