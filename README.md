# watlogs

Workforce & Time Logs — centralized time-tracking application.

## Running the Application

All data is stored in JSON files on the server (no localStorage). Start the server with:

```bash
node server.js
# or
npm start
```

Then open **http://localhost:3000** in your browser.

Default login: **username** `superadmin` / **password** `superadmin`

## Data Files

All data is stored in the `DB/` folder:

| File | Contents |
|------|----------|
| `users.json` | User accounts |
| `sessions.json` | Active/past login sessions |
| `loginhistory.json` | Login/logout history |
| `checkincheckouthistory.json` | Check-in/check-out records |
| `config.json` | System settings |
