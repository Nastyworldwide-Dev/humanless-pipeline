# Frappe / ERPNext Gotchas

Hard-won failure modes, organized by task. Targets Frappe v15.

## ORM & Database

- **`frappe.get_all` IGNORES permissions; `frappe.get_list` applies them.** Using
  `get_all` in a whitelisted endpoint leaks rows the caller shouldn't see. In user-facing
  code paths, use `get_list` or check permissions explicitly.
- **`frappe.db.sql` bypasses permissions entirely** — and injection-prone if you build
  strings. Always parameterize: `frappe.db.sql("... where name=%(n)s", {"n": name})`.
- **`frappe.db.set_value` skips validation and ALL lifecycle hooks** (no `validate`, no
  `on_update`). Fast, but use it only for flags/counters where hooks genuinely don't
  matter. It also skips `modified` bumping unless `update_modified=True` (default True —
  but setting it False then saving the doc later triggers `TimestampMismatchError`).
- **`Document has been modified` (TimestampMismatchError)** — you're saving a stale
  in-memory doc after something else wrote the row. Fix: `doc.reload()` before mutating,
  or restructure so only one code path saves. Do NOT "fix" with `ignore_version` or
  blanket `frappe.db.set_value`.
- **`frappe.get_cached_doc` can return stale data** after direct `db.set_value`/SQL
  writes — those don't invalidate the cache. After raw writes, use `frappe.get_doc`
  or `frappe.clear_document_cache(doctype, name)`.
- **Never call `frappe.db.commit()` in request handlers** — Frappe commits automatically
  on request success and rolls back on exception; a manual commit mid-request breaks
  atomicity (half-applied documents on later failure). Explicit commits belong only in
  background jobs, patches, and long-running loops (commit per chunk).
- **Exceptions roll back the whole transaction** — including rows you "already saved"
  earlier in the same request. If you need error logging that survives rollback, Frappe's
  `frappe.log_error` handles this via a separate connection; your own writes won't.
- **Child tables are not standalone** — rows carry `parent`, `parenttype`, `parentfield`.
  Query them with those filters; mutate them through the parent doc and `parent.save()`,
  or the parent's `modified` and version log drift.
- **`frappe.db.get_value` on non-standard tables needs `order_by=None`** — get_value
  applies a default `ORDER BY modified DESC`, which crashes (OperationalError 1054)
  against tables without standard columns: `Singles`, `DefaultValue`, `__Auth`, etc.
  Prefer `frappe.db.get_single_value` for Single fields (it passes `order_by=None`
  internally); when querying `tabSingles` raw, pass `order_by=None` explicitly.

## Document Lifecycle

- **Hook order (save)**: `before_validate → validate → before_save → db write →
  on_update → on_change`. **(submit)**: `before_submit → on_submit`. **(cancel)**:
  `before_cancel → on_cancel`. **(delete)**: `on_trash → after_delete`.
  Set-your-own-fields logic belongs in `validate`/`before_save` (before the write);
  side effects on OTHER documents belong in `on_update`/`on_submit` (after the write).
- **Never `doc.save()` inside that doc's own `on_update`** — infinite recursion. To
  persist a computed value post-write, set it in `before_save` instead, or use
  `db.set_value` deliberately (knowing hooks are skipped).
- **`on_update` fires on every save of a draft; `on_submit` only at docstatus 0→1.**
  Side effects that must happen once (stock/GL postings pattern) go in `on_submit`
  with the reversal in `on_cancel`.
- **Submitted docs are immutable** except fields with `allow_on_submit: 1`. Editing
  anything else needs cancel → amend (creates `DOC-1` amendment) — design fields
  accordingly before go-live.
- **`doc.flags.ignore_permissions = True` and `insert(ignore_permissions=True)`
  propagate further than you think** — e.g. into nested inserts. Scope them to the
  single operation and never set them based on user input.
- **`frappe.new_doc` vs `frappe.get_doc({...})`**: `get_doc` from a dict does not apply
  defaults/fetch-froms until validate; don't assume computed fields exist pre-save.

## Permissions

- **`@frappe.whitelist()` authenticates, it does not authorize.** Every endpoint must
  check `frappe.has_permission(doctype, "read"/"write", doc)` or
  `doc.check_permission("write")` itself. This is the #1 custom-app vulnerability.
