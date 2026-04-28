-- =====================================================================
-- Grant va Stipendiyalar Boshqaruvi Tizimi
-- 01_schema.sql — JADVALLAR, MUNOSABATLAR VA CHEKLOVLAR
-- =====================================================================
-- Bu skript bazani noldan qayta yaratadi. EHTIYOT BO'LING — barcha
-- mavjud ma'lumotlar o'chiriladi! Faqat birinchi marta ishga tushirishda
-- yoki test paytida bajaring.
--
-- Ishga tushirish: Supabase Dashboard → SQL Editor → bu faylni yopishtiring → RUN
-- =====================================================================

-- ----- Mavjud obyektlarni o'chirish (toza boshlash uchun) ------------
DROP TABLE IF EXISTS ariza_holati_tarixi CASCADE;
DROP TABLE IF EXISTS hujjatlar CASCADE;
DROP TABLE IF EXISTS arizalar CASCADE;
DROP TABLE IF EXISTS stipendiyalar CASCADE;
DROP TABLE IF EXISTS grantlar CASCADE;
DROP TABLE IF EXISTS talabalar CASCADE;
DROP TABLE IF EXISTS foydalanuvchilar CASCADE;
DROP TABLE IF EXISTS fakultetlar CASCADE;
DROP TABLE IF EXISTS universitetlar CASCADE;

DROP TYPE IF EXISTS rol_turi CASCADE;
DROP TYPE IF EXISTS jins_turi CASCADE;
DROP TYPE IF EXISTS ariza_holati CASCADE;
DROP TYPE IF EXISTS ariza_turi CASCADE;
DROP TYPE IF EXISTS stipendiya_turi CASCADE;

-- =====================================================================
-- ENUM TIPLAR (cheklangan qiymatlar uchun)
-- =====================================================================
CREATE TYPE rol_turi          AS ENUM ('admin', 'moderator', 'talaba');
CREATE TYPE jins_turi         AS ENUM ('erkak', 'ayol');
CREATE TYPE ariza_holati      AS ENUM ('yuborilgan', 'korib_chiqilmoqda', 'tasdiqlangan', 'rad_etilgan');
CREATE TYPE ariza_turi        AS ENUM ('grant', 'stipendiya');
CREATE TYPE stipendiya_turi   AS ENUM ('davlat', 'nomli', 'maxsus', 'sotsial');

