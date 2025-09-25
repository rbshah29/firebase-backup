# This project provides a comprehensive solution for automating daily backups of Firebase Storage data to a separate Google Cloud Storage bucket. It includes setup instructions, deployment steps, and commands for monitoring, recovery, and cleanup.

# For this you need service account with Storage Admin role in backup project and Storage Object Admin role in source project.


# Firebase Storage Automated Backup System [Function Gen 2, Schedular]

## Source Project Setup
```bash
gcloud config set project test
gcloud services enable storage.googleapis.com storagetransfer.googleapis.com
gcloud services enable cloudfunctions.googleapis.com run.googleapis.com

gsutil iam ch \
  serviceAccount:backup@test-dev-backups.iam.gserviceaccount.com:roles/storage.objectAdmin \
  gs://test.firebasestorage.app
```

## Backup Project Setup
```bash
gcloud config set project test-dev-backups
gcloud services enable storage.googleapis.com storagetransfer.googleapis.com
gcloud services enable cloudfunctions.googleapis.com run.googleapis.com

gsutil iam ch \
  serviceAccount:backup@test-dev-backups.iam.gserviceaccount.com:roles/storage.admin \
  gs://test-dev-backups.firebasestorage.app

gsutil versioning set on gs://test-dev-backups.firebasestorage.app

cat > lifecycle-policy.json << 'EOF'
{
  "rule": [
    {
      "action": {
        "type": "Delete"
      },
      "condition": {
        "age": 90,
        "isLive": false
      }
    }
  ]
}
EOF

gsutil lifecycle set lifecycle-policy.json gs://test-dev-backups.firebasestorage.app
```

## Function Files Setup
```bash
mkdir firebase-backup-function
cd firebase-backup-function

cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
EOF

touch main.py
# Add backup function code to main.py
```

## Deploy Function
```bash
gcloud functions deploy firebase-storage-backup \
  --gen2 \
  --runtime=python311 \
  --source=. \
  --entry-point=backup_firebase_storage \
  --trigger-http \
  --service-account=backup@test-dev-backups.iam.gserviceaccount.com
```

## Create Daily Scheduler
```bash
gcloud scheduler jobs create http daily-firebase-backup \
  --schedule="0 2 * * *" \
  --uri="https://northamerica-northeast1-test-dev-backups.cloudfunctions.net/firebase-storage-backup" \
  --http-method=POST \
  --time-zone="America/Toronto" \
  --location="northamerica-northeast1" \
  --description="Daily backup at 2 AM"
```

## Testing Commands
```bash
curl -X POST "https://northamerica-northeast1-test-dev-backups.cloudfunctions.net/firebase-storage-backup"
gcloud scheduler jobs run daily-firebase-backup --location="northamerica-northeast1"
gcloud functions logs read firebase-storage-backup --gen2 --region=northamerica-northeast1 --limit=20
```

## Monitoring & Verification
```bash
gsutil versioning get gs://test-dev-backups.firebasestorage.app
gsutil ls gs://test-dev-backups.firebasestorage.app/
gsutil ls -a gs://test-dev-backups.firebasestorage.app/ | head -20
gsutil lifecycle get gs://test-dev-backups.firebasestorage.app
gsutil ls gs://test-dev-backups.firebasestorage.app/_backup_markers/
gsutil cat gs://test-dev-backups.firebasestorage.app/_backup_markers/backup_20250924_*.txt
gcloud scheduler jobs list --location="northamerica-northeast1"
gcloud scheduler jobs describe daily-firebase-backup --location="northamerica-northeast1"
```

## Recovery Commands
```bash
gsutil ls -a gs://test-dev-backups.firebasestorage.app/path/to/file.jpg
gsutil cp gs://test-dev-backups.firebasestorage.app/path/to/file.jpg#GENERATION_ID gs://test.firebasestorage.app/path/to/file.jpg
gsutil cp gs://test-dev-backups.firebasestorage.app/path/to/file.jpg gs://test.firebasestorage.app/path/to/file.jpg
gsutil -m cp -r gs://test-dev-backups.firebasestorage.app/* gs://test.firebasestorage.app/
```

## Cleanup Commands
```bash
gsutil -m rm -r gs://test-dev-backups.firebasestorage.app/backup_YYYY-MM-DD_*/
gsutil rm gs://test-dev-backups.firebasestorage.app/path/to/file.jpg#GENERATION_ID
gsutil -m rm -a gs://test-dev-backups.firebasestorage.app/**
gcloud functions deploy firebase-storage-backup --gen2 --runtime=python311 --source=.
gcloud scheduler jobs delete daily-firebase-backup --location="northamerica-northeast1"
```

## Recovery Scripts
```bash
# Find deleted files
./find_deleted_files.sh

# Restore all deleted files
./find_deleted_files.sh restore

# View all versions of a file
./file_versions.sh images/09cc1ccc-1a5f-4431-b069-5d426bc0615a.jpg
./file_versions.sh inspections/filename.zip
```
