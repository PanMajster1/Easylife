import os, jwt, psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, render_template, request, redirect, jsonify
from functools import wraps
import yfinance as yf
import requests

app = Flask(__name__)
DB_HOST = os.getenv("DB_HOST")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
SHARED_SECRET = os.getenv("SHARED_SECRET")

def get_db():
    return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.cookies.get('easylife_token')
        if not token: return redirect("http://hub.local/login")
        try:
            data = jwt.decode(token, SHARED_SECRET, algorithms=["HS256"])
            return f(data['user_id'], *args, **kwargs)
        except:
            return redirect("http://hub.local/login")
    return decorated

@app.route('/')
@token_required
def dashboard(uid):
    return render_template('dashboard.html')

@app.route('/api/data')
@token_required
def api_data(uid):
    # Logika pobierania danych (uproszczona)
    usd = 4.0 # Fallback
    gold = 2000.0
    try:
        usd = requests.get("http://api.nbp.pl/api/exchangerates/rates/a/usd/?format=json", timeout=2).json()['rates'][0]['mid']
        gold = yf.Ticker("GC=F").fast_info['last_price']
    except: pass

    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM gold_items WHERE user_id = %s", (uid,))
    rows = cur.fetchall()
    conn.close()
    
    portfolio = []
    total_val = 0
    mennica_pln = (gold / 31.1) * usd * 0.98

    for r in rows:
        val = float(r['waga_g']) * mennica_pln
        portfolio.append({"id": r['id'], "typ": r['typ'], "waga": float(r['waga_g']), "zysk": round(val - float(r['cena_zakupu']), 2)})
        total_val += val

    return jsonify({"usd_nbp": usd, "gold_usd": gold, "spot_pln": int(mennica_pln/0.98), "mennica_pln": int(mennica_pln), "total_val": int(total_val), "total_profit": 0, "portfolio": portfolio, "recommendation": "WAIT"})

@app.route('/add', methods=['POST'])
@token_required
def add(uid):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO gold_items (typ, producent, waga_g, cena_zakupu, user_id) VALUES (%s, %s, %s, %s, %s)",
                (request.form['typ'], request.form['prod'], request.form['waga'], request.form['cena'], uid))
    conn.commit()
    conn.close()
    return redirect('/')

@app.route('/delete/<int:id>')
@token_required
def delete(uid, id):
    conn = get_db()
    conn.cursor().execute("DELETE FROM gold_items WHERE id = %s AND user_id = %s", (id, uid))
    conn.commit()
    conn.close()
    return redirect('/')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)