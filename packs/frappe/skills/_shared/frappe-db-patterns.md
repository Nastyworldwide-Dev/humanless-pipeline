# Frappe Database Patterns

## Safe Query Patterns
```python
# ORM — preferred for single documents
doc = frappe.get_doc("Sales Invoice", name)
doc.status = "Paid"
doc.save()

# get_all — preferred for lists
invoices = frappe.get_all("Sales Invoice",
    filters={"status": "Unpaid", "company": company},
    fields=["name", "grand_total", "customer"],
    order_by="creation desc",
    limit_page_length=20
)

# get_value — single field lookup
customer = frappe.db.get_value("Sales Invoice", name, "customer")

# count
total = frappe.db.count("Sales Invoice", {"status": "Unpaid"})
```

## Parameterized SQL (when ORM isn't enough)
```python
# GOOD: parameterized
result = frappe.db.sql("""
    SELECT name, grand_total
    FROM `tabSales Invoice`
    WHERE customer = %s AND status = %s
""", (customer, status), as_dict=True)

# BAD: string interpolation (SQL injection risk!)
result = frappe.db.sql(f"SELECT * FROM `tabSales Invoice` WHERE customer='{customer}'")
```

## Bulk Operations
```python
# Bulk insert (fast, bypasses hooks)
frappe.db.bulk_insert("Sales Invoice Item", items_list)

# Bulk update via set_value (fires on_change)
frappe.db.set_value("Sales Invoice", name, "status", "Paid")

# Bulk update via SQL (fast, bypasses hooks)
frappe.db.sql("UPDATE `tabSales Invoice` SET status='Paid' WHERE name IN %s", [names])
frappe.db.commit()
```

## Performance Rules
1. Never query inside a loop — batch with `get_all` + `filters`
2. Use `pluck="name"` for simple name lists
3. Use `limit_page_length=0` carefully — can return millions of rows
4. Index columns used in WHERE clauses
5. Use `frappe.db.exists()` instead of `get_value()` for existence checks

## Transaction Rules
- Frappe auto-commits after each request
- Use `frappe.db.commit()` only in background jobs or after bulk operations
- Use `frappe.db.savepoint()` for partial rollbacks
- Never `frappe.db.commit()` inside document hooks — Frappe handles this
