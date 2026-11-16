# Vox web

The same notes, tasks, reminders and alarms as the phone app, in a browser. It reads and writes the
Supabase tables directly, with the same rules as the app, so every device agrees.

Three static files, no build step:

- `index.html` page shell
- `app.css` look: scenery behind smoky dark glass, one ice blue accent
- `app.js` everything else: data, rules, screens, drag and drop

## Run it

Any static file server works. From this folder:

```
python3 -m http.server 8787
```

Then open http://127.0.0.1:8787 and sign in with the same email and password as the app.

To host it for free: push the `Web` folder to GitHub Pages, Netlify or Vercel as a static site.

## What it does

- Home: countdown to the next reminder, Today and Tomorrow, upcoming reminders, every top level note.
- Lists, checklists (foldable tree), boards (columns, sections, filter chips) and folders (colored tiles).
- Drag and drop everywhere: reorder rows, tiles and cards, move cards between columns, drop things
  onto a folder, a list row or a breadcrumb to move them inside. Works with mouse and touch (hold to drag).
- Ticking a card done moves it to the Done column and cancels its reminders, like the phone.
- Right click (or the dots button) for status, rename, move, info and delete. Delete can be undone from the toast.
- Reminders and alarms: add, edit, repeat, link to a task. The phone rings them once Vox syncs.
- Notes: a plain editor that saves as you type.
- History: every voice command from the phone.
- Settings: glass darkness and frost sliders, like the app.

## How it stays in sync

- Every change is written to Supabase at once and shown immediately.
- The page re-reads the tables every 8 seconds, when the tab comes back, and instantly when
  Supabase Realtime is enabled for the tables (Database > Publications > supabase_realtime).
- The phone picks up changes when the app is open or opened. There is no push with a free Apple account.
