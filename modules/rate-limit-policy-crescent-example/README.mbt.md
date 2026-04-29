# moonbit-community/rate_limit_policy_crescent_example

Checked Crescent integration example for `moonbit-community/rate_limit_policy`.

This example keeps token bucket state in application-owned storage, reads time
from `moonbitlang/async`, and returns `429 Too Many Requests` with a
`Retry-After` header when a request exceeds the configured bucket.

Run it with:

```bash
moon test --package moonbit-community/rate_limit_policy_crescent_example --target native
```
