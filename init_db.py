"""Boshlang'ich foydalanuvchi va talaba ma'lumotlarini yaratadi.

Ishga tushirish:
    python init_db.py

01_schema.sql, 02_indexes_views.sql va 03_seed.sql Supabase SQL Editor'da
allaqachon bajarilgan bo'lishi kerak.
"""
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from dotenv import load_dotenv
load_dotenv()

from werkzeug.security import generate_password_hash
import db

DEMO_USERS = [
    # (email, parol, rol, talaba_data — None bo'lsa talaba qo'shilmaydi)
    ("admin@grant.uz",     "admin123",     "admin",     None),
    ("moderator@grant.uz", "moderator123", "moderator", None),
    ("aliyor@grant.uz",    "talaba123",    "talaba", {
        "ism": "Aliyor", "familiya": "Karimov", "otasining_ismi": "Akmalovich",
        "jshshir": "12345678901234", "tugilgan_sana": "2003-05-15", "jins": "erkak",
        "telefon": "+998901234567", "manzil": "Toshkent sh., Yunusobod tumani",
        "universitet_id": 1, "fakultet_id": 1, "kurs": 3, "gpa": 4.20,
    }),
    ("madina@grant.uz",    "talaba123",    "talaba", {
        "ism": "Madina", "familiya": "Yusupova", "otasining_ismi": "Bahromqizi",
        "jshshir": "12345678901235", "tugilgan_sana": "2002-09-22", "jins": "ayol",
        "telefon": "+998901234568", "manzil": "Toshkent sh., Chilonzor tumani",
        "universitet_id": 1, "fakultet_id": 2, "kurs": 4, "gpa": 4.65,
    }),
    ("sardor@grant.uz",    "talaba123",    "talaba", {
        "ism": "Sardor", "familiya": "Toshev", "otasining_ismi": "Olimovich",
        "jshshir": "12345678901236", "tugilgan_sana": "2004-01-08", "jins": "erkak",
        "telefon": "+998901234569", "manzil": "Samarqand sh.",
        "universitet_id": 4, "fakultet_id": 8, "kurs": 2, "gpa": 3.85,
    }),
    ("nigora@grant.uz",    "talaba123",    "talaba", {
        "ism": "Nigora", "familiya": "Egamberdieva", "otasining_ismi": "Toshqulqizi",
        "jshshir": "12345678901237", "tugilgan_sana": "2003-11-30", "jins": "ayol",
        "telefon": "+998901234570", "manzil": "Toshkent sh.",
        "universitet_id": 3, "fakultet_id": 6, "kurs": 3, "gpa": 4.90,
    }),
]

DEMO_ARIZALAR = [
    # (talaba_email, ariza_turi, dastur_nomi, holat)
    ("aliyor@grant.uz", "grant",      "Prezident granti",          "yuborilgan"),
    ("madina@grant.uz", "grant",      "Erasmus+ stipendiyasi",     "tasdiqlangan"),
    ("madina@grant.uz", "stipendiya", "Prezident stipendiyasi",    "korib_chiqilmoqda"),
    ("sardor@grant.uz", "stipendiya", "Davlat stipendiyasi",       "rad_etilgan"),
    ("nigora@grant.uz", "grant",      "Qizlar uchun maxsus grant", "tasdiqlangan"),
    ("nigora@grant.uz", "stipendiya", "Prezident stipendiyasi",    "yuborilgan"),
]


def seed_users() -> dict[str, int]:
    """Foydalanuvchilar va talabalarni yaratadi. Email->user_id qaytaradi."""
    email_to_id: dict[str, int] = {}

    for email, parol, rol, talaba in DEMO_USERS:
        existing = db.fetch_one("SELECT id FROM foydalanuvchilar WHERE email = %s", (email,))
        if existing:
            print(f"  [skip] {email} allaqachon mavjud")
            email_to_id[email] = existing["id"]
            continue

        user = db.execute_returning("""
            INSERT INTO foydalanuvchilar (email, parol_hash, rol)
            VALUES (%s, %s, %s) RETURNING id
        """, (email, generate_password_hash(parol), rol))
        user_id = user["id"]
        email_to_id[email] = user_id
        print(f"  [+] foydalanuvchi: {email} ({rol})")

        if talaba:
            db.execute("""
                INSERT INTO talabalar (
                    foydalanuvchi_id, ism, familiya, otasining_ismi, jshshir,
                    tugilgan_sana, jins, telefon, manzil,
                    universitet_id, fakultet_id, kurs, gpa
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                user_id, talaba["ism"], talaba["familiya"], talaba["otasining_ismi"],
                talaba["jshshir"], talaba["tugilgan_sana"], talaba["jins"],
                talaba["telefon"], talaba["manzil"],
                talaba["universitet_id"], talaba["fakultet_id"],
                talaba["kurs"], talaba["gpa"],
            ))
            print(f"      talaba ma'lumotlari qo'shildi")

    return email_to_id


def seed_arizalar(email_to_id: dict[str, int]) -> None:
    admin = db.fetch_one("SELECT id FROM foydalanuvchilar WHERE email = 'admin@grant.uz'")
    admin_id = admin["id"] if admin else None

    for email, tur, dastur_nomi, holat in DEMO_ARIZALAR:
        user_id = email_to_id.get(email)
        if not user_id:
            continue
        talaba = db.fetch_one("SELECT id FROM talabalar WHERE foydalanuvchi_id = %s", (user_id,))
        if not talaba:
            continue

        if tur == "grant":
            obj = db.fetch_one("SELECT id FROM grantlar      WHERE nomi = %s", (dastur_nomi,))
            obj_col, obj_val = "grant_id", obj["id"] if obj else None
        else:
            obj = db.fetch_one("SELECT id FROM stipendiyalar WHERE nomi = %s", (dastur_nomi,))
            obj_col, obj_val = "stipendiya_id", obj["id"] if obj else None

        if not obj:
            print(f"  [warn] '{dastur_nomi}' topilmadi, ariza qo'shilmadi")
            continue

        existing = db.fetch_one(
            f"SELECT id FROM arizalar WHERE talaba_id = %s AND {obj_col} = %s",
            (talaba["id"], obj_val),
        )
        if existing:
            continue

        korib = admin_id if holat in ("tasdiqlangan", "rad_etilgan", "korib_chiqilmoqda") else None
        izoh  = {"tasdiqlangan": "Tasdiqlandi", "rad_etilgan": "Talablarga javob bermaydi"}.get(holat)

        db.execute(f"""
            INSERT INTO arizalar (talaba_id, ariza_turi, {obj_col}, holat, korib_chiqdi_id, izoh)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (talaba["id"], tur, obj_val, holat, korib, izoh))
        print(f"  [+] ariza: {email} -> {dastur_nomi} ({holat})")


def main():
    print(">> Bazaga ulanish tekshirilmoqda...")
    try:
        db.fetch_one("SELECT 1")
        print("   OK\n")
    except Exception as e:
        print(f"   XATO: {e}", file=sys.stderr)
        sys.exit(1)

    print(">> Foydalanuvchilar yaratilmoqda...")
    email_to_id = seed_users()

    print("\n>> Demo arizalar yaratilmoqda...")
    seed_arizalar(email_to_id)

    print("\n>> Tayyor! Endi saytga kirib ko'rishingiz mumkin:")
    print("     admin@grant.uz / admin123")
    print("     aliyor@grant.uz / talaba123")
    print("     madina@grant.uz / talaba123")


if __name__ == "__main__":
    main()
