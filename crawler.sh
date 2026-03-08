#!/bin/sh

URL="$1"
LAYERS="${2:-1}"

if [ -z "$URL" ]; then
    printf "Usage: %s <url> [layers]\n" "$0"
    return 1 2>/dev/null || exit 1
fi

mkdir -p files

> queue_0.txt
> visited.txt
> downloaded.txt

printf "%s\n" "$URL" > queue_0.txt

get_absolute_url() {
    base="$1"
    link="$2"

    # Remove fragment
    link="${link%%#*}"

    case "$link" in
        http://*|https://*|ftp://*)
            printf "%s\n" "$link"
            ;;
        /*)
            domain_part=$(printf "%s\n" "$base" | awk -F/ '{print $1"//"$3}')
            printf "%s\n" "${domain_part}${link}"
            ;;
        *)
            case "$base" in
                */) printf "%s\n" "${base}${link}" ;;
                *)
                    # If base has no path (e.g., https://example.com)
                    domain_part=$(printf "%s\n" "$base" | awk -F/ '{print $1"//"$3}')
                    if [ "$base" = "$domain_part" ]; then
                        printf "%s\n" "${base}/${link}"
                    else
                        base_dir="${base%/*}"
                        printf "%s\n" "${base_dir}/${link}"
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

    ext=$(printf "%s\n" "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
        htm|html|php|asp|aspx|jsp|css|xml|json|com|org|net|in|edu|uk|us|info|io|gov|mil) return 1 ;;
        # As per requirement: links end with .pdf .c .js .cpp .py etc
        pdf|c|js|cpp|py|txt|doc|docx|ppt|pptx|xls|xlsx|zip|tar|gz|rar|bz2|7z|jpg|jpeg|png|gif|svg|mp3|mp4|avi|mkv|webm|webp|h|hpp) return 0 ;;
        *) return 1 ;;
    esac
}

current_layer=0

while [ "$current_layer" -le "$LAYERS" ]; do
    printf "=== Processing Layer %d ===\n" "$current_layer"

    next_layer=$((current_layer + 1))
    > "queue_${next_layer}.txt"

    while IFS= read -r current_url || [ -n "$current_url" ]; do
        [ -z "$current_url" ] && continue

        if grep -Fqx -- "$current_url" visited.txt 2>/dev/null; then
            continue
        fi

        printf "%s\n" "$current_url" >> visited.txt

        if is_target_file_strict "$current_url"; then
            printf "[Layer %d] File found: %s\n" "$current_layer" "$current_url"

            clean_url="${current_url%%\?*}"
            filename="${clean_url##*/}"

            # Directory traversal prevention:
            case "$filename" in
                */*|*\\*|..|.)
                    printf "Invalid filename %s\n" "$filename"
                    continue
                    ;;
            esac

            if [ -z "$filename" ]; then continue; fi

            if ! grep -Fqx -- "$current_url" downloaded.txt 2>/dev/null; then
                printf "Downloading: %s\n" "$current_url"

                # Using --output is safer than -o when combined with --
                curl -sL "$current_url" --output "files/$filename" || wget -q "$current_url" --output-document="files/$filename"

                if [ $? -eq 0 ]; then
                    printf "%s\n" "$current_url" >> downloaded.txt
                fi
            fi
            continue
        fi

        if [ "$current_layer" -lt "$LAYERS" ]; then
            printf "[Layer %d] Crawling: %s\n" "$current_layer" "$current_url"

            content=$(curl -sL "$current_url" 2>/dev/null || wget -qO- "$current_url" 2>/dev/null)

            links=$(printf "%s\n" "$content" | grep -ioE 'href="[^"]*"' | sed -E 's/^href="//i; s/"$//i')
            links2=$(printf "%s\n" "$content" | grep -ioE "href='[^']*'" | sed -E "s/^href='//i; s/'$//i")

            printf "%s\n" "$links" | awk 'NF' | while IFS= read -r link; do
                if printf "%s\n" "$link" | grep -qE "^(mailto:|tel:|javascript:|data:|#)"; then
                    continue
                fi
                abs_url=$(get_absolute_url "$current_url" "$link")
                printf "%s\n" "$abs_url" >> "queue_${next_layer}.txt"
            done

            printf "%s\n" "$links2" | awk 'NF' | while IFS= read -r link; do
                if printf "%s\n" "$link" | grep -qE "^(mailto:|tel:|javascript:|data:|#)"; then
                    continue
                fi
                abs_url=$(get_absolute_url "$current_url" "$link")
                printf "%s\n" "$abs_url" >> "queue_${next_layer}.txt"
            done
        fi

    done < "queue_${current_layer}.txt"

    if [ -f "queue_${next_layer}.txt" ]; then
        sort -u "queue_${next_layer}.txt" > "queue_${next_layer}_tmp.txt"
        mv "queue_${next_layer}_tmp.txt" "queue_${next_layer}.txt"
    fi

    current_layer=$next_layer
done

printf "Done!\n"
