# API and WebDAV Integration

## Recommended Pattern

Use server-to-server access:

```text
Browser -> Project Backend -> oCIS HTTPS API/WebDAV
```

This keeps project credentials out of browsers and normally avoids CORS.

## Project Identity

For each project:

1. Create a dedicated technical user.
2. Create a dedicated Project Space.
3. Grant only the minimum role on that Space.
4. Create an expiring App Token using the supported `auth-app` mechanism.
5. Store the token only in that project's server-side secret store.
6. Record owner, issue date, expiry, rotation, and revocation procedure.

Do not use `OCIS_SERVICE_ACCOUNT_ID`/`SECRET` for the ten project integrations.
Official documentation describes that account as an inter-service admin account,
not a tenant-isolated application credential.

## File Reference Model

Each project may store only references in its own PostgreSQL schema, for example:

```text
id UUID
owncloud_file_id
owncloud_space_id
file_name
file_path
owner_id
mime_type
size_bytes
created_at
updated_at
```

Do not store binary file data in PostgreSQL and do not redesign unrelated
schemas. Validate the target schema's existing columns before adding anything.

## Operations

- Upload: authorize, stream request body, capture oCIS file/space identifiers,
  then commit the application reference only after oCIS confirms success.
- Download: authorize against project metadata and Space membership, then stream
  from oCIS without exposing S3 or admin credentials.
- Rename/delete: authorize first, call oCIS, then update the project reference in
  a transaction. Define reconciliation for partial failures.
- Log identifiers and outcomes, never tokens or authorization headers.

Official auth-app reference:
https://doc.owncloud.com/ocis/latest/admin/deployment/services/s-list/auth-app.html

