-- =====================================================================
-- 04_queries.sql — NAMUNA SO'ROVLAR (himoya paytida ko'rsatish uchun)
-- =====================================================================
-- Bu fayldagi so'rovlar Ma'lumotlar bazasi fanidagi turli mavzularni
-- namoyish qiladi: JOIN, GROUP BY, HAVING, oyna funksiyalari, CTE,
-- subso'rovlar, agregat funksiyalar, EXISTS, IN, UNION va h.k.
-- =====================================================================


-- ============================ 1. ASOSIY SELECT ========================
-- 1.1. Barcha aktiv grantlarni summa bo'yicha kamayish tartibida
SELECT id, nomi, summa, ariza_tugashi
FROM grantlar
WHERE aktiv = TRUE AND ariza_tugashi >= CURRENT_DATE
ORDER BY summa DESC;


-- 1.2. GPA 4.0 dan yuqori bo'lgan talabalar
SELECT familiya, ism, gpa, kurs
FROM talabalar
WHERE gpa > 4.00
ORDER BY gpa DESC;


-- ============================ 2. INNER JOIN ===========================
-- 2.1. Talabalar va ularning universitetlari
SELECT
    t.familiya || ' ' || t.ism AS fio,
    u.qisqa_nomi               AS universitet,
    f.nomi                     AS fakultet,
    t.kurs,
    t.gpa
FROM talabalar t
INNER JOIN universitetlar u ON u.id = t.universitet_id
INNER JOIN fakultetlar    f ON f.id = t.fakultet_id
ORDER BY t.gpa DESC;


