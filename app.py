"""Grant va Stipendiyalar Boshqaruvi Tizimi — Flask asosiy fayli."""
import os
from datetime import datetime
from functools import wraps

from dotenv import load_dotenv
load_dotenv()

from flask import (
    Flask, render_template, request, redirect, url_for, flash, session, abort
)
from werkzeug.security import generate_password_hash, check_password_hash

import db


# ====================================================================
# Flask sozlamalari
# ====================================================================
app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-secret-key-change-me")
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"


# ====================================================================
# Auth yordamchilari
# ====================================================================
def current_user():
    """Sessiyadagi foydalanuvchini bazadan olib keladi."""
    user_id = session.get("user_id")
    if not user_id:
        return None
    return db.fetch_one(
        "SELECT id, email, rol, aktiv FROM foydalanuvchilar WHERE id = %s AND aktiv = TRUE",
        (user_id,),
    )


def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not current_user():
            flash("Iltimos, avval tizimga kiring.", "warning")
            return redirect(url_for("kirish", next=request.path))
        return f(*args, **kwargs)
    return wrapper


def role_required(*roles):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            user = current_user()
            if not user:
                return redirect(url_for("kirish"))
            if user["rol"] not in roles:
                abort(403)
            return f(*args, **kwargs)
        return wrapper
    return decorator


@app.context_processor
def inject_user():
    return {"current_user": current_user(), "now": datetime.now()}


# ====================================================================
# Public routelar
# ====================================================================
@app.route("/")
def index():
    stats = db.fetch_one("""
        SELECT
            (SELECT COUNT(*) FROM talabalar)                                  AS talabalar,
            (SELECT COUNT(*) FROM grantlar      WHERE aktiv = TRUE)           AS grantlar,
            (SELECT COUNT(*) FROM stipendiyalar WHERE aktiv = TRUE)           AS stipendiyalar,
            (SELECT COUNT(*) FROM arizalar      WHERE holat = 'tasdiqlangan') AS tasdiqlangan
    """)
    grantlar = db.fetch_all("""
        SELECT id, nomi, summa, ariza_tugashi, beruvchi_tashkilot
        FROM grantlar
        WHERE aktiv = TRUE AND ariza_tugashi >= CURRENT_DATE
        ORDER BY ariza_tugashi ASC
        LIMIT 6
    """)
    return render_template("index.html", stats=stats, grantlar=grantlar)


@app.route("/grantlar")
def grantlar_list():
    rows = db.fetch_all("""
        SELECT g.*, vs.jami_arizalar, vs.qabul_foizi
        FROM grantlar g
        LEFT JOIN v_grant_statistikasi vs ON vs.id = g.id
        ORDER BY g.aktiv DESC, g.ariza_tugashi ASC
    """)
    return render_template("grantlar.html", grantlar=rows)


@app.route("/stipendiyalar")
def stipendiyalar_list():
    rows = db.fetch_all("SELECT * FROM stipendiyalar ORDER BY aktiv DESC, oylik_summa DESC")
    return render_template("stipendiyalar.html", stipendiyalar=rows)


# ====================================================================
# Autentifikatsiya
# ====================================================================
@app.route("/kirish", methods=["GET", "POST"])
def kirish():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        parol = request.form.get("parol", "")
        user = db.fetch_one(
            "SELECT id, email, parol_hash, rol, aktiv FROM foydalanuvchilar WHERE email = %s",
            (email,),
        )
        if not user or not user["aktiv"] or not check_password_hash(user["parol_hash"], parol):
            flash("Email yoki parol noto'g'ri.", "danger")
            return render_template("kirish.html"), 401

        session["user_id"] = user["id"]
        db.execute("UPDATE foydalanuvchilar SET ohirgi_kirish = NOW() WHERE id = %s", (user["id"],))
        flash(f"Xush kelibsiz, {user['email']}!", "success")

        if user["rol"] in ("admin", "moderator"):
            return redirect(url_for("admin_dashboard"))
        return redirect(url_for("panel"))

    return render_template("kirish.html")


