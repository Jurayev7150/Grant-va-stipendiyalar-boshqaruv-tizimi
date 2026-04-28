# Grant va Stipendiyalar Boshqaruvi Tizimi

**Ma'lumotlar bazasi fani** bo'yicha mustaqil ish loyihasi.

Bu tizim universitet talabalari uchun grant va stipendiyalarni boshqarishga moljallangan veb-ilova hisoblanadi. Talabalar ariza topshiradi, administrator esa arizalarni ko'rib chiqadi va tasdiqlaydi/rad etadi.

## Texnologiyalar

| Qism | Texnologiya |
|------|-------------|
| Backend | Python 3.11 + Flask 3.0 |
| Ma'lumotlar bazasi | PostgreSQL (Supabase'da hostlangan) |
| ORM/Driver | psycopg2 (toza SQL bilan ishlash uchun) |
| Frontend | HTML + Bootstrap 5 + Jinja2 |
| Autentifikatsiya | Flask-Login + Werkzeug (parol hash) |
| Deploy | Render (Web Service) |

## Ma'lumotlar bazasi tuzilmasi

Loyihada **8 ta jadval** mavjud:

1. `universitetlar` — universitetlar ro'yxati
2. `fakultetlar` — universitetga tegishli fakultetlar
3. `foydalanuvchilar` — tizim foydalanuvchilari (admin, talaba)
4. `talabalar` — talabalar ma'lumotlari
5. `grantlar` — mavjud grant dasturlari
6. `stipendiyalar` — mavjud stipendiya turlari
7. `arizalar` — talabalarning grant/stipendiyaga arizalari
8. `hujjatlar` — arizaga ilova qilingan fayllar
9. `ariza_holati_tarixi` — ariza holati o'zgarish tarixi (audit log)

Qo'shimcha:
- `INDEX`lar tezkor qidiruv uchun
- `VIEW`lar (`v_aktiv_arizalar`, `v_talaba_statistikasi`)
- `TRIGGER`lar (ariza holati o'zgarganda tarixga yozish)
- `FUNCTION`lar (statistika hisoblash uchun)

Schema fayli: [`database/01_schema.sql`](database/01_schema.sql)

## Lokal ishga tushirish

```bash
# 1. Repo'ni klon qiling
git clone https://github.com/Jurayev7150/Grant-va-stipendiyalar-boshqaruv-tizimi.git
cd Grant-va-stipendiyalar-boshqaruv-tizimi

# 2. Virtual environment yarating
python -m venv venv
# Windows:
venv\Scripts\activate
# Linux/Mac:
source venv/bin/activate

# 3. Paketlarni o'rnating
pip install -r requirements.txt

# 4. .env faylini sozlang
cp .env.example .env
# .env ichidagi qiymatlarni o'zingiznikiga moslang

# 5. Bazani tayyorlang
# Supabase Dashboard → SQL Editor'ga o'ting va quyidagi fayllarni ketma-ket bajaring:
# - database/01_schema.sql
# - database/02_indexes_views.sql
# - database/03_seed.sql

# 6. Saytni ishga tushiring
python app.py
```

Sayt: http://localhost:5000

## Render'da deploy qilish

1. https://dashboard.render.com'ga kiring
2. **New Web Service** → GitHub repo'ni tanlang
3. Sozlamalar:
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `gunicorn app:app --bind 0.0.0.0:$PORT --workers 2`
4. **Environment Variables** qismida `.env` ichidagi barcha o'zgaruvchilarni kiriting
5. **Create Web Service**

## Loyiha tuzilmasi

```
.
├── app.py                    # Flask asosiy fayli
├── db.py                     # PostgreSQL ulanish
├── requirements.txt          # Python paketlari
├── Procfile                  # Render uchun start buyrug'i
├── render.yaml               # Render blueprint
├── database/
│   ├── 01_schema.sql         # CREATE TABLE'lar
│   ├── 02_indexes_views.sql  # INDEX, VIEW, TRIGGER
│   ├── 03_seed.sql           # Boshlang'ich ma'lumotlar
│   └── 04_queries.sql        # Namuna SQL so'rovlar (himoya uchun)
├── templates/                # HTML shablonlar
└── static/                   # CSS, JS, rasmlar
```

## Mualliflar

Toshkent davlat universiteti talabalari, "Ma'lumotlar bazasi" fanidan mustaqil ish.

## Litsenziya

Ta'lim maqsadida bepul foydalanish mumkin.
