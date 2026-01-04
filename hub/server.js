require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const cookieParser = require('cookie-parser');

const app = express();
const pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    database: process.env.DB_NAME
});

app.set('view engine', 'ejs');
app.use(express.static('public'));
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());

const checkAuth = (req, res, next) => {
    const token = req.cookies.easylife_token;
    if (!token) return res.redirect('/login');
    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        req.user = decoded;
        next();
    } catch (err) {
        res.clearCookie('easylife_token');
        return res.redirect('/login');
    }
};

app.get('/login', (req, res) => {
    if (req.cookies.easylife_token) return res.redirect('/');
    res.render('login', { error: null });
});

app.post('/login', async (req, res) => {
    const { username, password } = req.body;
    try {
        const result = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
        if (result.rows.length === 0) return res.render('login', { error: "Brak użytkownika" });
        const user = result.rows[0];
        const validPass = await bcrypt.compare(password, user.password_hash);
        if (!validPass) return res.render('login', { error: "Błędne hasło" });

        const token = jwt.sign({ user_id: user.id, username: user.username }, process.env.JWT_SECRET, { expiresIn: '24h' });
        res.cookie('easylife_token', token, { httpOnly: true, domain: process.env.COOKIE_DOMAIN || undefined });
        res.redirect('/');
    } catch (err) {
        res.render('login', { error: "Błąd serwera" });
    }
});

app.get('/', checkAuth, async (req, res) => {
    const result = await pool.query('SELECT * FROM apps WHERE is_active = TRUE ORDER BY id ASC');
    res.render('dashboard', { user: req.user, apps: result.rows });
});

app.listen(process.env.PORT || 80, () => console.log('Hub running'));