# External Storage Requirements

Status: **BLOCKED — EXTERNAL STORAGE AND DEDICATED NODE REQUIRED**

## Required Inputs

- Dedicated ownCloud node address and owner approval
- Stable ownCloud URL and DNS record
- Trusted TLS certificate and chain for that URL
- `S3_ENDPOINT`
- `S3_REGION`
- `S3_BUCKET`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- Maximum expected upload size and concurrent-upload target
- External backup destination and retention policy

Do not invent, reuse, or copy credentials from another service.

## Storage Placement

| Data class | Required location |
|---|---|
| User file blobs | External S3/S3-compatible object storage |
| oCIS file metadata | POSIX storage on the dedicated ownCloud node or approved shared POSIX/NFS |
| Temporary upload buffers | Dedicated ownCloud node only |
| oCIS configuration | Dedicated ownCloud node |
| Project application references | The project's existing PostgreSQL schema |
| User file binary data | Never PostgreSQL, research-app, or research-db |

The official `s3ng` design stores blobs in S3 but still requires POSIX metadata.
Official documentation also states that the largest expected upload needs at
least the same amount of temporary storage on the Infinite Scale node. Therefore
the requirement “uploads must not touch research-app, even temporarily” cannot
be met by deploying oCIS on research-app.

## Minimum S3 Policy

Grant only the selected bucket or approved prefix. Required operations normally
include listing the bucket and object/multipart-upload operations within the
bucket. Do not grant account-wide S3 administration.

Enable provider-supported encryption, access logging, versioning where approved,
lifecycle rules for incomplete multipart uploads, and a separate backup policy.

## Official References

- https://doc.owncloud.com/ocis/latest/admin/deployment/storage/s3.html
- https://doc.owncloud.com/ocis/latest/admin/prerequisites/prerequisites.html
- https://doc.owncloud.com/ocis/latest/admin/deployment/services/s-list/storage-users.html

