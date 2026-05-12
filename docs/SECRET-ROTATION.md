# Secret rotation log

The following secrets sit in EMSConfig.json (or in source) today.
All three will be rotated and moved to DPAPI store in Phase 1 (tasks P1-T01, P1-T02).
Treat the current values as already-leaked.

| Secret | Current location | Owner | Rotated on | New location |
|---|---|---|---|---|
| Database.Password | EMSConfig.json | DBA | (Phase 1) | DPAPI key `DB_PASSWORD` |
| API.JWTSecretKey | EMSConfig.json | Security | (Phase 1) | DPAPI key `JWT_SECRET` |
| LDAP.BindPassword | EMSConfig.json | AD admin | (Phase 1) | DPAPI key `LDAP_BIND_PW` |
