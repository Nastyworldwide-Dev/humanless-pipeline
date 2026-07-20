---
name: erpnext-app-dev
description: Build and maintain custom Frappe/ERPNext apps correctly — scaffolding, DocTypes, server/client logic, patches, fixtures, permissions, testing, deployment. Load references/gotchas.md before writing Frappe code.
---

# ERPNext / Frappe App Development

Process for building custom apps on Frappe v15 / ERPNext. The deep gotcha list
lives in `references/gotchas.md` — read the section matching your task before coding.

## Step 1: Scaffold & Install

```bash
bench new-app my_app                      # create app skeleton
bench --site mysite.local install-app my_app
bench --site mysite.local migrate
```

- Match branches across frappe / erpnext / custom apps (`version-15` with `version-15`).
- App must appear in `sites/apps.txt` or it silently won't load.
- Key files: `hooks.py` (all integration points), `modules.txt`, `patches.txt`.

## Step 2: Never Modify Core — Use the Customization Ladder

In order of preference:
1. **Custom Field / Property Setter** — via Customize Form, exported as filtered fixtures
2. **Client Script / Server Script** doctypes — for site-specific tweaks
3. **doc_events in hooks.py** — attach logic to core doctypes from your app
4. **override_doctype_class** — subclass a core controller (fragile across upgrades)
5. **Monkey patch** — last resort, document why

Editing frappe/erpnext source directly = lost on next `bench update`. Never do it.

## Step 3: DocType Design

Checklist before creating:
- **Naming**: `autoname` strategy (field:, naming_series:, format:, hash) — hard to change after records exist
- **Submittable?** — docstatus workflow (0 draft / 1 submitted / 2 cancelled) changes everything: submitted docs are immutable except `allow_on_submit` fields
- **Child tables**: `istable: 1`, always accessed through the parent, never standalone
- **Permissions**: roles + permlevels at design time, not after go-live
- **Track changes**: enable for audit-relevant doctypes

Create via the UI on a dev site, then the JSON lands in your app's module folder — commit it.

## Step 4: Server Logic

- Controller methods on the DocType class; lifecycle order in `references/gotchas.md#lifecycle`
- API endpoints: `@frappe.whitelist()` + explicit permission check — decorator does NOT check doc permissions
- Heavy work: `frappe.enqueue()` to background queues, never in the request cycle
- All DB access parameterized — `frappe.db.sql(query, {"name": name})`, never f-strings

## Step 5: Client Logic

- Form scripts: `frappe.ui.form.on("DocType", { refresh(frm) {...} })`
- `doctype_js` in hooks.py for per-doctype scripts; `app_include_js` only for truly global code
- After JS changes: `bench build --app my_app` (and hard-refresh; assets are cached)

## Step 6: Schema Changes & Patches

- New fields in doctype JSON → applied by `bench migrate`, no patch needed
- **Renaming a field** = data loss unless you write a `rename_field` patch first
- Any data transformation → patch module + entry in `patches.txt`; patches run once per site, in file order, and MUST be idempotent
- `frappe.reload_doc(...)` at the top of any patch that touches fields newer than the last migrate

## Step 7: Fixtures — Always Filtered

```python
fixtures = [
    {"dt": "Custom Field", "filters": [["module", "=", "My App"]]},
    {"dt": "Property Setter", "filters": [["module", "=", "My App"]]},
]
```

Unfiltered fixtures export EVERY record of that doctype and overwrite other apps'
customizations on every migrate. `bench --site X export-fixtures --app my_app` after UI changes.

## Step 8: Test

```bash
bench --site test_site run-tests --app my_app                 # all
bench --site test_site run-tests --module my_app.my_app.doctype.foo.test_foo
```

- Tests subclass `FrappeTestCase` (auto-rollback per test)
- Declare `test_dependencies` / provide test records for linked doctypes
- TDD protocol applies: red → green → refactor (see /tdd skill)
- Logic-bearing code (pricing, rounding, permissions, doc-state transitions):
  add a hypothesis property test — patterns + declarative-fixture rules in
  `references/property-testing.md`. The spec's `PROPERTY TESTS: REQUIRED`
  line makes tdd-gate block without one.

## Step 9: Deploy

```bash
bench --site X backup            # ALWAYS before migrate
git pull && bench migrate        # schema + patches + fixtures
bench build --app my_app         # if JS/CSS changed
bench restart                    # if hooks.py or any .py changed (Python is memory-resident)
bench --site X clear-cache       # if doctype JSON / client scripts changed
```

`hooks.py` edits require a restart — migrate alone does not reload Python workers.

## Gotcha Lookup

Before writing code, read the matching section of `references/gotchas.md`:

| Task | Section |
|---|---|
| Reads/writes via ORM | ORM & Database |
| Controller/hooks logic | Document Lifecycle |
| Endpoints, roles, user access | Permissions |
| Field/schema changes | Schema & Patches |
| hooks.py wiring | hooks.py |
| Form scripts, buttons | Client-Side |
| Background jobs | Background Jobs |
| Money, dates, floats | Data Types & Precision |
| Anything user-facing | Security |