- **`allow_guest=True` exposes the endpoint to the whole internet** — no session. Only
  for genuinely public data, with rate limiting (`frappe.rate_limiter`).
- **Everything in `frappe.form_dict` is a string** (or JSON string). `"0"` is truthy;
  numbers need `cint`/`flt`; dicts/lists need `json.loads` / `frappe.parse_json`.
- **`permission_query_conditions` only filters LIST views / `get_list`** — it does not
  stop direct `get_doc` access by name. Pair it with a `has_permission` hook or the
  restriction is cosmetic.
- **User Permissions silently filter link fields and list views** — "missing" records
  in production are often a User Permission on a linked doctype, not a bug.
- **Permlevel >0 fields need explicit role grants per level** — otherwise the field is
  invisible/read-only for everyone but System Manager, and values POSTed to it by
  unprivileged users are silently dropped (which is also how you protect fields).
- **`ignore_permissions=True` in `frappe.get_doc(...).insert()` inside a whitelisted
  method** = any logged-in user can create that document. Grep for this in review.

## Schema & Patches

- **Renaming a fieldname in doctype JSON = new empty column.** Data stays in the old
  column. Write a patch using `frappe.model.utils.rename_field(doctype, old, new)`
  BEFORE the schema change lands, or ship both in one migrate with the patch first.
- **Deleting a DocType does not drop its table** (`tab{DocType}` remains). Recreating
  a doctype with the same name inherits the old table — stale columns and all.
- **Patches run once per site, in `patches.txt` order, and must be idempotent** —
  a patch that throws halfway blocks every subsequent migrate. Guard with
  `if frappe.db.has_column(...)` / `frappe.db.exists(...)`.
- **`frappe.reload_doc(module, "doctype", name)` before touching new fields in a
  patch** — the patch may run before the schema sync for that doctype.
- **`Data` fields are varchar(140)** — URLs and tokens get truncated; use
  `Small Text`/`Long Text`/`Text Editor` appropriately.
- **`Select` stores the raw string** — renaming an option orphans existing rows; write
  a data patch when changing options.
- **Changing fieldtype is a cast, not a migration** — `Data → Int` on non-numeric rows
  fails or zeroes. Patch-clean the data first.
- **Never hand-edit another app's doctype JSON** (including frappe/erpnext). Custom
  Field + Property Setter via fixtures is the upgrade-safe path.

## hooks.py

- **hooks.py changes need `bench restart`** — Python is memory-resident under
  supervisor/gunicorn; migrate and clear-cache do NOT reload it. "My hook doesn't fire"
  is usually this.
- **`doc_events` dotted paths fail silently if wrong** — typo'd module path = hook never
  runs, no error. Verify the path imports: `bench --site X console` →
  `frappe.get_attr("my_app.events.foo")`.
- **`doc_events` on `"*"` runs on EVERY document save site-wide** — keep the handler
  O(1) and early-return fast, or site performance craters.
- **`scheduler_events` require the scheduler to be enabled**
  (`bench --site X enable-scheduler`; check `bench --site X doctor`). On dev benches
  it's often disabled and jobs "mysteriously" never run.
- **Long scheduled jobs go in `"long"` queue** — the default queue timeout (300s) kills
  them mid-run.
- **`override_doctype_class` must subclass the original controller** — replacing it
  wholesale breaks on every upstream method you didn't copy; and two apps overriding
  the same doctype = last app in `apps.txt` order wins.
- **`app_include_js` loads on EVERY desk page** — use `doctype_js` for per-doctype
  scripts; bloated global bundles slow the whole desk.

## Client-Side (Form Scripts)

- **`frm.set_value` triggers the field's change event** — a change handler that
  `set_value`s its own field loops forever. Guard with a flag or compare-before-set.
- **`frappe.call` is async** — code after it runs before the response; use the
  `callback` or `await frappe.call(...)`.
- **Custom buttons duplicate on every refresh** — `refresh` fires often; call
  `frm.clear_custom_buttons()` first or check existence.