@app.route("/royxat", methods=["GET", "POST"])
def royxat():
    universitetlar = db.fetch_all("SELECT id, nomi, qisqa_nomi FROM universitetlar ORDER BY nomi")
    fakultetlar    = db.fetch_all("SELECT id, universitet_id, nomi FROM fakultetlar ORDER BY nomi")

    if request.method == "POST":
        f = request.form
        try:
            email = f["email"].strip().lower()
            parol = f["parol"]
            if len(parol) < 6:
                raise ValueError("Parol kamida 6 ta belgidan iborat bo'lishi kerak")

            existing = db.fetch_one("SELECT id FROM foydalanuvchilar WHERE email = %s", (email,))
            if existing:
                raise ValueError("Bu email bilan foydalanuvchi mavjud")

            with db.cursor(commit=True) as cur:
                cur.execute(
                    "INSERT INTO foydalanuvchilar (email, parol_hash, rol) "
                    "VALUES (%s, %s, 'talaba') RETURNING id",
                    (email, generate_password_hash(parol)),
                )
                user_id = cur.fetchone()["id"]

                cur.execute("""
                    INSERT INTO talabalar (
                        foydalanuvchi_id, ism, familiya, otasining_ismi, jshshir,
                        tugilgan_sana, jins, telefon, manzil,
                        universitet_id, fakultet_id, kurs, gpa
                    ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """, (
                    user_id, f["ism"], f["familiya"], f.get("otasining_ismi"),
                    f.get("jshshir") or None,
                    f["tugilgan_sana"], f["jins"], f.get("telefon"), f.get("manzil"),
                    int(f["universitet_id"]), int(f["fakultet_id"]),
                    int(f["kurs"]), float(f.get("gpa") or 0) or None,
                ))

            session["user_id"] = user_id
            flash("Ro'yxatdan o'tildi! Endi grant/stipendiyaga ariza topshirishingiz mumkin.", "success")
            return redirect(url_for("panel"))

        except Exception as e:
            flash(f"Xato: {e}", "danger")

    return render_template("royxat.html", universitetlar=universitetlar, fakultetlar=fakultetlar)


@app.route("/chiqish", methods=["POST"])
def chiqish():
    session.clear()
    flash("Tizimdan chiqdingiz.", "info")
    return redirect(url_for("index"))


# ====================================================================
# Talaba paneli
# ====================================================================
@app.route("/panel")
@login_required
def panel():
    user = current_user()
    if user["rol"] != "talaba":
        return redirect(url_for("admin_dashboard"))

    talaba = db.fetch_one("""
        SELECT t.*, u.qisqa_nomi AS universitet, f.nomi AS fakultet
        FROM talabalar t
        JOIN universitetlar u ON u.id = t.universitet_id
        JOIN fakultetlar f    ON f.id = t.fakultet_id
        WHERE t.foydalanuvchi_id = %s
    """, (user["id"],))
    if not talaba:
        flash("Talaba ma'lumotlari topilmadi.", "danger")
        return redirect(url_for("index"))

    arizalar = db.fetch_all("""
        SELECT a.id, a.ariza_turi, a.holat, a.topshirilgan_sana, a.izoh,
               COALESCE(g.nomi, s.nomi) AS dastur_nomi,
               COALESCE(g.summa, s.oylik_summa) AS summa
        FROM arizalar a
        LEFT JOIN grantlar      g ON g.id = a.grant_id
        LEFT JOIN stipendiyalar s ON s.id = a.stipendiya_id
        WHERE a.talaba_id = %s
        ORDER BY a.topshirilgan_sana DESC
    """, (talaba["id"],))

    statistika = db.fetch_one(
        "SELECT * FROM v_talaba_statistikasi WHERE talaba_id = %s",
        (talaba["id"],),
    )

    return render_template("panel.html", talaba=talaba, arizalar=arizalar, statistika=statistika)


