# Backend How-To: Drive Storage and Migration

This guide explains how to store OpenM files in real folders on a drive and how to migrate old files.

## 1. What is implemented

- Files are stored in real directories under a storage root.
- Folder structure in the app is mirrored on disk.
- Existing files from the old flat layout can be migrated once.

## 2. Storage root configuration

The backend reads the storage root from environment variable `OPENM_STORAGE_ROOT`.

If not set, default is:

- `OpenM_backend/storage`

## 3. Start with a local drive path

PowerShell example:

```powershell
Set-Location "C:\Users\ÜbernahmeKonto\OpenM\OpenM_backend"
$env:OPENM_STORAGE_ROOT = "D:\OpenM-Files"
uvicorn app.main:app --reload --port 8000
```

## 4. Later switch to a network drive (UNC)

PowerShell example:

```powershell
Set-Location "C:\Users\ÜbernahmeKonto\OpenM\OpenM_backend"
$env:OPENM_STORAGE_ROOT = "\\server\share\openm-files"
uvicorn app.main:app --reload --port 8000
```

## 5. On-disk folder layout

Under the storage root, backend creates:

- `project_<project_id>/`
- nested folders: `<folder_name>_<folder_id-prefix>/`

Example:

- `D:\OpenM-Files\project_abc123\Angebot_f81c2a9b\` 

## 6. One-time migration for old files

After setting `OPENM_STORAGE_ROOT`, run migration once as manager/admin:

- Endpoint: `POST /files/migrate-storage-layout`

Use Swagger:

1. Open `http://127.0.0.1:8000/docs`
2. Login to get token
3. Authorize in Swagger
4. Run `POST /files/migrate-storage-layout`

Response includes:

- `moved`
- `unchanged`
- `skipped_missing_file`
- `skipped_missing_folder`
- `errors`

## 7. Demo template folder (optional)

Demo templates are read from `OpenM_backend/demo_files` by default.
You can override with `OPENM_DEMO_FILES_ROOT`.

```powershell
$env:OPENM_DEMO_FILES_ROOT = "C:\openm-demo-files"
```

## 8. Important notes

- Set the environment variables before starting `uvicorn`.
- The backend process needs read/write permissions on the configured drive path.
- For network shares, ensure the service/user account has access.
