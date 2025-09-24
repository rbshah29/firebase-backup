#!/bin/bash
BACKUP_BUCKET="test-dev-backups.firebasestorage.app"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file_path>"
    echo "Example: $0 images/filename.jpg"
    echo "Example: $0 inspections/filename.zip"
    exit 1
fi

FILE_PATH="$1"
FILE_PATH="${FILE_PATH#/}"

echo "Bucket: $BACKUP_BUCKET"
echo "File: $FILE_PATH"
echo ""

FULL_PATH="gs://$BACKUP_BUCKET/$FILE_PATH"

VERSIONS=$(gsutil ls -a "$FULL_PATH" 2>/dev/null)

if [ -z "$VERSIONS" ]; then
    echo "No versions found for: $FILE_PATH"
    echo ""
    echo "Searching for similar files..."
    FILENAME=$(basename "$FILE_PATH")
    gsutil ls -a "gs://$BACKUP_BUCKET/**" | grep "$FILENAME" | head -5
    exit 1
fi

VERSION_COUNT=$(echo "$VERSIONS" | wc -l)
echo "Found $VERSION_COUNT versions"
echo ""

convert_generation_to_date() {
    local generation=$1
    local seconds=$((generation / 1000000))
    if command -v date >/dev/null 2>&1; then
        date -d "@$seconds" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "Invalid timestamp"
    else
        echo "Generation: $generation"
    fi
}

# Function to get file size
get_file_size() {
    local full_url=$1
    gsutil du "$full_url" 2>/dev/null | awk '{print $1}' | head -1
}

echo "ALL VERSIONS"
echo "Version | Generation ID        | Date & Time              | Size"

version_num=1
echo "$VERSIONS" | while IFS= read -r version_url; do
    if [[ "$version_url" == *"#"* ]]; then
        generation=$(echo "$version_url" | grep -o '#[0-9]*' | tail -1 | sed 's/#//')
        
        readable_date=$(convert_generation_to_date "$generation")
        
        size=$(get_file_size "$version_url")
        size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
        
        printf "v%-6d | %-20s | %-24s | %s MB\n" "$version_num" "$generation" "$readable_date" "$size_mb"
    else
        readable_date=$(convert_generation_to_date "$(date +%s)000000")
        size=$(get_file_size "$version_url")
        size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
        
        printf "v%-6d | %-20s | %-24s | %s MB\n" "$version_num" "current" "$readable_date" "$size_mb"
    fi
    version_num=$((version_num + 1))
done

echo ""
echo "=== RESTORE COMMANDS ==="
echo "To restore a specific version:"
echo ""

version_num=1
echo "$VERSIONS" | while IFS= read -r version_url; do
    restore_command="gsutil cp '$version_url' 'gs://test.firebasestorage.app/$FILE_PATH'"
    echo "# Restore version $version_num:"
    echo "$restore_command"
    echo ""
    version_num=$((version_num + 1))
done