-- =====================================================================
-- 1. UNIVERSITETLAR
-- =====================================================================
CREATE TABLE universitetlar (
    id              BIGSERIAL PRIMARY KEY,
    nomi            VARCHAR(255) NOT NULL UNIQUE,
    qisqa_nomi      VARCHAR(50)  NOT NULL,
    shahar          VARCHAR(100) NOT NULL,
    tashkil_yili    SMALLINT     CHECK (tashkil_yili BETWEEN 1800 AND 2100),
    veb_sayt        VARCHAR(255),
    yaratilgan      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  universitetlar IS 'Universitetlar ro''yxati';
COMMENT ON COLUMN universitetlar.qisqa_nomi IS 'Masalan: TATU, TDPU';

-- =====================================================================
-- 2. FAKULTETLAR (universitetga tegishli)
-- =====================================================================
CREATE TABLE fakultetlar (
    id              BIGSERIAL PRIMARY KEY,
    universitet_id  BIGINT NOT NULL REFERENCES universitetlar(id) ON DELETE CASCADE,
    nomi            VARCHAR(255) NOT NULL,
    qisqa_nomi      VARCHAR(50),
    yaratilgan      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Bir universitetda bir xil nomli fakultet bo'lmasligi kerak
    CONSTRAINT uq_fakultet UNIQUE (universitet_id, nomi)
);

COMMENT ON TABLE fakultetlar IS 'Universitetlarning fakultetlari (1:N munosabat)';

-- =====================================================================
-- 3. FOYDALANUVCHILAR (autentifikatsiya uchun)
-- =====================================================================
CREATE TABLE foydalanuvchilar (
    id              BIGSERIAL PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    parol_hash      VARCHAR(255) NOT NULL,
    rol             rol_turi     NOT NULL DEFAULT 'talaba',
    aktiv           BOOLEAN      NOT NULL DEFAULT TRUE,
    ohirgi_kirish   TIMESTAMPTZ,
    yaratilgan      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

COMMENT ON TABLE foydalanuvchilar IS 'Tizim foydalanuvchilari (admin/moderator/talaba)';
COMMENT ON COLUMN foydalanuvchilar.parol_hash IS 'Werkzeug PBKDF2 hash, hech qachon ochiq parol saqlanmaydi';

-- =====================================================================
-- 4. TALABALAR (foydalanuvchi profili — 1:1)
-- =====================================================================
CREATE TABLE talabalar (
    id                BIGSERIAL PRIMARY KEY,
    foydalanuvchi_id  BIGINT NOT NULL UNIQUE REFERENCES foydalanuvchilar(id) ON DELETE CASCADE,
    ism               VARCHAR(100) NOT NULL,
    familiya          VARCHAR(100) NOT NULL,
    otasining_ismi    VARCHAR(100),
    jshshir           CHAR(14)     UNIQUE,
    tugilgan_sana     DATE         NOT NULL,
    jins              jins_turi    NOT NULL,
    telefon           VARCHAR(20),
    manzil            TEXT,
    universitet_id    BIGINT NOT NULL REFERENCES universitetlar(id) ON DELETE RESTRICT,
    fakultet_id       BIGINT NOT NULL REFERENCES fakultetlar(id)    ON DELETE RESTRICT,
    kurs              SMALLINT     NOT NULL CHECK (kurs BETWEEN 1 AND 6),
    gpa               NUMERIC(3,2) CHECK (gpa BETWEEN 0 AND 5.00),
    yaratilgan        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Talaba 16 yoshdan kichik bo'lmasligi kerak
    CONSTRAINT chk_yosh CHECK (tugilgan_sana <= CURRENT_DATE - INTERVAL '16 years')
);

COMMENT ON TABLE  talabalar IS 'Talabalarning shaxsiy ma''lumotlari';
COMMENT ON COLUMN talabalar.jshshir IS 'Jismoniy shaxsning shaxsiy identifikatsiya raqami';
COMMENT ON COLUMN talabalar.gpa IS 'Akademik o''zlashtirish (0.00 dan 5.00 gacha)';

-- =====================================================================
-- 5. GRANTLAR
-- =====================================================================
CREATE TABLE grantlar (
    id                  BIGSERIAL PRIMARY KEY,
    nomi                VARCHAR(255) NOT NULL,
    tavsif              TEXT,
    beruvchi_tashkilot  VARCHAR(255) NOT NULL,
    summa               NUMERIC(15,2) NOT NULL CHECK (summa > 0),
    valyuta             CHAR(3) NOT NULL DEFAULT 'UZS',
    minimal_gpa         NUMERIC(3,2) DEFAULT 3.00 CHECK (minimal_gpa BETWEEN 0 AND 5),
    minimal_kurs        SMALLINT DEFAULT 1 CHECK (minimal_kurs BETWEEN 1 AND 6),
    maksimal_kurs       SMALLINT DEFAULT 6 CHECK (maksimal_kurs BETWEEN 1 AND 6),
    jins_talab          jins_turi,
    ariza_boshlanishi   DATE NOT NULL,
    ariza_tugashi       DATE NOT NULL,
    aktiv               BOOLEAN NOT NULL DEFAULT TRUE,
    yaratilgan          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_kurs_oraliq CHECK (minimal_kurs <= maksimal_kurs),
    CONSTRAINT chk_sana        CHECK (ariza_boshlanishi < ariza_tugashi)
);

COMMENT ON COLUMN grantlar.jins_talab IS 'NULL — har ikkala jins ham arz qila oladi';
COMMENT ON COLUMN grantlar.summa IS 'Grant umumiy summasi (bir martalik to''lov)';

-- =====================================================================
-- 6. STIPENDIYALAR
-- =====================================================================
CREATE TABLE stipendiyalar (
    id                BIGSERIAL PRIMARY KEY,
    nomi              VARCHAR(255) NOT NULL,
    tavsif            TEXT,
    tur               stipendiya_turi NOT NULL,
    oylik_summa       NUMERIC(15,2) NOT NULL CHECK (oylik_summa > 0),
    minimal_gpa       NUMERIC(3,2) DEFAULT 3.50 CHECK (minimal_gpa BETWEEN 0 AND 5),
    davomiyligi_oy    SMALLINT NOT NULL DEFAULT 12 CHECK (davomiyligi_oy > 0),
    aktiv             BOOLEAN NOT NULL DEFAULT TRUE,
    yaratilgan        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN stipendiyalar.tur IS 'davlat=Prezident/Davlat, nomli=Beruniy/Navoiy, maxsus=fakultet, sotsial=ehtiyojmandlar uchun';

-- =====================================================================
-- 7. ARIZALAR (asosiy biznes-jadval)
-- =====================================================================
CREATE TABLE arizalar (
    id                    BIGSERIAL PRIMARY KEY,
    talaba_id             BIGINT NOT NULL REFERENCES talabalar(id) ON DELETE CASCADE,
    ariza_turi            ariza_turi NOT NULL,
    grant_id              BIGINT REFERENCES grantlar(id)      ON DELETE SET NULL,
    stipendiya_id         BIGINT REFERENCES stipendiyalar(id) ON DELETE SET NULL,
    holat                 ariza_holati NOT NULL DEFAULT 'yuborilgan',
    ariza_matni           TEXT,
    topshirilgan_sana     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    korib_chiqilgan_sana  TIMESTAMPTZ,
    korib_chiqdi_id       BIGINT REFERENCES foydalanuvchilar(id) ON DELETE SET NULL,
    izoh                  TEXT,
    yaratilgan            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ariza turi grant bo'lsa grant_id majburiy, stipendiya bo'lsa stipendiya_id majburiy
    CONSTRAINT chk_ariza_obyekt CHECK (
        (ariza_turi = 'grant'      AND grant_id      IS NOT NULL AND stipendiya_id IS NULL) OR
        (ariza_turi = 'stipendiya' AND stipendiya_id IS NOT NULL AND grant_id      IS NULL)
    ),

    -- Bir talaba bir grantga/stipendiyaga faqat bir marta ariza topshira oladi
    CONSTRAINT uq_ariza_grant      UNIQUE (talaba_id, grant_id),
    CONSTRAINT uq_ariza_stipendiya UNIQUE (talaba_id, stipendiya_id)
);

COMMENT ON TABLE arizalar IS 'Talabalarning grant/stipendiyaga arizalari';

-- =====================================================================
-- 8. HUJJATLAR (arizaga ilova qilingan fayllar)
-- =====================================================================
CREATE TABLE hujjatlar (
    id            BIGSERIAL PRIMARY KEY,
    ariza_id      BIGINT NOT NULL REFERENCES arizalar(id) ON DELETE CASCADE,
    nomi          VARCHAR(255) NOT NULL,
    fayl_yoli     VARCHAR(500) NOT NULL,
    fayl_olchami  BIGINT CHECK (fayl_olchami > 0),
    yuklangan     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN hujjatlar.fayl_yoli IS 'Supabase Storage yoki lokal yo''l';

-- =====================================================================
-- 9. ARIZA HOLATI TARIXI (audit log — TRIGGER avtomatik to'ldiradi)
-- =====================================================================
CREATE TABLE ariza_holati_tarixi (
    id                BIGSERIAL PRIMARY KEY,
    ariza_id          BIGINT NOT NULL REFERENCES arizalar(id) ON DELETE CASCADE,
    eski_holat        ariza_holati,
    yangi_holat       ariza_holati NOT NULL,
    ozgartiruvchi_id  BIGINT REFERENCES foydalanuvchilar(id) ON DELETE SET NULL,
    izoh              TEXT,
    ozgartirilgan     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ariza_holati_tarixi IS 'Arizalarning holat o''zgarish tarixi (TRIGGER bilan to''ldiriladi)';

-- =====================================================================
-- TUGADI
-- =====================================================================
-- Keyingi qadam: 02_indexes_views.sql ni ishga tushiring
-- =====================================================================