@app.route("/ariza/<string:tur>/<int:obj_id>", methods=["GET", "POST"])
@login_required
def ariza_yaratish(tur: str, obj_id: int):
    if tur not in ("grant", "stipendiya"):
        abort(404)

    user = current_user()
    talaba = db.fetch_one(
        "SELECT id FROM talabalar WHERE foydalanuvchi_id = %s",
        (user["id"],),
    )
    if not talaba:
        flash("Avval talaba sifatida ro'yxatdan o'ting.", "warning")
        return redirect(url_for("royxat"))

    if tur == "grant":
        obj = db.fetch_one("SELECT * FROM grantlar WHERE id = %s AND aktiv = TRUE", (obj_id,))
    else:
        obj = db.fetch_one("SELECT * FROM stipendiyalar WHERE id = %s AND aktiv = TRUE", (obj_id,))
    if not obj:
        abort(404)

    if request.method == "POST":
        try:
            if tur == "grant":
                db.execute("""
                    INSERT INTO arizalar (talaba_id, ariza_turi, grant_id, ariza_matni)
                    VALUES (%s, 'grant', %s, %s)
                """, (talaba["id"], obj_id, request.form.get("ariza_matni", "")))
            else:
                db.execute("""
                    INSERT INTO arizalar (talaba_id, ariza_turi, stipendiya_id, ariza_matni)
                    VALUES (%s, 'stipendiya', %s, %s)
                """, (talaba["id"], obj_id, request.form.get("ariza_matni", "")))

            flash("Ariza muvaffaqiyatli topshirildi!", "success")
            return redirect(url_for("panel"))
        except psycopg2_error_dup() as e:
            flash(f"Xato: bu dasturga allaqachon ariza topshirgansiz. ({e})", "danger")
        except Exception as e:
            flash(f"Xato: {e}", "danger")

    return render_template("ariza.html", obj=obj, tur=tur)


def psycopg2_error_dup():
    """psycopg2.errors.UniqueViolation ni qaytaradi (lazy import)."""
    import psycopg2.errors
    return psycopg2.errors.UniqueViolation


# ====================================================================
# Admin paneli
# ====================================================================
@app.route("/admin")
@role_required("admin", "moderator")
def admin_dashboard():
    stats = db.fetch_one("""
        SELECT
            (SELECT COUNT(*) FROM talabalar)        AS talabalar,
            (SELECT COUNT(*) FROM arizalar)         AS jami_arizalar,
            (SELECT COUNT(*) FROM arizalar WHERE holat = 'yuborilgan')        AS yangi,
            (SELECT COUNT(*) FROM arizalar WHERE holat = 'korib_chiqilmoqda') AS korib_chiqilmoqda,
            (SELECT COUNT(*) FROM arizalar WHERE holat = 'tasdiqlangan')      AS tasdiqlangan,
            (SELECT COUNT(*) FROM arizalar WHERE holat = 'rad_etilgan')       AS rad_etilgan
    """)
    universitet_stat = db.fetch_all("SELECT * FROM v_universitet_statistikasi ORDER BY arizalar_soni DESC")
    grant_stat       = db.fetch_all("SELECT * FROM v_grant_statistikasi ORDER BY jami_arizalar DESC")
    return render_template("admin/dashboard.html",
                           stats=stats, universitet_stat=universitet_stat, grant_stat=grant_stat)


@app.route("/admin/arizalar")
@role_required("admin", "moderator")
def admin_arizalar():
    holat = request.args.get("holat", "")
    sql = "SELECT * FROM v_aktiv_arizalar"
    params: tuple = ()
    if holat in ("yuborilgan", "korib_chiqilmoqda", "tasdiqlangan", "rad_etilgan"):
        sql = """
            SELECT a.id AS ariza_id, a.ariza_turi, a.holat, a.topshirilgan_sana,
                   t.id AS talaba_id, (t.familiya || ' ' || t.ism) AS talaba_fio,
                   t.gpa, t.kurs, u.qisqa_nomi AS universitet, f.nomi AS fakultet,
                   COALESCE(g.nomi, s.nomi) AS dastur_nomi,
                   COALESCE(g.summa, s.oylik_summa) AS summa
            FROM arizalar a
            JOIN talabalar      t ON t.id = a.talaba_id
            JOIN universitetlar u ON u.id = t.universitet_id
            JOIN fakultetlar    f ON f.id = t.fakultet_id
            LEFT JOIN grantlar       g ON g.id = a.grant_id
            LEFT JOIN stipendiyalar  s ON s.id = a.stipendiya_id
            WHERE a.holat = %s
            ORDER BY a.topshirilgan_sana DESC
        """
        params = (holat,)
    arizalar = db.fetch_all(sql, params)
    return render_template("admin/arizalar.html", arizalar=arizalar, holat=holat)


