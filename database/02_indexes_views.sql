-- =====================================================================
-- 02_indexes_views.sql — INDEKSLAR, VIEWLAR, TRIGGERLAR, FUNKSIYALAR
-- =====================================================================
-- 01_schema.sql bajarilgandan keyin shuni ishga tushiring.
-- =====================================================================

-- =====================================================================
-- INDEKSLAR (so'rovlarni tezlashtirish uchun)
-- =====================================================================

-- Foydalanuvchini email bo'yicha qidirish (UNIQUE allaqachon indeks yaratadi,
-- shuning uchun aktiv foydalanuvchilarni ajratib qidiruvchi qisman indeks):
CREATE INDEX idx_foydalanuvchilar_aktiv ON foydalanuvchilar(aktiv) WHERE aktiv = TRUE;

-- Talabalarni universitet va fakultet bo'yicha guruhlash uchun:
CREATE INDEX idx_talabalar_universitet ON talabalar(universitet_id);
CREATE INDEX idx_talabalar_fakultet    ON talabalar(fakultet_id);

-- GPA bo'yicha saralash/filtrlash (yuqori GPA talabalarni topish):
CREATE INDEX idx_talabalar_gpa ON talabalar(gpa DESC NULLS LAST);

-- Arizalarni talaba va holat bo'yicha qidirish (eng tez-tez ishlatiladigan):
CREATE INDEX idx_arizalar_talaba ON arizalar(talaba_id);
CREATE INDEX idx_arizalar_holat  ON arizalar(holat);

-- Arizalarni sana bo'yicha tartiblash:
CREATE INDEX idx_arizalar_topshirilgan ON arizalar(topshirilgan_sana DESC);

-- Faqat aktiv grantlarni tez topish (qisman indeks — joy tejaydi):
CREATE INDEX idx_grantlar_aktiv      ON grantlar(aktiv, ariza_tugashi)      WHERE aktiv = TRUE;
CREATE INDEX idx_stipendiyalar_aktiv ON stipendiyalar(aktiv)                 WHERE aktiv = TRUE;

-- Composite indeks: talaba + holat (talabaning ariza holatlarini ko'rish):
CREATE INDEX idx_arizalar_talaba_holat ON arizalar(talaba_id, holat);

-- Audit log uchun:
CREATE INDEX idx_tarix_ariza ON ariza_holati_tarixi(ariza_id, ozgartirilgan DESC);

-- =====================================================================
-- VIEWLAR (murakkab SO'ROVLARNI soddalashtirish uchun)
-- =====================================================================

-- 1-VIEW: Aktiv arizalar to'liq ma'lumot bilan
CREATE OR REPLACE VIEW v_aktiv_arizalar AS
SELECT
    a.id                  AS ariza_id,
    a.ariza_turi,
    a.holat,
    a.topshirilgan_sana,
    t.id                  AS talaba_id,
    (t.familiya || ' ' || t.ism) AS talaba_fio,
    t.gpa,
    t.kurs,
    u.qisqa_nomi          AS universitet,
    f.nomi                AS fakultet,
    COALESCE(g.nomi, s.nomi)  AS dastur_nomi,
    COALESCE(g.summa, s.oylik_summa) AS summa
FROM arizalar a
JOIN talabalar      t ON t.id = a.talaba_id
JOIN universitetlar u ON u.id = t.universitet_id
JOIN fakultetlar    f ON f.id = t.fakultet_id
LEFT JOIN grantlar       g ON g.id = a.grant_id
LEFT JOIN stipendiyalar  s ON s.id = a.stipendiya_id
WHERE a.holat IN ('yuborilgan', 'korib_chiqilmoqda');

COMMENT ON VIEW v_aktiv_arizalar IS 'Hali tasdiqlash/rad etilmagan arizalar (admin paneli uchun)';

-- 2-VIEW: Har bir talaba uchun arizalar statistikasi
CREATE OR REPLACE VIEW v_talaba_statistikasi AS
SELECT
    t.id   AS talaba_id,
    (t.familiya || ' ' || t.ism) AS fio,
    t.gpa,
    COUNT(a.id)                                                   AS jami_arizalar,
    COUNT(*) FILTER (WHERE a.holat = 'tasdiqlangan')              AS tasdiqlangan,
    COUNT(*) FILTER (WHERE a.holat = 'rad_etilgan')               AS rad_etilgan,
    COUNT(*) FILTER (WHERE a.holat IN ('yuborilgan','korib_chiqilmoqda')) AS kutilmoqda
FROM talabalar t
LEFT JOIN arizalar a ON a.talaba_id = t.id
GROUP BY t.id, t.familiya, t.ism, t.gpa;

-- 3-VIEW: Grant statistikasi (ko'rgan/tasdiqlangan arizalar)
CREATE OR REPLACE VIEW v_grant_statistikasi AS
SELECT
    g.id,
    g.nomi,
    g.summa,
    g.aktiv,
    g.ariza_tugashi,
    COUNT(a.id)                                       AS jami_arizalar,
    COUNT(*) FILTER (WHERE a.holat = 'tasdiqlangan')  AS tasdiqlangan_arizalar,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE a.holat = 'tasdiqlangan')
        / NULLIF(COUNT(a.id), 0),
        2
    ) AS qabul_foizi
FROM grantlar g
LEFT JOIN arizalar a ON a.grant_id = g.id
GROUP BY g.id, g.nomi, g.summa, g.aktiv, g.ariza_tugashi;

-- 4-VIEW: Universitet bo'yicha statistika
CREATE OR REPLACE VIEW v_universitet_statistikasi AS
SELECT
    u.id,
    u.qisqa_nomi          AS universitet,
    u.shahar,
    COUNT(DISTINCT t.id)  AS talabalar_soni,
    COUNT(a.id)           AS arizalar_soni,
    ROUND(AVG(t.gpa), 2)  AS ortacha_gpa
FROM universitetlar u
LEFT JOIN talabalar t  ON t.universitet_id = u.id
LEFT JOIN arizalar  a  ON a.talaba_id      = t.id
GROUP BY u.id, u.qisqa_nomi, u.shahar;

-- =====================================================================
-- FUNKSIYALAR
-- =====================================================================

-- Talabaning yoshini hisoblash
CREATE OR REPLACE FUNCTION f_talaba_yoshi(p_tugilgan_sana DATE)
RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM AGE(CURRENT_DATE, p_tugilgan_sana))::INTEGER;
END;
$$;

