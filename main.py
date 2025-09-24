import functions_framework
from google.cloud import storage
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SOURCE_BUCKET = 'test.firebasestorage.app'
DESTINATION_BUCKET = 'test-dev-backups.firebasestorage.app'

def get_next_version_number(destination_bucket):
    try:
        blobs = destination_bucket.list_blobs(prefix='_backup_markers/backup_v-')
        version_numbers = []
        
        for blob in blobs:
            filename = blob.name.split('/')[-1]
            if filename.startswith('backup_v-'):
                try:
                    version_part = filename.split('_')[1]
                    version_num = int(version_part.split('-')[1])
                    version_numbers.append(version_num)
                except (IndexError, ValueError):
                    continue
        
        return max(version_numbers) + 1 if version_numbers else 1
        
    except Exception as e:
        logger.warning(f"Could not determine version number, defaulting to v-1: {str(e)}")
        return 1

@functions_framework.http
def backup_firebase_storage(request):
    try:
        storage_client = storage.Client(project='test-dev-backups')
        
        source_bucket = storage_client.bucket(SOURCE_BUCKET)
        destination_bucket = storage_client.bucket(DESTINATION_BUCKET)
        
        readable_date = datetime.now().strftime('%Y%m%d')
        full_timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
        version_string = readable_date
        
        logger.info(f"Starting backup {version_string} from {SOURCE_BUCKET} to {DESTINATION_BUCKET}")
        
        existing_backup_files = {blob.name for blob in destination_bucket.list_blobs() 
                               if not blob.name.startswith('_backup_markers/')}
        
        source_blobs = list(source_bucket.list_blobs())
        current_source_files = {blob.name for blob in source_blobs}
        
        copied_count = 0
        error_count = 0
        
        for blob in source_blobs:
            try:
                destination_blob = source_bucket.copy_blob(
                    blob, 
                    destination_bucket, 
                    blob.name
                )
                
                destination_blob.metadata = {
                    'backup_version': version_string,
                    'backup_date': full_timestamp,
                    'backup_source': SOURCE_BUCKET
                }
                destination_blob.patch()
                
                copied_count += 1
                logger.info(f"Copied: {blob.name}")
                
            except Exception as e:
                if "404" in str(e) and "No such object" in str(e):
                    logger.info(f"Skipping phantom file (doesn't exist): {blob.name}")
                else:
                    error_count += 1
                    logger.error(f"Error copying {blob.name}: {str(e)}")
        
        deleted_files = existing_backup_files - current_source_files
        if deleted_files:
            logger.info(f"Files deleted from source (preserved in backup): {list(deleted_files)}")
        
        logger.info(f"Backup {version_string} completed. Files copied: {copied_count}, Errors: {error_count}, Deleted files preserved: {len(deleted_files)}")
        
        marker_content = f"""Backup Version: {version_string}
            Backup Date: {full_timestamp}
            Files copied: {copied_count}
            Errors: {error_count}
            Deleted files preserved: {len(deleted_files)}
            Source bucket: {SOURCE_BUCKET}
            Destination bucket: {DESTINATION_BUCKET}
            """
        
        marker_blob = destination_bucket.blob(f"_backup_markers/backup_{version_string}_{full_timestamp}.txt")
        marker_blob.upload_from_string(marker_content)
        logger.info(f"Created backup marker: backup_{version_string}_{full_timestamp}.txt")
        
        return {
            'status': 'success',
            'version': version_string,
            'timestamp': full_timestamp,
            'files_copied': copied_count,
            'errors': error_count,
            'deleted_files_preserved': len(deleted_files)
        }
        
    except Exception as e:
        logger.error(f"Backup failed: {str(e)}")
        raise e