- **Child table events are named `{fieldname}_add` / `{fieldname}_remove` on the parent,
  and cell changes fire on the CHILD doctype** — `frappe.ui.form.on("Child DocType",
  "qty", (frm, cdt, cdn) => { const row = locals[cdt][cdn]; ... })`.
- **`frm.set_query` must be set in `setup`/`onload`, not `refresh`-only** — link-field
  filters set late don't apply to the first open.
- **Wrap globals in a namespace guard** — multiple client scripts share scope;
  redeclared `const` at top level breaks all scripts on the form.
- **`hasattr(doc, "custom_field")` is ALWAYS True on Frappe documents** (getattr is
  overridden). Server-side, check `doc.meta.has_field("custom_field")` or
  `doc.get("custom_field")` instead.

## Background Jobs

- **Pass names, not Document objects, to `frappe.enqueue`** — args are pickled; docs
  are stale by execution time. Re-fetch inside the job.
- **Jobs must manage their own commits** — auto-commit happens at job end; a job
  processing 10k rows should commit per chunk or a late failure rolls back everything.
- **Deduplicate with `job_id=` + `deduplicate=True`** — double-enqueue from double-click or
  retry storms is the norm, not the exception.
- **In tests, `frappe.enqueue` runs synchronously** (`frappe.flags.in_test`) — passing
  tests do not prove queue behavior; check worker logs on the bench.
- **`frappe.session.user` inside a job is whoever enqueued it** — permission checks in
  job code behave differently than you tested as Administrator.

## Data Types & Precision

- **Use `flt()` and `cint()` on any external input** — form_dict values, CSV imports,
  API payloads are strings; `"1" + 1` is a TypeError, `flt(None)` is safely 0.0.
- **Currency math: `flt(value, doc.precision("fieldname"))`** — float accumulation
  across child rows drifts totals by 0.01; ERPNext validates totals and will reject.
- **Dates are strings until you `getdate()`/`get_datetime()`** — comparing string dates
  works until formats differ. `frappe.utils.nowdate()` for today, `now_datetime()` tz-aware.
- **Timezones**: DB stores naive datetimes in the SITE timezone (System Settings), not
  UTC. Converting for external APIs needs explicit handling
  (`frappe.utils.get_system_timezone()`).
- **`doc.get("field")` returns `None` for empty, `0` for unset Check fields** —
  Check fields are ints (0/1), never bools, in the DB.

## Security

- **Parameterized SQL only** — `frappe.db.sql(f"... {user_input}")` is injection.
  Also true for `order_by`/`group_by` kwargs built from user input in `get_all`
  (v15 validates identifiers, but don't rely on it — allowlist).
- **`frappe.msgprint`/`frappe.throw` render HTML** — interpolating user data without
  `frappe.utils.escape_html` is stored/reflected XSS in the desk.
- **Never `eval`; use `frappe.safe_eval`** with a restricted namespace — and treat even
  safe_eval on user input as a finding.
- **Private files are permission-checked, public files are not** — anything under
  `/files/` is world-readable by URL. Attachments with PII must be private
  (`is_private: 1`).
- **Don't log secrets** — `frappe.log_error(frappe.as_json(doc))` on a doctype holding
  API keys puts them in Error Log, readable by System Managers and often shipped to
  monitoring.

## Bench / Ops

- **Always `bench --site X backup` before migrate** — patches are one-way.
- **`bench update` runs migrate on ALL sites of the bench** — a broken patch in your
  app blocks every site. Test migrate on a staging site first.
- **Asset changes need `bench build --app my_app`** and users need a hard refresh —
  "my JS change does nothing" is cached assets ~90% of the time. `bench clear-cache`
  for server-rendered/doctype-meta changes.
- **`site_config.json` (per-site) overrides `common_site_config.json`** — env-specific
  keys (keys, hosts) go per-site; worker/redis config goes common.
- **`bench start` (Procfile) vs production (supervisor + nginx)** — hooks like
  `before_request` behave the same, but scheduler and workers only run if their
  processes exist; production changes need `sudo supervisorctl restart all`, not Ctrl-C.
- **Version pinning**: frappe, erpnext, and every custom app must track the same major
  branch (`version-15`). Mixed branches fail on import of moved utils — check
  `bench version` when errors mention missing `frappe.utils` members.
