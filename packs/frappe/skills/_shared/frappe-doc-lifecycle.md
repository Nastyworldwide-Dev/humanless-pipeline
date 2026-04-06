# Frappe Document Lifecycle

## Hook Execution Order

### Save (new document)
1. `before_insert` — before first save to DB
2. `validate` — validate fields, calculate derived values
3. `before_save` — last chance before DB write
4. `after_insert` — after first save (has name now)
5. `on_update` — after every save (insert or update)
6. `on_change` — after on_update, only if doc actually changed
7. `after_save` — cleanup, notifications

### Save (existing document)
1. `validate`
2. `before_save`
3. `on_update`
4. `on_change` (if changed)
5. `after_save`

### Submit
1. `validate`
2. `before_save`
3. `before_submit`
4. `on_submit`
5. `on_update`
6. `after_save`
7. `on_change`

### Cancel
1. `before_cancel`
2. `on_cancel`
3. `on_update`
4. `after_save`
5. `on_change`

### Amend
1. `before_insert` (on the amended copy)
2. `validate`
3. `before_save`
4. `after_insert`
5. `on_update`
6. `on_change`

### Delete
1. `on_trash`
2. `after_delete`

## Key Rules
- `validate` — NEVER call frappe.db here. Use for field validation and calculation only.
- `on_update` — safe for DB operations, but document is already saved
- `flags.ignore_validate` — check this before expensive validation
- `flags.ignore_permissions` — check this before permission checks
- `flags.in_import` — True during data import, skip notifications
- `flags.in_patch` — True during bench migrate, skip validations

## Common Patterns
```python
def validate(self):
    if self.flags.ignore_validate:
        return
    self.validate_qty()
    self.calculate_totals()

def on_update(self):
    self.update_stock_ledger()
    self.make_gl_entries()

def on_submit(self):
    self.update_status("Submitted")
    frappe.enqueue(self.send_notification)
```
