# Frappe Error Patterns

## User-Facing Errors (use frappe.throw)
```python
# Validation error — shown to user as red banner
frappe.throw(_("Quantity cannot be negative"), frappe.ValidationError)

# Permission error
frappe.throw(_("Not permitted to approve"), frappe.PermissionError)

# Mandatory field
frappe.throw(_("{0} is required").format(frappe.bold("Customer")), frappe.MandatoryError)
```

## System Errors (use raise)
```python
# Programming errors — should not happen in production
raise ValueError(f"Unknown status: {status}")
raise TypeError(f"Expected dict, got {type(data)}")
```

## Rule: frappe.throw vs raise
- `frappe.throw` -> user did something wrong -> show message, rollback transaction
- `raise` -> code has a bug -> let it bubble up to error log

## Common Mistakes
1. Using `frappe.throw` for programming errors -> hides bugs
2. Using `raise` for validation -> ugly traceback shown to user
3. Catching broad `Exception` -> swallows real bugs
4. Not using `_()` for translatable messages

## Transaction Safety
```python
# BAD: partial update on error
def on_submit(self):
    self.update_stock()    # succeeds
    self.make_gl_entries() # fails -> stock updated but no GL entries!

# GOOD: let Frappe handle rollback
def on_submit(self):
    self.update_stock()
    self.make_gl_entries()
    # If any step fails, entire transaction rolls back

# MANUAL SAVEPOINT: when you need partial commits
frappe.db.savepoint("before_risky_operation")
try:
    risky_operation()
except Exception:
    frappe.db.rollback(save_point="before_risky_operation")
    frappe.log_error("Risky operation failed")
```

## Error Logging
```python
# Log full traceback to Error Log doctype
frappe.log_error(title="Stock Update Failed")

# Log with custom message
frappe.log_error(message=f"Failed for item {item}", title="Stock Error")
```
