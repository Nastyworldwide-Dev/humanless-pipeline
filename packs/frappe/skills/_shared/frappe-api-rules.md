# Frappe API Rules

## Whitelisted Methods
```python
@frappe.whitelist()
def my_api_method(doctype, name, action):
    """Always check permissions in whitelisted methods."""
    frappe.has_permission(doctype, "write", name, throw=True)
    # ... logic
    return {"status": "ok"}
```

## Guest APIs
```python
@frappe.whitelist(allow_guest=True)
def public_endpoint(token):
    """Guest APIs must validate input aggressively."""
    if not token or not isinstance(token, str):
        frappe.throw(_("Invalid token"), frappe.AuthenticationError)
    # ... logic
```

## Response Format
- Return dicts or lists — frappe auto-serializes to JSON
- Never return frappe.response directly
- Use `frappe.response["message"]` only for legacy compatibility

## Client-Side Calls
```javascript
// Standard call
frappe.call({
    method: "myapp.api.my_method",
    args: { doctype: "Sales Invoice", name: "SI-001" },
    callback: (r) => { console.log(r.message) },
    error: (r) => { frappe.msgprint("Failed") }
})

// Async/await pattern
const result = await frappe.xcall("myapp.api.my_method", { name: "SI-001" })
```

## Security Rules
1. Always `frappe.has_permission()` in whitelisted methods
2. Never trust client input — validate type, range, existence
3. Use `frappe.whitelist(methods=["POST"])` for state-changing operations
4. Never expose internal frappe methods as APIs
5. Rate-limit guest endpoints
