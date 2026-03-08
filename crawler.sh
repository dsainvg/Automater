#!/bin/sh

URL="$1"
LAYERS="${2:-1}"

if [ -z "$URL" ]; then
    echo "Usage: $0 <url> [layers]"
    return 1 2>/dev/null || exit 1
fi

mkdir -p files

> queue_0.txt
> visited.txt
> downloaded.txt

echo "$URL" > queue_0.txt

get_absolute_url() {
    base="$1"
    link="$2"

    # Remove fragment
    link="${link%%#*}"

    case "$link" in
        http://*|https://*|ftp://*)
            echo "$link"
            ;;
        /*)
            domain_part=$(echo "$base" | awk -F/ '{print $1"//"$3}')
            echo "${domain_part}${link}"
            ;;
        *)
            case "$base" in
                */) echo "${base}${link}" ;;
                *)
                    # If base has no path (e.g., https://example.com)
                    domain_part=$(echo "$base" | awk -F/ '{print $1"//"$3}')
                    if [ "$base" = "$domain_part" ]; then
                        echo "${base}/${link}"
                    else
                        base_dir="${base%/*}"
                        echo "${base_dir}/${link}"
                    fi
                    ;;
            esac
            ;;
    esac
}

is_target_file_strict() {
    url="$1"
    clean_url="${url%%\?*}"

    case "$clean_url" in
        */) return 1 ;;
    esac

    ext="${clean_url##*.}"

    if [ "$ext" = "$clean_url" ]; then
        return 1
    fi

    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
        htm|html|php|asp|aspx|jsp|css|xml|json|com|org|net|in|edu|uk|us|info|io|gov|mil) return 1 ;;
        # As per requirement: links end with .pdf .c .js .cpp .py etc
        pdf|c|js|cpp|py|txt|doc|docx|ppt|pptx|xls|xlsx|zip|tar|gz|rar|bz2|7z|jpg|jpeg|png|gif|svg|mp3|mp4|avi|mkv|webm|webp|h|hpp) return 0 ;;
        *) return 1 ;;
    esac
}

current_layer=0

while [ "$current_layer" -le "$LAYERS" ]; do
    echo "=== Processing Layer $current_layer ==="

    next_layer=$((current_layer + 1))
    > "queue_${next_layer}.txt"

    while IFS= read -r current_url || [ -n "$current_url" ]; do
        [ -z "$current_url" ] && continue

        if grep -Fqx "$current_url" visited.txt 2>/dev/null; then
            continue
        fi

        echo "$current_url" >> visited.txt

        if is_target_file_strict "$current_url"; then
            echo "[Layer $current_layer] File found: $current_url"
            filename=$(basename "${current_url%%\?*}")

            if ! grep -Fqx "$current_url" downloaded.txt 2>/dev/null; then
                echo "Downloading: $current_url"
                curl -sL "$current_url" -o "files/$filename" || wget -q "$current_url" -O "files/$filename"
                echo "$current_url" >> downloaded.txt
            fi
            continue
        fi

        if [ "$current_layer" -lt "$LAYERS" ]; then
            echo "[Layer $current_layer] Crawling: $current_url"

            content=$(curl -sL "$current_url" 2>/dev/null || wget -qO- "$current_url" 2>/dev/null)

            links=$(echo "$content" | grep -ioE 'href="[^"]*"' | sed -E 's/^href="//i; s/"$//i')
            links2=$(echo "$content" | grep -ioE "href='[^']*'" | sed -E "s/^href='//i; s/'$//i")

            echo "$links" | awk 'NF' | while IFS= read -r link; do
                if echo "$link" | grep -qE "^(mailto:|tel:|javascript:|#)"; then
                    continue
                fi
                abs_url=$(get_absolute_url "$current_url" "$link")
                echo "$abs_url" >> "queue_${next_layer}.txt"
            done

            echo "$links2" | awk 'NF' | while IFS= read -r link; do
                if echo "$link" | grep -qE "^(mailto:|tel:|javascript:|#)"; then
                    continue
                fi
                abs_url=$(get_absolute_url "$current_url" "$link")
                echo "$abs_url" >> "queue_${next_layer}.txt"
            done
        fi

    done < "queue_${current_layer}.txt"

    if [ -f "queue_${next_layer}.txt" ]; then
        sort -u "queue_${next_layer}.txt" > "queue_${next_layer}_tmp.txt"
        mv "queue_${next_layer}_tmp.txt" "queue_${next_layer}.txt"
    fi

    current_layer=$next_layer
done

echo "Done!"