COMMENT ON FUNCTION f_talaba_yoshi IS 'Tug''ilgan sanadan yoshni hisoblaydi';

-- Talaba grant talablariga javob beradimi?
CREATE OR REPLACE FUNCTION f_grantga_mos(p_talaba_id BIGINT, p_grant_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_gpa NUMERIC; v_kurs INT; v_jins jins_turi;
    v_min_gpa NUMERIC; v_min_kurs INT; v_max_kurs INT; v_jins_talab jins_turi;
    v_aktiv BOOLEAN; v_tugashi DATE;
BEGIN
    SELECT gpa, kurs, jins INTO v_gpa, v_kurs, v_jins
      FROM talabalar WHERE id = p_talaba_id;

    SELECT minimal_gpa, minimal_kurs, maksimal_kurs, jins_talab, aktiv, ariza_tugashi
      INTO v_min_gpa, v_min_kurs, v_max_kurs, v_jins_talab, v_aktiv, v_tugashi
      FROM grantlar WHERE id = p_grant_id;

    IF NOT v_aktiv OR v_tugashi < CURRENT_DATE THEN RETURN FALSE; END IF;
    IF v_gpa IS NULL OR v_gpa < v_min_gpa            THEN RETURN FALSE; END IF;
    IF v_kurs < v_min_kurs OR v_kurs > v_max_kurs    THEN RETURN FALSE; END IF;
    IF v_jins_talab IS NOT NULL AND v_jins_talab <> v_jins THEN RETURN FALSE; END IF;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION f_grantga_mos IS 'Talaba grant talablariga mosligini tekshiradi';

-- =====================================================================
-- TRIGGERLAR
-- =====================================================================

-- 1-TRIGGER: Ariza holati o'zgarganda audit log'ga yozish
CREATE OR REPLACE FUNCTION trg_ariza_audit_func()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Faqat holat o'zgarganda yozamiz (boshqa maydonlar emas)
    IF (TG_OP = 'UPDATE' AND OLD.holat IS DISTINCT FROM NEW.holat) THEN
        INSERT INTO ariza_holati_tarixi (
            ariza_id, eski_holat, yangi_holat, ozgartiruvchi_id, izoh
        ) VALUES (
            NEW.id, OLD.holat, NEW.holat, NEW.korib_chiqdi_id, NEW.izoh
        );
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO ariza_holati_tarixi (
            ariza_id, eski_holat, yangi_holat, ozgartiruvchi_id, izoh
        ) VALUES (
            NEW.id, NULL, NEW.holat, NULL, 'Ariza yaratildi'
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ariza_audit
AFTER INSERT OR UPDATE OF holat ON arizalar
FOR EACH ROW
EXECUTE FUNCTION trg_ariza_audit_func();

-- 2-TRIGGER: Holat tasdiqlangan/rad_etilgan'ga o'zgarsa, korib_chiqilgan_sana ni avtomatik qo'yish
CREATE OR REPLACE FUNCTION trg_korib_chiqilgan_sana_func()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.holat IN ('tasdiqlangan', 'rad_etilgan')
       AND (OLD.holat IS DISTINCT FROM NEW.holat)
       AND NEW.korib_chiqilgan_sana IS NULL THEN
        NEW.korib_chiqilgan_sana := NOW();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_korib_chiqilgan_sana
BEFORE UPDATE OF holat ON arizalar
FOR EACH ROW
EXECUTE FUNCTION trg_korib_chiqilgan_sana_func();

-- =====================================================================
-- TUGADI — Keyingi qadam: 03_seed.sql
-- =====================================================================