-- ============================ 3. LEFT JOIN ============================
-- 3.1. Barcha talabalar va ularning arizalari soni (arizasi bo'lmaganlar ham)
SELECT
    t.familiya || ' ' || t.ism AS fio,
    COUNT(a.id)                AS arizalar_soni
FROM talabalar t
LEFT JOIN arizalar a ON a.talaba_id = t.id
GROUP BY t.id, t.familiya, t.ism
ORDER BY arizalar_soni DESC;


-- ============================ 4. AGREGAT + GROUP BY ===================
-- 4.1. Universitet bo'yicha o'rtacha GPA
SELECT
    u.qisqa_nomi          AS universitet,
    COUNT(t.id)           AS talabalar_soni,
    ROUND(AVG(t.gpa), 2)  AS ortacha_gpa,
    MAX(t.gpa)            AS eng_yuqori_gpa,
    MIN(t.gpa)            AS eng_past_gpa
FROM universitetlar u
LEFT JOIN talabalar t ON t.universitet_id = u.id
GROUP BY u.id, u.qisqa_nomi
ORDER BY ortacha_gpa DESC NULLS LAST;


-- 4.2. Holat bo'yicha arizalar soni
SELECT holat, COUNT(*) AS soni
FROM arizalar
GROUP BY holat
ORDER BY soni DESC;


-- ============================ 5. HAVING ===============================
-- 5.1. Eng kamida 2 ta ariza topshirgan talabalar
SELECT
    t.familiya || ' ' || t.ism AS fio,
    COUNT(a.id)                AS arizalar_soni
FROM talabalar t
JOIN arizalar a ON a.talaba_id = t.id
GROUP BY t.id, t.familiya, t.ism
HAVING COUNT(a.id) >= 2
ORDER BY arizalar_soni DESC;


-- ============================ 6. SUBSO'ROVLAR =========================
-- 6.1. Eng yuqori GPA li talaba
SELECT familiya, ism, gpa
FROM talabalar
WHERE gpa = (SELECT MAX(gpa) FROM talabalar);


-- 6.2. Hech qachon ariza topshirmagan talabalar
SELECT t.familiya, t.ism, t.gpa
FROM talabalar t
WHERE NOT EXISTS (
    SELECT 1 FROM arizalar a WHERE a.talaba_id = t.id
);


-- 6.3. O'rtachadan yuqori GPA li talabalar
SELECT familiya, ism, gpa
FROM talabalar
WHERE gpa > (SELECT AVG(gpa) FROM talabalar)
ORDER BY gpa DESC;


-- ============================ 7. CTE (WITH) ===========================
-- 7.1. Har bir universitetdan eng yuqori GPA li talaba
WITH eng_yaxshi_talaba AS (
    SELECT
        t.*,
        ROW_NUMBER() OVER (PARTITION BY t.universitet_id ORDER BY t.gpa DESC) AS rn
    FROM talabalar t
)
SELECT u.qisqa_nomi, e.familiya || ' ' || e.ism AS fio, e.gpa
FROM eng_yaxshi_talaba e
JOIN universitetlar u ON u.id = e.universitet_id
WHERE e.rn = 1;


-- ============================ 8. OYNA FUNKSIYALARI ====================
-- 8.1. Talabalarni GPA bo'yicha reyting
SELECT
    familiya || ' ' || ism AS fio,
    gpa,
    RANK()       OVER (ORDER BY gpa DESC) AS oddiy_rank,
    DENSE_RANK() OVER (ORDER BY gpa DESC) AS dense_rank,
    ROW_NUMBER() OVER (ORDER BY gpa DESC) AS qator_raqami
FROM talabalar;


-- 8.2. Har bir kurs uchun GPA bo'yicha persentil
SELECT
    familiya || ' ' || ism AS fio,
    kurs,
    gpa,
    NTILE(4) OVER (PARTITION BY kurs ORDER BY gpa DESC) AS chorak
FROM talabalar;


-- ============================ 9. CASE WHEN ============================
-- 9.1. GPA bo'yicha talabalarni darajalash
SELECT
    familiya || ' ' || ism AS fio,
    gpa,
    CASE
        WHEN gpa >= 4.50 THEN 'A''lochi'
        WHEN gpa >= 4.00 THEN 'Yaxshi'
        WHEN gpa >= 3.00 THEN 'Qoniqarli'
        ELSE 'Past'
    END AS daraja
FROM talabalar
ORDER BY gpa DESC;


-- ============================ 10. UNION ===============================
-- 10.1. Talaba arzlari (grant + stipendiya birga)
SELECT 'Grant' AS turi, g.nomi AS dastur_nomi, a.holat, a.topshirilgan_sana
FROM arizalar a JOIN grantlar g ON g.id = a.grant_id
WHERE a.talaba_id = 2

UNION ALL

SELECT 'Stipendiya', s.nomi, a.holat, a.topshirilgan_sana
FROM arizalar a JOIN stipendiyalar s ON s.id = a.stipendiya_id
WHERE a.talaba_id = 2

ORDER BY topshirilgan_sana DESC;


-- ============================ 11. VIEWLARDAN FOYDALANISH ==============
-- 11.1. Aktiv arizalar (ko'rib chiqilishi kutilayotgan)
SELECT * FROM v_aktiv_arizalar;

-- 11.2. Talaba statistikasi
SELECT * FROM v_talaba_statistikasi WHERE jami_arizalar > 0;

-- 11.3. Grant qabul foizi bo'yicha
SELECT * FROM v_grant_statistikasi WHERE qabul_foizi IS NOT NULL ORDER BY qabul_foizi DESC;


-- ============================ 12. FUNKSIYALARNI CHAQIRISH =============
-- 12.1. Talabaning yoshi
SELECT
    familiya || ' ' || ism AS fio,
    tugilgan_sana,
    f_talaba_yoshi(tugilgan_sana) AS yosh
FROM talabalar;

-- 12.2. Talaba grantga mos keladimi?
SELECT
    t.familiya || ' ' || t.ism AS talaba,
    g.nomi                      AS grant,
    f_grantga_mos(t.id, g.id)  AS mos_keladimi
FROM talabalar t
CROSS JOIN grantlar g
WHERE g.aktiv = TRUE
ORDER BY t.familiya, g.nomi;


-- ============================ 13. AUDIT LOG ===========================
-- 13.1. Bitta arizaning tarixi (TRIGGER yozgan)
SELECT
    aht.ozgartirilgan,
    aht.eski_holat,
    aht.yangi_holat,
    f.email     AS ozgartiruvchi,
    aht.izoh
FROM ariza_holati_tarixi aht
LEFT JOIN foydalanuvchilar f ON f.id = aht.ozgartiruvchi_id
WHERE aht.ariza_id = 2
ORDER BY aht.ozgartirilgan;


-- ============================ 14. TRANZAKSIYA NAMUNASI ================
-- 14.1. Ariza tasdiqlash (atomicity ko'rsatish uchun)
-- BEGIN;
--   UPDATE arizalar
--      SET holat = 'tasdiqlangan',
--          korib_chiqdi_id = 1,
--          izoh = 'Hammma talablarga javob beradi'
--    WHERE id = 1;
--
--   -- TRIGGER avtomatik ravishda ariza_holati_tarixi ga yozadi
--   -- Agar bu yerda xato bo'lsa, ROLLBACK qilamiz
-- COMMIT;


-- ============================ 15. EXPLAIN (indekslar samaradorligi) ===
-- 15.1. Indeks ishlatilayotganini tekshirish
EXPLAIN ANALYZE
SELECT * FROM arizalar WHERE holat = 'yuborilgan';
-- Natijada "Index Scan using idx_arizalar_holat" ko'rinishi kerak

-- =====================================================================
