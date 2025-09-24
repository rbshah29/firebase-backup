#!/bin/bash

SOURCE_BUCKET="test.firebasestorage.app"
BACKUP_BUCKET="test-dev-backups.firebasestorage.app"

echo "=== Firebase Storage Deleted Files Finder ==="
echo "Source bucket: $SOURCE_BUCKET"
echo "Backup bucket: $BACKUP_BUCKET"
echo ""

TEMP_DIR=$(mktemp -d)
SOURCE_FILES="$TEMP_DIR/source_files.txt"
BACKUP_FILES="$TEMP_DIR/backup_files.txt"
DELETED_FILES="$TEMP_DIR/deleted_files.txt"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Scanning source bucket..."
gsutil ls -r gs://$SOURCE_BUCKET/ | grep -E '\.(jpg|jpeg|png|gif|zip|pdf|txt|doc|docx)$' | sort > "$SOURCE_FILES"
source_count=$(wc -l < "$SOURCE_FILES")
echo "Found $source_count files in source bucket"

echo ""
echo "Scanning backup bucket (current versions only)..."
gsutil ls -r gs://$BACKUP_BUCKET/ | grep -v '_backup_markers/' | grep -E '\.(jpg|jpeg|png|gif|zip|pdf|txt|doc|docx)$' | sort > "$BACKUP_FILES"
backup_count=$(wc -l < "$BACKUP_FILES")
echo "Found $backup_count files in backup bucket"

echo ""
echo "Comparing buckets to find deleted files..."

sed "s|gs://$SOURCE_BUCKET/||" "$SOURCE_FILES" > "$TEMP_DIR/source_names.txt"
sed "s|gs://$BACKUP_BUCKET/||" "$BACKUP_FILES" > "$TEMP_DIR/backup_names.txt"

comm -13 "$TEMP_DIR/source_names.txt" "$TEMP_DIR/backup_names.txt" > "$TEMP_DIR/deleted_names.txt"

# Create full URLs for deleted files
while IFS= read -r filename; do
    if [ -n "$filename" ]; then
        echo "gs://$BACKUP_BUCKET/$filename"
    fi
done < "$TEMP_DIR/deleted_names.txt" > "$DELETED_FILES"

deleted_count=$(wc -l < "$DELETED_FILES")

echo ""
echo "=== RESULTS ==="
echo "Files in source: $source_count"
echo "Files in backup: $backup_count"
echo "Deleted files found: $deleted_count"
echo ""

if [ $deleted_count -eq 0 ]; then
    echo "No deleted files found. All files in backup are present in source."
    exit 0
fi

echo "=== DELETED FILES ==="
cat "$DELETED_FILES" | while IFS= read -r deleted_file; do
    if [ -n "$deleted_file" ]; then
        filename=$(basename "$deleted_file")
        folder=$(dirname "$deleted_file" | sed "s|gs://$BACKUP_BUCKET/||")
        echo "$folder/$filename"
    fi
done
echo ""

# Check if restore was requested
if [ "$1" = "restore" ]; then
    echo "=== RESTORING DELETED FILES ==="
    restored=0
    failed=0
    
    cat "$DELETED_FILES" | while IFS= read -r backup_file; do
        if [ -n "$backup_file" ]; then
            relative_path=$(echo "$backup_file" | sed "s|gs://$BACKUP_BUCKET/||")
            source_file="gs://$SOURCE_BUCKET/$relative_path"
            
            echo "Restoring: $relative_path"
            if gsutil cp "$backup_file" "$source_file" 2>/dev/null; then
                echo "Restored successfully"
                ((restored++))
            else
                echo "Failed to restore"
                ((failed++))
            fi
        fi
    done
    
elif [ $deleted_count -gt 0 ]; then
    echo "To restore these files, run:"
    echo "./find_deleted_files.sh restore"
    echo ""
    echo "Or restore individual files manually:"
    cat "$DELETED_FILES" | while IFS= read -r backup_file; do
        if [ -n "$backup_file" ]; then
            relative_path=$(echo "$backup_file" | sed "s|gs://$BACKUP_BUCKET/||")
            source_file="gs://$SOURCE_BUCKET/$relative_path"
            echo "gsutil cp '$backup_file' '$source_file'"
        fi
    done
fi