@app.route("/admin/arizalar/<int:ariza_id>", methods=["GET", "POST"])
@role_required("admin", "moderator")
def admin_ariza_detail(ariza_id: int):
    user = current_user()

    if request.method == "POST":
        yangi_holat = request.form.get("holat")
        izoh        = request.form.get("izoh", "")
        if yangi_holat not in ("korib_chiqilmoqda", "tasdiqlangan", "rad_etilgan"):
            flash("Noto'g'ri holat tanlandi.", "danger")
        else:
            db.execute("""
                UPDATE arizalar
                   SET holat = %s, izoh = %s, korib_chiqdi_id = %s
                 WHERE id = %s
            """, (yangi_holat, izoh, user["id"], ariza_id))
            flash("Ariza holati yangilandi.", "success")
            return redirect(url_for("admin_arizalar"))

    ariza = db.fetch_one("""
        SELECT a.*,
               t.familiya || ' ' || t.ism AS talaba_fio,
               t.gpa, t.kurs, t.telefon,
               u.qisqa_nomi AS universitet, f.nomi AS fakultet,
               COALESCE(g.nomi, s.nomi) AS dastur_nomi,
               COALESCE(g.summa, s.oylik_summa) AS summa
        FROM arizalar a
        JOIN talabalar t      ON t.id = a.talaba_id
        JOIN universitetlar u ON u.id = t.universitet_id
        JOIN fakultetlar f    ON f.id = t.fakultet_id
        LEFT JOIN grantlar      g ON g.id = a.grant_id
        LEFT JOIN stipendiyalar s ON s.id = a.stipendiya_id
        WHERE a.id = %s
    """, (ariza_id,))
    if not ariza:
        abort(404)

    tarix = db.fetch_all("""
        SELECT aht.*, fy.email AS ozgartiruvchi_email
        FROM ariza_holati_tarixi aht
        LEFT JOIN foydalanuvchilar fy ON fy.id = aht.ozgartiruvchi_id
        WHERE aht.ariza_id = %s
        ORDER BY aht.ozgartirilgan DESC
    """, (ariza_id,))

    return render_template("admin/ariza_detail.html", ariza=ariza, tarix=tarix)


@app.route("/admin/talabalar")
@role_required("admin", "moderator")
def admin_talabalar():
    rows = db.fetch_all("""
        SELECT t.id, t.familiya, t.ism, t.gpa, t.kurs,
               u.qisqa_nomi AS universitet, f.nomi AS fakultet,
               fy.email,
               (SELECT COUNT(*) FROM arizalar a WHERE a.talaba_id = t.id) AS arizalar_soni
        FROM talabalar t
        JOIN universitetlar u   ON u.id = t.universitet_id
        JOIN fakultetlar    f   ON f.id = t.fakultet_id
        JOIN foydalanuvchilar fy ON fy.id = t.foydalanuvchi_id
        ORDER BY t.gpa DESC NULLS LAST
    """)
    return render_template("admin/talabalar.html", talabalar=rows)


@app.route("/admin/grantlar/yangi", methods=["GET", "POST"])
@role_required("admin")
def admin_grant_yangi():
    if request.method == "POST":
        f = request.form
        try:
            db.execute("""
                INSERT INTO grantlar (
                    nomi, tavsif, beruvchi_tashkilot, summa,
                    minimal_gpa, minimal_kurs, maksimal_kurs, jins_talab,
                    ariza_boshlanishi, ariza_tugashi
                ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                f["nomi"], f.get("tavsif"), f["beruvchi_tashkilot"], float(f["summa"]),
                float(f.get("minimal_gpa") or 3.0), int(f.get("minimal_kurs") or 1),
                int(f.get("maksimal_kurs") or 6), f.get("jins_talab") or None,
                f["ariza_boshlanishi"], f["ariza_tugashi"],
            ))
            flash("Yangi grant qo'shildi.", "success")
            return redirect(url_for("grantlar_list"))
        except Exception as e:
            flash(f"Xato: {e}", "danger")
    return render_template("admin/grant_yangi.html")


# ====================================================================
# Xato sahifalari
# ====================================================================
@app.errorhandler(403)
def err_403(_):
    return render_template("xato.html", kod=403, xabar="Sizda bu sahifaga ruxsat yo'q."), 403


@app.errorhandler(404)
def err_404(_):
    return render_template("xato.html", kod=404, xabar="Sahifa topilmadi."), 404


@app.errorhandler(500)
def err_500(_):
    return render_template("xato.html", kod=500, xabar="Server xatosi."), 500


# ====================================================================
# Sog'liqni tekshirish (Render uchun)
# ====================================================================
@app.route("/health")
def health():
    try:
        db.fetch_one("SELECT 1 AS ok")
        return {"status": "ok", "db": "connected"}, 200
    except Exception as e:
        return {"status": "error", "db": str(e)}, 500


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5000)),
        debug=os.environ.get("FLASK_DEBUG", "0") == "1",
    )
